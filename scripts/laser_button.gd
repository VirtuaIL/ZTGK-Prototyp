extends StaticBody3D
class_name laser_button

# The ID of the door this button controls
@export var doorId: int = 0

# Visual feedback settings
@export var active_color: Color = Color.CYAN
@export var press_depth: float = 0.05
@export var press_duration: float = 0.1

var _is_hit_this_frame: bool = false
var _was_hit_last_frame: bool = false

@onready var _button_mesh: MeshInstance3D = $ButtonMesh
@onready var _original_pos: Vector3 = $ButtonMesh.position
@onready var _original_color: Color = Color.GRAY # Default color

func _ready() -> void:
	var mat: StandardMaterial3D = _button_mesh.get_active_material(0)
	if mat:
		_original_color = mat.albedo_color


func receive_laser(_delta: float) -> void:
	_is_hit_this_frame = true


func _physics_process(_delta: float) -> void:
	if _is_hit_this_frame and not _was_hit_last_frame:
		_set_active(true)
	elif not _is_hit_this_frame and _was_hit_last_frame:
		_set_active(false)
	
	_was_hit_last_frame = _is_hit_this_frame
	_is_hit_this_frame = false


func _set_active(active: bool) -> void:
	# Visual feedback: Change color
	var mat: StandardMaterial3D = _button_mesh.get_active_material(0)
	if mat:
		var new_mat = mat.duplicate()
		new_mat.albedo_color = active_color if active else _original_color
		# Add emission for Cyan glow
		if active:
			new_mat.emission_enabled = true
			new_mat.emission = active_color
			new_mat.emission_energy_multiplier = 2.0
		else:
			new_mat.emission_enabled = false
		_button_mesh.material_override = new_mat
	
	# Movement feedback
	var target_y := _original_pos.y - press_depth if active else _original_pos.y
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_button_mesh, "position:y", target_y, press_duration)
	
	# Trigger doors
	var targets := _get_target_doors()
	for target in targets:
		if active:
			if target.has_method("press"):
				target.press(self)
			else:
				target.open()
		else:
			if target.has_method("release"):
				target.release(self)
			else:
				target.close()


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
