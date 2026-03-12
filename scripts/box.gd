extends CharacterBody3D
class_name box

@export var carriers_required: int = 4
@export var fall_death_y: float = -1.0
@export var gravity_multiplier: float = 5.0

signal box_reset

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []

var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_spawn_position = global_position


func _physics_process(delta: float) -> void:
	# Fall reset
	if global_position.y < fall_death_y:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		box_reset.emit()
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * gravity_multiplier
	else:
		velocity.y = 0.0

	move_and_slide()
