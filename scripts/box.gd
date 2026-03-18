extends CharacterBody3D
class_name box

@export var carriers_required: int = 4
@export var fall_death_y: float = -1.0
@export var gravity_multiplier: float = 5.0

signal object_reset

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []
var carrier_available_max: int = 0
var carrier_brush_desired: int = 0

var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	collision_layer = 4 # Layer 3: Movable
	collision_mask = 31 | (1 << 8)  # Floor (1) + Player (2) + Movable (4) + Walls (8) + Barrier (16) + RatStructures (9)
	_spawn_position = global_position
	add_to_group("boxes")

func _activate_reset_to_spawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	object_reset.emit()


func _physics_process(delta: float) -> void:
	# Fall reset
	if global_position.y < fall_death_y:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		object_reset.emit()
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * gravity_multiplier
	else:
		velocity.y = 0.0

	move_and_slide()


func set_highlight(enabled: bool) -> void:
	var mesh_instance: MeshInstance3D = get_node_or_null("Body")
	if not mesh_instance:
		return
		
	if enabled:
		if mesh_instance.material_overlay:
			return # Already highlighted
			
		var highlight_mat = StandardMaterial3D.new()
		highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		highlight_mat.albedo_color = Color.YELLOW
		highlight_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		highlight_mat.no_depth_test = true
		highlight_mat.grow = true
		highlight_mat.grow_amount = 0.03
		
		mesh_instance.material_overlay = highlight_mat
	else:
		mesh_instance.material_overlay = null
