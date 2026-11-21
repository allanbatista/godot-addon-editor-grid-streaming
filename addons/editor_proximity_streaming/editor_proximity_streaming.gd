@tool
extends EditorPlugin

const REFRESH_INTERVAL := 0.15
const PLACEHOLDER_GIZMOS = preload("res://addons/editor_proximity_streaming/proximity_placeholder_gizmos.gd")
const DISTANCES := {
	&"dist_near": Vector2(5, 7),
	&"dist_local": Vector2(25, 32),
	&"dist_mid": Vector2(50, 60),
	&"dist_away": Vector2(100, 115),
	&"dist_remote": Vector2(200, 220),
}
const DEFAULT_DISTANCE := Vector2(45, 45)

var _gizmos := PLACEHOLDER_GIZMOS.new()
var _boxes: Dictionary[int, Array] = {}
var _hidden: Dictionary[int, VisualInstance3D] = {}
var _until_refresh := 0.0


func _enter_tree() -> void:
	add_node_3d_gizmo_plugin(_gizmos)


func _exit_tree() -> void:
	_apply_visibility({})
	remove_node_3d_gizmo_plugin(_gizmos)


func _process(delta: float) -> void:
	_until_refresh -= delta
	if _until_refresh > 0.0:
		return
	_until_refresh = REFRESH_INTERVAL
	var world := EditorInterface.get_edited_scene_root()
	var view := EditorInterface.get_editor_viewport_3d()
	var camera := view.get_camera_3d() if view != null else null
	var next_boxes: Dictionary[int, Array] = {}
	var next_hidden: Dictionary[int, VisualInstance3D] = {}
	if world != null and camera != null:
		_collect_boxes(world, camera.global_position, next_boxes, next_hidden)
	_apply_visibility(next_hidden)
	_gizmos.replace_boxes(next_boxes)
	_boxes = next_boxes


func _collect_boxes(world: Node, position: Vector3, boxes: Dictionary[int, Array],
		hidden: Dictionary[int, VisualInstance3D]) -> void:
	for child in world.find_children("*", "Node3D", true, false):
		var placement := child as Node3D
		if not placement.get_scene_instance_load_placeholder() or not placement.is_visible_in_tree():
			continue
		var id := _distance_tag(placement)
		if id.is_empty() or _covered_by_parent(placement, world, boxes):
			continue
		var bounds := _local_bounds(placement)
		var footprint: AABB = placement.global_transform * bounds
		var closest := position.clamp(footprint.position, footprint.end)
		var offset := (position - closest).abs()
		var distance := maxf(offset.x, offset.z)
		var ranges: Vector2 = DISTANCES.get(id, DEFAULT_DISTANCE)
		var limit := ranges.x if _boxes.has(placement.get_instance_id()) else ranges.y
		if distance <= limit:
			continue
		boxes[placement.get_instance_id()] = [bounds, id, world.get_path_to(placement)]
		if placement is VisualInstance3D:
			hidden[placement.get_instance_id()] = placement
		for descendant in placement.find_children("*", "VisualInstance3D", true, false):
			hidden[descendant.get_instance_id()] = descendant


func _distance_tag(node: Node3D) -> StringName:
	var id := StringName(node.get_meta(&"stream_class", &""))
	if not id.is_empty():
		return id
	for tag in DISTANCES:
		if node.is_in_group(tag):
			return tag
	if node.is_in_group(&"interior_detail"):
		return &"dist_near"
	return &"dist_mid" if node.is_in_group(&"world_object") else &""


func _covered_by_parent(node: Node3D, world: Node, boxes: Dictionary[int, Array]) -> bool:
	var ancestor := node.get_parent()
	while ancestor != null and ancestor != world:
		if boxes.has(ancestor.get_instance_id()):
			return true
		ancestor = ancestor.get_parent()
	return false


func _local_bounds(node: Node3D) -> AABB:
	var bounds: Variant = node.get_meta(&"stream_bounds", AABB())
	if bounds is AABB and bounds.is_finite() and bounds.size != Vector3.ZERO:
		return bounds
	var visuals := node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		visuals.push_front(node)
	var local := node.global_transform.affine_inverse()
	var merged := AABB()
	var found := false
	for visual: GeometryInstance3D in visuals:
		var relative := local * visual.global_transform
		var part: AABB = relative * visual.get_aabb()
		if not part.is_finite():
			continue
		merged = merged.merge(part) if found else part
		found = true
	return merged


func _apply_visibility(hidden: Dictionary[int, VisualInstance3D]) -> void:
	for id in _hidden:
		if hidden.has(id):
			continue
		var visual := _hidden[id]
		if is_instance_valid(visual):
			RenderingServer.instance_set_visible(visual.get_instance(), visual.is_visible_in_tree())
	for visual in hidden.values():
		RenderingServer.instance_set_visible(visual.get_instance(), false)
	_hidden = hidden
