extends CharacterBody3D
class_name player

signal stratagem_activated(stratagem_id: String)
signal player_died
signal object_reset

@export var speed: float = 7.0
@export var rotation_speed: float = 10.0

@export var fall_death_y: float = -1.0

@export var max_hp: float = 100.0
@export var hp_regen_rate: float = 20.0
@export var regen_delay: float = 2.0
@export var carriers_required: int = 1

var current_hp: float = 100.0
var time_since_last_damage: float = 0.0

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []
var carrier_available_max: int = 0
var carrier_brush_desired: int = 0

@onready var damage_overlay: ColorRect = $PlayerHUD/DamageOverlay
@onready var health_bar: ProgressBar = $PlayerHUD/HealthBar/Margin/VBox/HealthProgress

var is_stratagem_mode: bool = false
var _spawn_position: Vector3 = Vector3.ZERO

@onready var minimap_camera: Camera3D = $PlayerHUD/MinimapPanel/Margin/SubViewportContainer/SubViewport/MinimapCamera

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2 # Layer 2: Player
	collision_mask = 13 | (1 << 8) # Floor (1) + Movable (4) + Walls (8) + RatStructures (9)
	_spawn_position = global_position
	current_hp = max_hp
	_update_health_bar()

	if minimap_camera:
		minimap_camera.top_level = true
		minimap_camera.global_position = Vector3(0, 50.0, 0)
		minimap_camera.size = 65.0
		minimap_camera.cull_mask = 1048575 - 2


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

	if is_stratagem_mode:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = Vector3.ZERO
	var cam = get_viewport().get_camera_3d()
	
	if cam:
		direction = (cam.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y))
		direction.y = 0
		direction = direction.normalized()
	else:
		direction = Vector3(input_dir.x, 0, input_dir.y).normalized()

	if direction.length_squared() > 0.01:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# Rotate player towards movement direction
		var target_angle = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

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
	_update_health_bar()


	object_reset.emit()
	player_died.emit()


func set_stratagem_mode(active: bool) -> void:
	is_stratagem_mode = active
	

func _update_health_bar() -> void:
	if not health_bar:
		return
	health_bar.max_value = max_hp
	health_bar.value = clampf(current_hp, 0.0, max_hp)

func set_highlight(enabled: bool) -> void:
	_set_highlight_recursive(self, enabled)

func _set_highlight_recursive(node: Node, enabled: bool) -> void:
	if node is MeshInstance3D:
		if enabled:
			if not node.material_overlay:
				var highlight_mat = StandardMaterial3D.new()
				highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				highlight_mat.albedo_color = Color.YELLOW
				highlight_mat.cull_mode = BaseMaterial3D.CULL_FRONT
				highlight_mat.no_depth_test = true
				highlight_mat.grow = true
				highlight_mat.grow_amount = 0.05
				node.material_overlay = highlight_mat
		else:
			node.material_overlay = null
	for child in node.get_children():
		_set_highlight_recursive(child, enabled)
