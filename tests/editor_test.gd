@tool
extends EditorPlugin

const WORLD := "res://world.tscn"
var _position := Vector3(0, 25, 0)
var _world: Node3D


func _enter_tree() -> void:
	process_priority = -100
	_run.call_deferred()


func _process(_delta: float) -> void:
	var viewport := EditorInterface.get_editor_viewport_3d()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		camera.global_position = _position
		camera.rotation_degrees = Vector3(-90, 0, 0)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 30.0


func _run() -> void:
	if not await _wait_for(func() -> bool: return _is_open(WORLD), "Could not open the map."):
		return
	_world = EditorInterface.get_edited_scene_root() as Node3D
	if not await _expect_previews(["Diagonal", "LeftEdge", "Near", "Overlap"]):
		return
	if not _check(not ResourceLoader.has_cached("res://far.tscn"), "A distant prefab was loaded."):
		return

	var near := _world.get_node("Near") as ProximityPlacement3D
	var preview := near.get_child(0, true) as Node3D
	var instance_id := preview.get_instance_id()
	_position.x += 0.3
	if not await _expect_previews(["Beyond", "Diagonal", "Near", "Overlap"]):
		return
	if not _check(near.get_child(0, true).get_instance_id() == instance_id, "Reloaded a retained prefab."):
		return
	near.position.x += 1.0
	if not _check(preview.global_position.is_equal_approx(near.global_position), "Preview did not follow the placement."):
		return
	if not _check(EditorInterface.save_scene() == OK, "Could not save the map."):
		return
	var saved := FileAccess.get_file_as_string(WORLD)
	if not _check(
		saved.contains('scene_path = "res://near.tscn"') and not saved.contains('instance=ExtResource'),
		"The map must save paths and omit instantiated previews."
	):
		return

	var settings := _world.get_node("Preview") as ProximityPreview3D
	settings.radius_meters = 2.0
	_position = Vector3(3, 25, 2)
	if not await _expect_previews(["Near"]):
		return
	near.open_prefab.call()
	if not await _wait_for(func() -> bool: return _is_open("res://near.tscn"), "Open Prefab opened the wrong scene."):
		return
	var building := EditorInterface.get_edited_scene_root().get_node("Building") as Node3D
	building.position.y = 4.0
	if not _check(EditorInterface.save_scene() == OK, "Could not save the prefab."):
		return

	EditorInterface.open_scene_from_path(WORLD)
	if not await _wait_for(func() -> bool: return _is_open(WORLD), "Could not return to the map."):
		return
	if not await _expect_previews(["Near"]):
		return
	preview = near.get_child(0, true) as Node3D
	if not _check(is_equal_approx(preview.get_node("Building").position.y, 4.0), "Preview did not reflect saved prefab."):
		return
	print("PASS position editing and isolated prefab saving")

	_position = Vector3(200, 25, 0)
	if not await _expect_previews(["Far"]):
		return
	EditorInterface.set_plugin_enabled("editor_proximity_streaming", false)
	if not await _expect_previews([]):
		return
	EditorInterface.set_plugin_enabled("editor_proximity_streaming", true)
	if not await _expect_previews(["Far"]):
		return
	print("PASS editor_proximity_streaming")
	get_tree().quit(0)


func _is_open(path: String) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	return root != null and root.scene_file_path == path and root.is_inside_tree()


func _preview_names() -> Array[String]:
	var names: Array[String] = []
	for node in _world.get_children():
		if node is ProximityPlacement3D and node.get_child_count(true) == 1:
			names.append(str(node.name))
	names.sort()
	return names


func _expect_previews(expected: Array[String]) -> bool:
	if not await _wait_for(func() -> bool: return _preview_names() == expected, "Wrong previews for %s" % [expected]):
		return false
	print("PASS previews ", expected)
	return true


func _wait_for(condition: Callable, message: String) -> bool:
	for frame in 480:
		await get_tree().process_frame
		if condition.call():
			return true
	return _check(false, message)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		get_tree().quit(1)
	return condition
