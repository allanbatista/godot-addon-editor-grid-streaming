@tool
extends EditorPlugin

var _grid: EditorStreamingGrid3D
var _edit_button: Button
var _indexed_directory := ""
var _index_dirty := true
var _known_cells: Dictionary[Vector2i, String] = {}

var _center := Vector2i.ZERO
var _radius := -1
var _cell_size := 0.0
var _wanted: Dictionary[Vector2i, String] = {}
var _previews: Dictionary[Vector2i, Node3D] = {}
var _queued: Array[Vector2i] = []
var _requested_cell: Vector2i
var _requested_path := ""


func _enter_tree() -> void:
	_edit_button = Button.new()
	_edit_button.name = &"EditCameraCell"
	_edit_button.text = "Edit Camera Cell"
	_edit_button.hide()
	_edit_button.pressed.connect(_edit_camera_cell)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _edit_button)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	_clear_previews()
	# A API do Godot exige recolher o resultado de um pedido iniciado.
	if not _requested_path.is_empty():
		ResourceLoader.load_threaded_get(_requested_path)
		_requested_path = ""
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _edit_button)
	_edit_button.queue_free()


func _process(_delta: float) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var grid := _find_grid(root)
	if grid != _grid:
		_clear_previews()
		_grid = grid
		_index_dirty = true

	var viewport := EditorInterface.get_editor_viewport_3d()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if not is_instance_valid(_grid) or not _grid.has_valid_grid() or camera == null:
		if _radius != -1:
			_clear_previews()
		_edit_button.hide()
		_finish_request()
		return

	if _indexed_directory != _grid.cells_directory or _cell_size != _grid.cell_size:
		_clear_previews()
	if _indexed_directory != _grid.cells_directory:
		_index_dirty = true

	var center := _grid.cell_at(camera.global_position)
	if _index_dirty or _center != center or _radius != _grid.radius_in_cells:
		if _index_dirty:
			_index_cells(root.scene_file_path)
		_update_window(center)

	_finish_request()
	_request_next_cell()


func _find_grid(root: Node) -> EditorStreamingGrid3D:
	if root == null or not root.is_inside_tree():
		return null
	if root is EditorStreamingGrid3D:
		return root
	for node in get_tree().get_nodes_in_group(EditorStreamingGrid3D.EDITOR_GROUP):
		if node.owner == root and node is EditorStreamingGrid3D:
			return node
	return null


func _on_filesystem_changed() -> void:
	_index_dirty = true


func _index_cells(world_path: String) -> void:
	_known_cells.clear()
	_indexed_directory = _grid.cells_directory
	_index_dirty = false
	if _indexed_directory.is_empty():
		return
	if not _indexed_directory.begins_with("res://") or not DirAccess.dir_exists_absolute(_indexed_directory):
		push_warning("Editor Grid Streaming: pasta de células inválida: %s" % _indexed_directory)
		return

	for file_name in DirAccess.get_files_at(_indexed_directory):
		if not file_name.begins_with("cell_") or file_name.get_extension() != "tscn":
			continue
		var coordinates := file_name.get_basename().trim_prefix("cell_").split("_")
		if coordinates.size() != 2 or not coordinates[0].is_valid_int() or not coordinates[1].is_valid_int():
			continue
		var cell := Vector2i(int(coordinates[0]), int(coordinates[1]))
		var path := _indexed_directory.path_join(file_name)
		if file_name == _cell_name(cell) + ".tscn" and path != world_path:
			_known_cells[cell] = path


func _update_window(center: Vector2i) -> void:
	_center = center
	_radius = _grid.radius_in_cells
	_cell_size = _grid.cell_size
	_wanted.clear()
	_queued.clear()
	for cell in _known_cells:
		if _distance_from_center(cell) <= _radius:
			_wanted[cell] = _known_cells[cell]

	for cell in _previews.keys():
		if not _wanted.has(cell):
			_remove_preview(_previews[cell])
			_previews.erase(cell)

	for cell in _wanted:
		if not _previews.has(cell) and (_requested_cell != cell or _requested_path != _wanted[cell]):
			_queued.append(cell)
	_queued.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _distance_from_center(a) > _distance_from_center(b)
	)

	var path: String = _wanted.get(_center, "")
	_edit_button.visible = true
	_edit_button.disabled = path.is_empty()
	_edit_button.tooltip_text = path if not path.is_empty() else "No saved scene in the camera cell."


func _distance_from_center(cell: Vector2i) -> int:
	return maxi(absi(cell.x - _center.x), absi(cell.y - _center.y))


func _request_next_cell() -> void:
	if not _requested_path.is_empty() or _queued.is_empty():
		return
	var cell: Vector2i = _queued.pop_back()
	var path := _wanted[cell]
	var error := ResourceLoader.load_threaded_request(path, "PackedScene")
	if error != OK:
		_report_load_failure(path, error_string(error))
		return
	_requested_cell = cell
	_requested_path = path


func _finish_request() -> void:
	if _requested_path.is_empty():
		return
	var status := ResourceLoader.load_threaded_get_status(_requested_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return

	var path := _requested_path
	var cell := _requested_cell
	_requested_path = ""
	var scene: PackedScene
	if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		scene = ResourceLoader.load_threaded_get(path) as PackedScene
	if _wanted.get(cell, "") != path or not is_instance_valid(_grid):
		return
	if scene == null:
		_report_load_failure(path, "Could not load the cell scene.")
		return

	var node := scene.instantiate()
	if not node is Node3D:
		if node != null:
			node.free()
		_report_load_failure(path, "The cell scene must have a Node3D root.")
		return
	var preview := node as Node3D
	preview.name = _cell_name(cell)
	preview.position += _grid.cell_origin(cell)
	# As prévias são internas e ficam fora do PackedScene salvo pelo editor.
	_grid.add_child(preview, false, Node.INTERNAL_MODE_BACK)
	_previews[cell] = preview


func _report_load_failure(path: String, reason: String) -> void:
	push_warning("Editor Grid Streaming: %s (%s)" % [reason, path])


func _clear_previews() -> void:
	for preview in _previews.values():
		_remove_preview(preview)
	_previews.clear()
	_wanted.clear()
	_queued.clear()
	_radius = -1


func _remove_preview(preview: Node3D) -> void:
	if not is_instance_valid(preview):
		return
	if preview.get_parent() != null:
		preview.get_parent().remove_child(preview)
	preview.queue_free()


func _cell_name(cell: Vector2i) -> String:
	return "cell_%d_%d" % [cell.x, cell.y]


func _edit_camera_cell() -> void:
	var path: String = _wanted.get(_center, "")
	if not path.is_empty():
		EditorInterface.open_scene_from_path(path)
