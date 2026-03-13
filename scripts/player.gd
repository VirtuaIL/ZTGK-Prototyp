extends CharacterBody3D
class_name player

signal stratagem_activated(stratagem_id: String)

@export var speed: float = 7.0
@export var rotation_speed: float = 10.0

@export var fall_death_y: float = -1.0

@export var max_hp: float = 100.0
@export var hp_regen_rate: float = 20.0
@export var regen_delay: float = 2.0

var current_hp: float = 100.0
var time_since_last_damage: float = 0.0

@onready var damage_overlay: ColorRect = $PlayerHUD/DamageOverlay

var is_stratagem_mode: bool = false
var _spawn_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	collision_layer = 2 # Layer 2: Player
	collision_mask = 13 # Floor (1) + Movable (4) + Walls (8)
	_spawn_position = global_position
	current_hp = max_hp


func _physics_process(delta: float) -> void:
	# HP Regeneration
	time_since_last_damage += delta
	if time_since_last_damage >= regen_delay and current_hp < max_hp:
		current_hp = min(current_hp + hp_regen_rate * delta, max_hp)
		
	# Update Damage Vignette Overlay
	if damage_overlay and damage_overlay.material:
		var health_ratio: float = clamp(current_hp / max_hp, 0.0, 1.0)
		var intensity: float = 1.0 - health_ratio
		
		# Optionally, make the intensity non-linear so it only intensely shows up when very low
		intensity = pow(intensity, 1.5)
		
		var shader_mat: ShaderMaterial = damage_overlay.material as ShaderMaterial
		if shader_mat:
			shader_mat.set_shader_parameter("intensity", intensity)

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


func take_damage(amount: float) -> void:
	current_hp -= amount
	time_since_last_damage = 0.0
	
	if current_hp <= 0:
		die()


func die() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	current_hp = max_hp
	time_since_last_damage = 0.0


func set_stratagem_mode(active: bool) -> void:
	is_stratagem_mode = active
