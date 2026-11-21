@tool
extends EditorPlugin

const ADDON := "editor_proximity_streaming"
const ADDON_SCRIPT := "res://addons/editor_proximity_streaming/editor_proximity_streaming.gd"
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
	if not await _wait_for(func() -> bool:
		var scene := EditorInterface.get_edited_scene_root()
		return scene != null and scene.scene_file_path == WORLD and _addon() != null,
		"Não foi possível abrir a cena de teste e localizar o addon."):
		return
	_world = EditorInterface.get_edited_scene_root() as Node3D
	var addon := _addon()
	var first := _world.get_node("NearBox") as Node3D
	var second := _world.get_node("NearBoxTwin") as Node3D
	var other := _world.get_node("LocalBox") as Node3D
	if not await _wait_for(func() -> bool: return _box_names() == ["LocalBox", "NearBox", "NearBoxTwin", "Room"],
			"Os limites, tags ou marcações nativas produziram caixas incorretas."):
		return
	if not _check(first.get_scene_instance_load_placeholder() and first.has_node("Building")
			and first.get_script() == null, "A instância nativa foi substituída."):
		return
	var interior := _world.get_node("Room/Interior")
	var hidden: Dictionary = addon.get("_hidden")
	if not _check(not addon.get("_boxes").has(interior.get_instance_id())
			and hidden.has(interior.get_node("Building").get_instance_id()),
			"Um filho distante recebeu uma caixa separada ou ficou fora da ocultação."):
		return
	print("PASS instâncias nativas, classes e hierarquia de caixas")

	var gizmos: EditorNode3DGizmoPlugin = addon.get("_gizmos")
	var first_path := _world.get_path_to(first)
	var first_material: ShaderMaterial = gizmos._material(&"dist_near", first_path)
	var second_material: ShaderMaterial = gizmos._material(&"dist_near", _world.get_path_to(second))
	var other_material: ShaderMaterial = gizmos._material(&"dist_local", _world.get_path_to(other))
	if not _check(first_material == gizmos._material(&"dist_near", first_path)
			and first_material.get_shader_parameter("class_color") == second_material.get_shader_parameter("class_color")
			and first_material.get_shader_parameter("brightness") != second_material.get_shader_parameter("brightness")
			and first_material.get_shader_parameter("class_color") != other_material.get_shader_parameter("class_color"),
			"As cores por classe e brilho por instância estão inconsistentes."):
		return
	print("PASS cor por classe e variação estável de brilho")

	_position.x = 2.0
	await get_tree().create_timer(0.35).timeout
	if not _check(_has_box(second), "A caixa sumiu entre 5 m e 7 m."):
		return
	_position.x = 3.0
	if not await _wait_for(func() -> bool: return not _has_box(second), "Ao chegar a 5 m a malha não voltou."):
		return
	_position.x = 2.0
	await get_tree().create_timer(0.35).timeout
	if not _check(not _has_box(second), "Uma malha visível voltou à caixa a 6 m."):
		return
	_position.x = 0.0
	if not await _wait_for(func() -> bool: return _has_box(second), "A caixa não voltou além de 7 m."):
		return
	print("PASS transição e histerese pela extensão da geometria")

	if not _check(EditorInterface.save_scene() == OK, "Falha ao salvar a cena de teste."):
		return
	var text := FileAccess.get_file_as_string(WORLD)
	if not _check(text.contains('instance_placeholder="res://prefab.tscn"')
			and not text.contains("script =") and not text.contains("visible = false"),
			"A prévia alterou a configuração salva do mapa."):
		return
	print("PASS arquivo salvo conserva as instâncias nativas")

	EditorInterface.set_plugin_enabled(ADDON, false)
	if not await _wait_for(func() -> bool: return _addon() == null, "Não foi possível desativar o addon."):
		return
	EditorInterface.set_plugin_enabled(ADDON, true)
	if not await _wait_for(func() -> bool: return _addon() != null and _has_box(second), "Falha ao reativar o addon."):
		return
	print("PASS editor_proximity_streaming")
	get_tree().quit(0)


func _addon() -> Node:
	for candidate in get_tree().root.find_children("*", "EditorPlugin", true, false):
		var script: Script = candidate.get_script()
		if script != null and script.resource_path == ADDON_SCRIPT:
			return candidate
	return null


func _box_names() -> Array[String]:
	var names: Array[String] = []
	var addon := _addon()
	if addon == null:
		return names
	var boxes: Dictionary = addon.get("_boxes")
	for id in boxes:
		var node := instance_from_id(id) as Node
		if node != null:
			names.append(str(node.name))
	names.sort()
	return names


func _has_box(node: Node) -> bool:
	var addon := _addon()
	return addon != null and addon.get("_boxes").has(node.get_instance_id())


func _wait_for(condition: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if condition.call():
			return true
	return _check(false, message)


func _check(passed: bool, message: String) -> bool:
	if not passed:
		push_error(message)
		get_tree().quit(1)
	return passed
