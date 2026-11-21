@tool
extends EditorPlugin

const REFRESH_INTERVAL := 0.1
const CATALOG := "res://proximity_prefabs.json"

var _world: Node
var _until_refresh := 0.0
var _catalog: Dictionary = {}
var _catalog_stamp := 0
var _edited_scenes: Dictionary[String, WeakRef] = {}
var _wanted: Dictionary[ProximityPlacement3D, String] = {}
var _previews: Dictionary[ProximityPlacement3D, Node3D] = {}
var _queue: Array[ProximityPlacement3D] = []
var _needed_paths: Dictionary[String, bool] = {}
var _ready_scenes: Dictionary[String, PackedScene] = {}
var _failed_paths: Dictionary[String, bool] = {}
var _unknown_classes: Dictionary[StringName, bool] = {}
var _pending_path := ""


func _enter_tree() -> void:
	_read_catalog()
	scene_changed.connect(_remember_scene)
	scene_saved.connect(_index_saved_scene)
	_remember_scene(EditorInterface.get_edited_scene_root())
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	_retire_previews(get_tree(), _previews.values())
	if not _pending_path.is_empty():
		_release_request(get_tree(), _pending_path)


func _process(delta: float) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root != _world:
		_world = root
		_until_refresh = 0.0
		_failed_paths.clear()

	_until_refresh -= delta
	if _until_refresh <= 0.0:
		_until_refresh = REFRESH_INTERVAL
		_refresh()
	_collect_loaded_scene()
	if not _remove_outdated_preview():
		_mount_or_request()


func _refresh() -> void:
	_wanted.clear()
	_queue.clear()
	_needed_paths.clear()
	var settings := _find_settings()
	var viewport := EditorInterface.get_editor_viewport_3d()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if settings == null or camera == null:
		_ready_scenes.clear()
		return

	var camera_position := camera.global_position
	var center := Vector2(camera_position.x, camera_position.z)
	var scores: Dictionary[ProximityPlacement3D, float] = {}
	# A ordem do SceneTree permite avaliar a colocação pai antes do conteúdo aninhado.
	for node in get_tree().get_nodes_in_group(ProximityPlacement3D.EDITOR_GROUP):
		var placement := node as ProximityPlacement3D
		if placement == null or placement.scene_path.is_empty():
			continue
		var entry: Dictionary = _catalog.get(placement.scene_path, {})
		var path := str(entry.get("preview", ""))
		if path.is_empty():
			path = placement.scene_path
		if path == _world.scene_file_path or not _can_preview(placement, path):
			continue
		if (
			(placement.is_in_group(&"interior_detail") or "interior_detail" in entry.get("groups", []))
			and not _inside_activation_volume(placement, camera_position)
		):
			continue
		var local_bounds: Variant = placement.get_meta(&"stream_bounds", AABB())
		if not local_bounds is AABB or not local_bounds.is_finite():
			continue
		var footprint: AABB = placement.global_transform * local_bounds
		var bounds := Rect2(footprint.position.x, footprint.position.z, footprint.size.x, footprint.size.z)
		var offset := (center - center.clamp(bounds.position, bounds.end)).abs()
		var ranges := _distance_ranges(settings, placement, entry)
		var loaded := _previews.get(placement) as Node3D
		var resident := is_instance_valid(loaded) and loaded.scene_file_path == path
		var limit := ranges.y if resident else ranges.x
		if maxf(offset.x, offset.y) > limit:
			continue
		_wanted[placement] = path
		_needed_paths[path] = true
		if not resident and not _failed_paths.has(path):
			scores[placement] = offset.length_squared()
			_queue.append(placement)

	for path in _ready_scenes.keys():
		if not _needed_paths.has(path):
			_ready_scenes.erase(path)
	_queue.sort_custom(func(a: ProximityPlacement3D, b: ProximityPlacement3D) -> bool:
		return scores[a] > scores[b]
	)


func _can_preview(placement: ProximityPlacement3D, path: String) -> bool:
	var ancestor := placement.get_parent()
	var nested := false
	while ancestor != null and ancestor != _world:
		if ancestor is ProximityPlacement3D:
			var parent_preview := _previews.get(ancestor) as Node3D
			if (
				not is_instance_valid(parent_preview)
				or parent_preview.scene_file_path != _wanted.get(ancestor, "")
				or parent_preview.scene_file_path == path
			):
				return false
			nested = true
		ancestor = ancestor.get_parent()
	return ancestor == _world and (nested or placement.owner == _world)


func _inside_activation_volume(placement: ProximityPlacement3D, point: Vector3) -> bool:
	if placement.activation_volume.has_volume():
		return placement.activation_volume.has_point(placement.to_local(point))
	var ancestor := placement.get_parent()
	while ancestor != null and ancestor != _world:
		var volume: Variant = ancestor.get_meta(&"stream_volume", AABB())
		if ancestor is Node3D and volume is AABB and volume.has_volume():
			return volume.has_point(ancestor.to_local(point))
		ancestor = ancestor.get_parent()
	return false


func _distance_ranges(settings: ProximityPreview3D, placement: ProximityPlacement3D, entry: Dictionary) -> Vector2:
	var id := placement.stream_class
	if id.is_empty():
		id = StringName(entry.get("class", ""))
	var fallback := Vector2.ONE * maxf(0.0, settings.radius_meters)
	if id.is_empty():
		return fallback
	var ranges: Vector2 = settings.distance_classes.get(id, Vector2(-1, -1))
	if ranges.is_finite() and ranges.x >= 0.0 and ranges.y >= ranges.x:
		return ranges
	if not _unknown_classes.has(id):
		_unknown_classes[id] = true
		push_warning("Editor Proximity Streaming: classe inválida ou ausente (%s)." % id)
	return fallback


