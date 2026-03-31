extends StaticBody3D
class_name wall_button

# The ID of the door this button controls
@export var doorId: int = 0

# Visual feedback settings
@export var active_color: Color = Color.GREEN
@export var press_depth: float = 0.05
@export var press_duration: float = 0.1

var _is_activated: bool = false
@onready var _button_mesh: MeshInstance3D = $ButtonMesh
@onready var _original_pos: Vector3 = $ButtonMesh.position
var _original_color: Color = Color(0.7411765, 0, 0.65882355, 1)

func _ready() -> void:
	add_to_group("buttons")
	for child in get_children():
		if child is CollisionShape3D:
			child.scale *= 2.0
	var mat: StandardMaterial3D = _button_mesh.get_active_material(0)
	if mat:
		_original_color = mat.albedo_color


func on_projectile_hit() -> void:
	if not _is_activated:
		_is_activated = true
		_set_visual_state(true)

	for target in _get_target_doors():
		if target.has_method("press"):
			target.press(self)
		else:
			target.open()


func _get_target_doors() -> Array[door]:
	var result: Array[door] = []
	var level_root := _get_level_root()
	for d in get_tree().get_nodes_in_group("doors"):
		if level_root and not level_root.is_ancestor_of(d):
			continue
		if d is door and d.doorId == doorId:
			result.append(d)
	return result

func _get_level_root() -> Node:
	var n: Node = self
	while n and n.get_parent():
		var p := n.get_parent()
		if p and p.name == "levels":
			return n
		n = p
	return null


func reset_button_state() -> void:
	_is_activated = false
	_set_visual_state(false)


func _set_visual_state(active: bool) -> void:
	var mat: StandardMaterial3D = _button_mesh.get_active_material(0)
	if mat:
		var new_mat: StandardMaterial3D = mat.duplicate()
		new_mat.albedo_color = active_color if active else _original_color
		_button_mesh.material_override = new_mat

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	var target_z := _original_pos.z - press_depth if active else _original_pos.z
	tween.tween_property(_button_mesh, "position:z", target_z, press_duration)
