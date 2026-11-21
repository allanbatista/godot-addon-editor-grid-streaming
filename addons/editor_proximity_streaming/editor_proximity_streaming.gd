@tool
extends EditorPlugin

const REFRESH_INTERVAL := 0.1

var _world: Node
var _until_refresh := 0.0
var _wanted: Dictionary[ProximityPlacement3D, float] = {}
var _previews: Dictionary[ProximityPlacement3D, Node3D] = {}
var _queue: Array[ProximityPlacement3D] = []
var _failed_paths: Dictionary[String, bool] = {}
var _pending_path := ""


func _enter_tree() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(func() -> void: _failed_paths.clear())


func _exit_tree() -> void:
	_clear_previews()
	# Recolhe o resultado do último carregamento iniciado antes de desativar o addon.
	if not _pending_path.is_empty():
		ResourceLoader.load_threaded_get(_pending_path)


func _process(delta: float) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root != _world:
		_clear_previews()
		_world = root
		_until_refresh = 0.0
		_failed_paths.clear()

	_until_refresh -= delta
	if _until_refresh <= 0.0:
		_until_refresh = REFRESH_INTERVAL
		_refresh()
	_finish_request()
	_request_next_prefab()


func _refresh() -> void:
	var settings := _find_settings()
	var viewport := EditorInterface.get_editor_viewport_3d()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if settings == null or camera == null or not is_finite(settings.radius_meters) or settings.radius_meters < 0.0:
		_clear_previews()
		return

	var center := Vector2(camera.global_position.x, camera.global_position.z)
	var extent := Vector2.ONE * settings.radius_meters
	var area := Rect2(center - extent, extent * 2.0)
	_wanted.clear()
	for node in get_tree().get_nodes_in_group(ProximityPlacement3D.EDITOR_GROUP):
		var placement := node as ProximityPlacement3D
		if (
			placement == null
			or placement.owner != _world
			or placement.scene_path.is_empty()
			or placement.scene_path == _world.scene_file_path
		):
			continue
		var local_bounds: Variant = placement.get_meta(&"stream_bounds", AABB())
		if not local_bounds is AABB or not local_bounds.is_finite():
			continue
		var footprint: AABB = placement.global_transform * local_bounds
		var bounds := Rect2(footprint.position.x, footprint.position.z, footprint.size.x, footprint.size.z)
		if area.intersects(bounds, true):
			_wanted[placement] = center.distance_squared_to(center.clamp(bounds.position, bounds.end))

	for placement in _previews.keys():
		var preview := _previews[placement]
		if (
			not _wanted.has(placement)
			or not is_instance_valid(preview)
			or preview.scene_file_path != placement.scene_path
		):
			_remove_preview(preview)
			_previews.erase(placement)

	_queue.clear()
	for placement in _wanted:
		if not _previews.has(placement) and not _failed_paths.has(placement.scene_path):
			_queue.append(placement)
	_queue.sort_custom(func(a: ProximityPlacement3D, b: ProximityPlacement3D) -> bool:
		return _wanted[a] > _wanted[b]
	)


func _find_settings() -> ProximityPreview3D:
	if not is_instance_valid(_world) or not _world.is_inside_tree():
		return null
	for child in _world.get_children():
		if child is ProximityPreview3D:
			return child
	return null


func _request_next_prefab() -> void:
	if not _pending_path.is_empty():
		return
	while not _queue.is_empty():
		var placement: ProximityPlacement3D = _queue.pop_back()
		if not is_instance_valid(placement) or _previews.has(placement):
			continue
		var path := placement.scene_path
		if not _failed_paths.has(path):
			var error := ResourceLoader.load_threaded_request(path, "PackedScene")
			if error == OK:
				_pending_path = path
			else:
				_report_failure(path, error_string(error))
			return


func _finish_request() -> void:
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
	if scene == null or not scene.can_instantiate():
		_report_failure(path, "Could not load the prefab.")
		return
	for placement in _wanted:
		if not is_instance_valid(placement) or _previews.has(placement) or placement.scene_path != path:
			continue
		var preview := placement.instantiate_prefab(scene)
		if preview == null:
			_report_failure(path, "The prefab must have a Node3D root.")
			return
		preview.transform = Transform3D.IDENTITY
		# A prévia pertence à colocação para seleção no viewport. O World salva a colocação.
		placement.add_child(preview, false, Node.INTERNAL_MODE_BACK)
		preview.owner = placement
		_previews[placement] = preview


func _report_failure(path: String, reason: String) -> void:
	_failed_paths[path] = true
	push_warning("Editor Proximity Streaming: %s (%s)" % [reason, path])


func _clear_previews() -> void:
	for preview in _previews.values():
		_remove_preview(preview)
	_previews.clear()
	_wanted.clear()
	_queue.clear()


func _remove_preview(preview: Node3D) -> void:
	if not is_instance_valid(preview):
		return
	var parent := preview.get_parent()
	if parent != null:
		parent.remove_child(preview)
	preview.queue_free()
