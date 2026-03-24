extends CharacterBody3D
class_name player

signal stratagem_activated(stratagem_id: String)
signal player_died

@export var speed: float = 7.0
@export var rotation_speed: float = 10.0

@export var fall_death_y: float = -1.0

var is_stratagem_mode: bool = false
var _spawn_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2 # Layer 2: Player
	collision_mask = 13 | (1 << 8) # Floor (1) + Movable (4) + Walls (8) + RatStructures (9)
	_spawn_position = global_position


func _physics_process(delta: float) -> void:
	# Fall reset
	if global_position.y < fall_death_y:
		die()
		return

	if is_stratagem_mode:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var input_dir := Vector3.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.z = Input.get_axis("move_forward", "move_back")
	# Rotate input to match isometric camera (45° around Y)
	input_dir = input_dir.rotated(Vector3.UP, deg_to_rad(45.0))

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		velocity.x = input_dir.x * speed
		velocity.z = input_dir.z * speed

		var target_angle := atan2(input_dir.x, input_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0.0, speed * delta * 5.0)

	# Gravity — accumulated independently of horizontal movement
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 5
	else:
		velocity.y = 0.0

	move_and_slide()


# Stealth: any contact = instant reset
func take_damage(_amount: float = 0.0) -> void:
	die()


func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos


func die() -> void:
	for box in get_tree().get_nodes_in_group("boxes"):
		if box.has_method("_activate_reset_to_spawn"):
			box._activate_reset_to_spawn()
			
	global_position = _spawn_position
	velocity = Vector3.ZERO
	player_died.emit()


func set_stratagem_mode(active: bool) -> void:
	is_stratagem_mode = active
