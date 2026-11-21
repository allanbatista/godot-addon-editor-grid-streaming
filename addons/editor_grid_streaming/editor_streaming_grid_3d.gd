@tool
class_name EditorStreamingGrid3D
extends Node3D

const EDITOR_GROUP := &"editor_grid_streaming"

## Pasta com cenas cell_<x>_<z>.tscn.
@export_dir var cells_directory: String
## Comprimento, em metros, de cada lado da célula.
@export_range(0.1, 1000.0, 0.1, "or_greater", "suffix:m") var cell_size := 50.0
## 0 carrega a célula atual. 1 inclui as oito vizinhas, formando uma grade 3×3.
@export_range(0, 10, 1, "or_greater") var radius_in_cells := 1


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		add_to_group(EDITOR_GROUP)


func cell_at(world_position: Vector3) -> Vector2i:
	var local_position := to_local(world_position)
	return Vector2i(floori(local_position.x / cell_size), floori(local_position.z / cell_size))


func cell_origin(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * cell_size, 0.0, cell.y * cell_size)


func has_valid_grid() -> bool:
	return is_finite(cell_size) and cell_size > 0.0 and radius_in_cells >= 0
