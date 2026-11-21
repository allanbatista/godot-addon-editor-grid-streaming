@tool
extends EditorNode3DGizmoPlugin

const PROTOTYPE_SHADER = preload("res://addons/editor_proximity_streaming/proximity_placeholder.gdshader")
const BRIGHTNESS_LEVELS := [0.88, 0.94, 1.0, 1.06, 1.12]
const CLASS_COLORS := {
	&"dist_near": Color("#60cdeb"),
	&"dist_local": Color("#75ce83"),
	&"dist_mid": Color("#e9bd57"),
	&"dist_away": Color("#ee8758"),
	&"dist_remote": Color("#b291ec"),
}

var _boxes: Dictionary[int, Array] = {}
var _materials: Dictionary[StringName, ShaderMaterial] = {}
var _mesh := ArrayMesh.new()
var _faces := PackedVector3Array()


func _init() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
		Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
		Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
		Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 1, 2, 0, 2, 3, 4, 7, 6, 4, 6, 5,
		0, 3, 7, 0, 7, 4, 1, 5, 6, 1, 6, 2,
		0, 4, 5, 0, 5, 1, 3, 2, 6, 3, 6, 7,
	])
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_faces = _mesh.get_faces()


func _get_gizmo_name() -> String:
	return "Placeholders de proximidade"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_scene_instance_load_placeholder()


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var placement := gizmo.get_node_3d()
	var entry: Array = _boxes.get(placement.get_instance_id(), [])
	if entry.is_empty():
		return
	var bounds: AABB = entry[0]
	var size := bounds.size.max(Vector3.ONE * 0.1)
	if bounds.size == Vector3.ZERO:
		size = Vector3.ONE * 0.5
	var box := Transform3D(Basis.from_scale(size), bounds.get_center())
	gizmo.add_mesh(_mesh, _material(entry[1], entry[2]), box)
	var faces := PackedVector3Array()
	for vertex in _faces:
		faces.append(box * vertex)
	var pick_shape := TriangleMesh.new()
	if pick_shape.create_from_faces(faces):
		gizmo.add_collision_triangles(pick_shape)


func replace_boxes(boxes: Dictionary[int, Array]) -> void:
	var previous := _boxes
	_boxes = boxes
	for id in previous:
		if not boxes.has(id):
			_update_gizmos(id)
	for id in boxes:
		if boxes[id] != previous.get(id, []):
			_update_gizmos(id)


func _update_gizmos(id: int) -> void:
	var placement := instance_from_id(id) as Node3D
	if is_instance_valid(placement):
		placement.update_gizmos()


func _material(member_class: StringName, placement_path: NodePath) -> ShaderMaterial:
	var shade := posmod(hash(placement_path), BRIGHTNESS_LEVELS.size())
	var key := StringName("%s/%d" % [member_class, shade])
	if not _materials.has(key):
		var tint := Color("#acadba")
		if not member_class.is_empty():
			tint = CLASS_COLORS.get(member_class,
				Color.from_hsv(float(posmod(hash(member_class), 360)) / 360.0, 0.45, 0.92))
		var material := ShaderMaterial.new()
		material.shader = PROTOTYPE_SHADER
		material.set_shader_parameter("class_color", tint)
		material.set_shader_parameter("brightness", BRIGHTNESS_LEVELS[shade])
		_materials[key] = material
	return _materials[key]
