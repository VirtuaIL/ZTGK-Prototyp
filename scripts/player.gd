extends CharacterBody3D

@export var speed: float = 7.0
@export var rotation_speed: float = 10.0
@export var jump_impulse: float = 8.0

var is_stratagem_mode: bool = false


func _ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	# Handle Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_impulse

	if is_stratagem_mode:
		velocity.y = 0 # Hover during stratagem input
		velocity.x = 0
		velocity.z = 0
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
		velocity.x = move_toward(velocity.x, 0, speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0, speed * delta * 5.0)

	move_and_slide()


func set_stratagem_mode(active: bool) -> void:
	is_stratagem_mode = active
