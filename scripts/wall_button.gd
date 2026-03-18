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

func _ready() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			child.scale *= 2.0


func on_projectile_hit() -> void:
	if _is_activated:
		return
	
	_is_activated = true
	
	# Visual feedback: Change color and sink into the base
	var mat: StandardMaterial3D = _button_mesh.get_active_material(0)
	if mat:
		# Create a unique material instance so we don't change all buttons
		var new_mat = mat.duplicate()
		new_mat.albedo_color = active_color
		_button_mesh.material_override = new_mat
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	# Button sinks along local Z if oriented towards wall
	tween.tween_property(_button_mesh, "position:z", _original_pos.z - press_depth, press_duration)
	
	# Permanently open the target doors
	for target in _get_target_doors():
		target.open()


func _get_target_doors() -> Array[door]:
	var result: Array[door] = []
	for d in get_tree().get_nodes_in_group("doors"):
		if d is door and d.doorId == doorId:
			result.append(d)
	return result
