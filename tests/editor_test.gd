@tool
extends EditorPlugin

const WORLD := "res://world.tscn"
const ORIGIN := Vector3(100, 0, -40)

var _camera_position := ORIGIN + Vector3(5, 45, 5)
var _grid: EditorStreamingGrid3D


func _enter_tree() -> void:
	process_priority = -100
	_run.call_deferred()


func _process(_delta: float) -> void:
	var viewport := EditorInterface.get_editor_viewport_3d()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		camera.global_position = _camera_position
		camera.rotation_degrees = Vector3(-90, 0, 0)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 40.0


func _run() -> void:
	if not await _wait_for(func() -> bool: return _is_open(WORLD), "Could not open the grid map."):
		return
	_grid = EditorInterface.get_edited_scene_root().get_node("Grid") as EditorStreamingGrid3D
	if not await _expect_window(Vector2i.ZERO, 1):
		return
	var corner := _grid.get_node("cell_1_1") as Node3D
	if not _check(
		corner.global_position.is_equal_approx(ORIGIN + Vector3(10, 0, 10)),
		"The cell must be positioned relative to the grid origin."
	):
		return
	if not _check(not ResourceLoader.has_cached("res://cells/cell_-3_-3.tscn"), "A distant scene was loaded."):
		return
	EditorInterface.get_selection().add_node(_grid)
	EditorInterface.edit_node(_grid)
	await RenderingServer.frame_post_draw
	var editor_image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	if not _check(
		editor_image.save_png(OS.get_environment("GRID_TEST_OUTPUT").path_join("grid-3x3.png")) == OK,
		"Could not capture the grid preview."
	):
		return

	var retained := _grid.get_node("cell_0_0").get_instance_id()
	_set_camera_cell(Vector2i(1, 0))
	if not await _expect_window(Vector2i(1, 0), 1):
		return
	if not _check(_grid.get_node("cell_0_0").get_instance_id() == retained, "Reloaded a cell in the overlap."):
		return

	_camera_position = ORIGIN + Vector3(-0.1, 45, -0.1)
	if not await _expect_window(Vector2i(-1, -1), 1):
		return
	_set_camera_cell(Vector2i(3, 3))
	if not await _expect_window(Vector2i(3, 3), 1):
		return
	_set_camera_cell(Vector2i(8, 8))
	if not await _expect_window(Vector2i(8, 8), 1):
		return

	_set_camera_cell(Vector2i.ZERO)
	_grid.radius_in_cells = 2
	if not await _expect_window(Vector2i.ZERO, 2):
		return
	_grid.radius_in_cells = 0
	_set_camera_cell(Vector2i(1, 0))
	if not await _expect_window(Vector2i(1, 0), 0):
		return

	if not _check(EditorInterface.save_scene() == OK, "Could not save the map."):
		return
	var saved_map := FileAccess.get_file_as_string(WORLD)
	if not _check(
		saved_map.contains("radius_in_cells = 0") and not saved_map.contains("cell_1_0"),
		"The map must persist the radius and omit previews."
	):
		return

	var button := EditorInterface.get_base_control().find_child("EditCameraCell", true, false) as Button
	if not _check(button != null and not button.disabled, "The cell editing button is unavailable."):
		return
	button.pressed.emit()
	if not await _wait_for(
		func() -> bool: return _is_open("res://cells/cell_1_0.tscn"),
		"The editor opened the wrong cell."
	):
		return
	var building := EditorInterface.get_edited_scene_root().get_node("Building") as Node3D
	building.position.y = 4.0
	if not _check(EditorInterface.save_scene() == OK, "Could not save the edited cell."):
		return

	EditorInterface.open_scene_from_path(WORLD)
	if not await _wait_for(func() -> bool: return _is_open(WORLD), "Could not return to the map."):
		return
	if not await _expect_window(Vector2i(1, 0), 0):
		return
	var preview := _grid.get_node("cell_1_0/Building") as Node3D
	if not _check(is_equal_approx(preview.position.y, 4.0), "The preview did not reflect the saved cell."):
		return
	print("PASS edit cell, save it, and return to its updated preview")

	EditorInterface.set_plugin_enabled("editor_grid_streaming", false)
	if not await _wait_for(func() -> bool: return _preview_names().is_empty(), "Disabling left previews behind."):
		return
	EditorInterface.set_plugin_enabled("editor_grid_streaming", true)
	if not await _expect_window(Vector2i(1, 0), 0):
		return
	print("PASS editor_grid_streaming")
	get_tree().quit(0)


func _set_camera_cell(cell: Vector2i) -> void:
	_camera_position = ORIGIN + Vector3(cell.x * 10 + 5, 45, cell.y * 10 + 5)


func _is_open(path: String) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	return root != null and root.scene_file_path == path and root.is_inside_tree()


func _preview_names() -> Array[String]:
	var names: Array[String] = []
	for node in _grid.get_children(true):
		names.append(str(node.name))
	names.sort()
	return names


func _expect_window(center: Vector2i, radius: int) -> bool:
	var expected: Array[String] = []
	for x in range(maxi(-3, center.x - radius), mini(3, center.x + radius) + 1):
		for z in range(maxi(-3, center.y - radius), mini(3, center.y + radius) + 1):
			if Vector2i(x, z) != Vector2i(3, 3):
				expected.append("cell_%d_%d" % [x, z])
	expected.sort()
	var description := "center %s, radius %d, %d scenes" % [center, radius, expected.size()]
	if not await _wait_for(func() -> bool: return _preview_names() == expected, "Wrong window for " + description):
		return false
	print("PASS ", description)
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
