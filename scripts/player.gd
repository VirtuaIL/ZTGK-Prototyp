extends CharacterBody3D
class_name player

signal stratagem_activated(stratagem_id: String)
signal player_died

@export var speed: float = 7.0
@export var rotation_speed: float = 10.0

@export var fall_death_y: float = -1.0

@export var max_hp: float = 100.0
@export var hp_regen_rate: float = 20.0
@export var regen_delay: float = 2.0
@export var carried_by_rats: bool = false
@export var required_available_rats_for_movement: int = 0
var is_being_carried: bool = false

signal object_reset

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []
var carrier_available_max: int = 0
var carrier_brush_desired: int = 0

var current_hp: float = 100.0
var time_since_last_damage: float = 0.0

@onready var damage_overlay: ColorRect = $PlayerHUD/DamageOverlay
@onready var health_bar: ProgressBar = $PlayerHUD/HealthBar/Margin/VBox/HealthProgress

var is_stratagem_mode: bool = false
var is_trans_mode: bool = false
var _spawn_position: Vector3 = Vector3.ZERO
var carried_target_pos: Vector3 = Vector3.ZERO
var has_carried_target: bool = false
var _rat_manager: Node = null

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2 # Layer 2: Player
	collision_mask = 13 | (1 << 8) # Floor (1) + Movable (4) + Walls (8) + RatStructures (9)
	_spawn_position = global_position
	current_hp = max_hp
	_update_health_bar()
	_cache_rat_manager()


func _physics_process(delta: float) -> void:
	# HP Regeneration
	time_since_last_damage += delta
	if time_since_last_damage >= regen_delay and current_hp < max_hp:
		current_hp = min(current_hp + hp_regen_rate * delta, max_hp)
		_update_health_bar()
		
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

	if carried_by_rats:
		velocity.x = 0.0
		velocity.z = 0.0
		if is_being_carried and has_carried_target:
			var motion := carried_target_pos - global_position
			move_and_collide(motion)
			return
		# Allow falling even when idle
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 5
		else:
			velocity.y = 0.0
		move_and_slide()
		return

	if is_stratagem_mode:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if is_trans_mode:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var can_move := _has_required_rats_for_manual_movement()
	var input_dir := Vector3.ZERO
	if can_move:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			input_dir.z -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			input_dir.z += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			input_dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			input_dir.x += 1.0
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
	_update_health_bar()
	
	if current_hp <= 0:
		die()


func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos


func die() -> void:
	for box in get_tree().get_nodes_in_group("boxes"):
		if box.has_method("_activate_reset_to_spawn"):
			box._activate_reset_to_spawn()
			
	global_position = _spawn_position
	velocity = Vector3.ZERO
	current_hp = max_hp
	time_since_last_damage = 0.0
	is_stratagem_mode = false
	_update_health_bar()
	player_died.emit()


func set_stratagem_mode(active: bool) -> void:
	is_stratagem_mode = active


func set_rat_manager(rat_manager: Node) -> void:
	_rat_manager = rat_manager


func get_required_available_rats_for_movement() -> int:
	return max(0, required_available_rats_for_movement)


func _update_health_bar() -> void:
	if not health_bar:
		return
	health_bar.max_value = max_hp
	health_bar.value = clampf(current_hp, 0.0, max_hp)


func _cache_rat_manager() -> void:
	if _rat_manager == null:
		_rat_manager = get_tree().get_first_node_in_group("rat_manager")


func _has_required_rats_for_manual_movement() -> bool:
	var required := get_required_available_rats_for_movement()
	if required <= 0:
		return true
	_cache_rat_manager()
	if _rat_manager == null or not _rat_manager.has_method("get_available_rat_count"):
		return true
	return _rat_manager.get_available_rat_count() >= required

func set_highlight(enabled: bool) -> void:
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		return
	if enabled:
		if mesh_instance.material_overlay:
			return
		var highlight_mat := StandardMaterial3D.new()
		highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		highlight_mat.albedo_color = Color.YELLOW
		highlight_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		highlight_mat.no_depth_test = true
		highlight_mat.grow = true
		highlight_mat.grow_amount = 0.03
		mesh_instance.material_overlay = highlight_mat
	else:
		mesh_instance.material_overlay = null