func _find_settings() -> ProximityPreview3D:
	if not is_instance_valid(_world) or not _world.is_inside_tree():
		return null
	for child in _world.get_children():
		if child is ProximityPreview3D:
			return child
	return null


func _collect_loaded_scene() -> void:
	if _pending_path.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(_pending_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	var path := _pending_path
	_pending_path = ""
	var scene: PackedScene
	if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		scene = ResourceLoader.load_threaded_get(path) as PackedScene
	if not _needed_paths.has(path):
		return
	if scene == null or not scene.can_instantiate():
		_report_failure(path, "Não foi possível carregar o prefab.")
		return
	_ready_scenes[path] = scene


func _mount_or_request() -> void:
	while not _queue.is_empty():
		var placement: ProximityPlacement3D = _queue.back()
		if not is_instance_valid(placement) or _previews.has(placement) or not _wanted.has(placement):
			_queue.pop_back()
			continue
		var path := _wanted[placement]
		if _failed_paths.has(path):
			_queue.pop_back()
			continue
		if _ready_scenes.has(path):
			_queue.pop_back()
			var preview := placement.instantiate_prefab(_ready_scenes[path])
			if preview == null:
				_report_failure(path, "A cena precisa de uma raiz Node3D.")
				return
			preview.transform = Transform3D.IDENTITY
			placement.add_child(preview, false, Node.INTERNAL_MODE_BACK)
			preview.owner = placement
			_previews[placement] = preview
			return
		if _pending_path.is_empty():
			var error := ResourceLoader.load_threaded_request(path, "PackedScene")
			if error == OK:
				_pending_path = path
			else:
				_report_failure(path, error_string(error))
		return


func _remove_outdated_preview() -> bool:
	for placement in _previews.keys():
		var preview := _previews[placement]
		if not is_instance_valid(preview):
			_previews.erase(placement)
		elif preview.scene_file_path != _wanted.get(placement, ""):
			# Desmonta primeiro os conteúdos aninhados, deixando cada operação em um quadro.
			if _has_nested_preview(preview):
				continue
			_previews.erase(placement)
			_remove_preview(preview)
			return true
	return false


func _has_nested_preview(preview: Node3D) -> bool:
	for candidate in _previews.values():
		if is_instance_valid(candidate) and preview.is_ancestor_of(candidate):
			return true
	return false


func _report_failure(path: String, reason: String) -> void:
	_failed_paths[path] = true
	push_warning("Editor Proximity Streaming: %s (%s)" % [reason, path])


static func _release_request(tree: SceneTree, path: String) -> void:
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.create_timer(0.1).timeout
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_get(path)


static func _retire_previews(tree: SceneTree, previews: Array) -> void:
	previews.reverse()
	for preview in previews:
		_remove_preview(preview)
		await tree.process_frame


static func _remove_preview(preview: Node3D) -> void:
	if not is_instance_valid(preview):
		return
	var parent := preview.get_parent()
	if parent != null:
		parent.remove_child(preview)
	preview.queue_free()


func _remember_scene(root: Node) -> void:
	if root != null and not root.scene_file_path.is_empty():
		_edited_scenes[root.scene_file_path] = weakref(root)


func _on_filesystem_changed() -> void:
	_failed_paths.clear()
	if FileAccess.get_modified_time(CATALOG) != _catalog_stamp:
		_read_catalog()


func _read_catalog() -> void:
	_catalog_stamp = FileAccess.get_modified_time(CATALOG)
	_catalog.clear()
	if not FileAccess.file_exists(CATALOG):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if data is Dictionary:
		_catalog = data
	else:
		push_warning("Editor Proximity Streaming: índice inválido (%s)." % CATALOG)


func _index_saved_scene(path: String) -> void:
	_remember_scene(EditorInterface.get_edited_scene_root())
	var reference: WeakRef = _edited_scenes.get(path)
	var root: Node = reference.get_ref() if reference != null else null
	if root == null:
		return
	var entry := {}
	var id := str(root.get_meta(&"stream_class", ""))
	if not id.is_empty():
		entry["class"] = id
	var groups: Array[String] = []
	for group in [&"interior_detail", &"world_object"]:
		if root.is_in_group(group):
			groups.append(str(group))
	if not groups.is_empty():
		entry["groups"] = groups
	var preview := str(root.get_meta(&"stream_preview_path", ""))
	if not preview.is_empty():
		entry["preview"] = preview
	if _catalog.get(path, {}) == entry:
		return
	var updated := _catalog.duplicate()
	if entry.is_empty():
		updated.erase(path)
	else:
		updated[path] = entry
	var temporary := CATALOG + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_error("Editor Proximity Streaming: falha ao salvar o índice (%s)." % CATALOG)
		return
	file.store_string(JSON.stringify(updated, "\t", true) + "\n")
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, CATALOG)
	if error != OK:
		push_error("Editor Proximity Streaming: falha ao atualizar o índice (%s)." % error_string(error))
		return
	_catalog = updated
	_catalog_stamp = FileAccess.get_modified_time(CATALOG)
