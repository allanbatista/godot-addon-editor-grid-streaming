@tool
class_name ProximityPlacement3D
extends Node3D

const EDITOR_GROUP := &"_editor_proximity_placements"

## Caminho da cena carregada quando este objeto entra no alcance.
@export_file("*.tscn", "*.scn") var scene_path: String
## Classe específica para esta colocação. Vazio usa a classe do prefab.
@export var stream_class: StringName
## Volume local opcional de ativação. Salas podem fornecer stream_volume no nó pai.
@export var activation_volume := AABB()
## Propriedades da raiz do prefab sobrescritas nesta colocação.
@export var instance_properties: Dictionary = {}
@export_tool_button("Open Prefab", "PackedScene") var open_prefab: Callable = _open_prefab


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		add_to_group(EDITOR_GROUP)


func instantiate_prefab(scene: PackedScene) -> Node3D:
	if scene == null or not scene.can_instantiate():
		return null
	var node := scene.instantiate()
	if not node is Node3D:
		if node != null:
			node.free()
		return null
	for property in instance_properties:
		node.set(property, instance_properties[property])
	return node


func create_instance(replace: bool, scene: PackedScene) -> Node3D:
	var instance := instantiate_prefab(scene)
	if instance == null:
		return null
	instance.name = name
	instance.transform = transform
	var parent := get_parent()
	var index := get_index()
	if replace:
		parent.remove_child(self)
		queue_free()
	parent.add_child(instance)
	parent.move_child(instance, index)
	return instance


func _open_prefab() -> void:
	if not Engine.is_editor_hint() or not ResourceLoader.exists(scene_path, "PackedScene"):
		return
	var editor := Engine.get_singleton(&"EditorInterface")
	editor.call(&"open_scene_from_path", scene_path)
