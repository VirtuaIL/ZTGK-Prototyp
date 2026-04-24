extends CharacterBody3D
class_name player

signal player_died
signal object_reset

@export var speed: float = 7.0
@export var rotation_speed: float = 10.0

@export var fall_death_y: float = -1.0

@export var max_hp: float = 100.0
@export var hp_regen_rate: float = 20.0
@export var regen_delay: float = 2.0
@export var carriers_required: int = 1

@export_group("Minimap")
@export var minimap_camera_height: float = 38.0
@export var minimap_camera_size: float = 30.0
@export var minimap_follow_smooth: float = 10.0
@export var minimap_camera_margin: float = 1.2
@export var minimap_cursor_focus_factor: float = 0.16666667
@export var minimap_look_ahead_fallback: float = 4.0

var current_hp: float = 100.0
var time_since_last_damage: float = 0.0

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []
var carrier_available_max: int = 0
var carrier_brush_desired: int = 0

var damage_overlay: ColorRect = null
var health_bar: ProgressBar = null

var _spawn_position: Vector3 = Vector3.ZERO
var minimap_camera: Camera3D = null

var _music_particles: GPUParticles3D = null # Legacy ref
var _music_idle: GPUParticles3D = null
var _music_attack: GPUParticles3D = null
var _music_move: GPUParticles3D = null
var _music_follow: GPUParticles3D = null

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2 # Layer 2: Player
	collision_mask = 13 | (1 << 8) # Floor (1) + Movable (4) + Walls (8) + RatStructures (9)
	_ensure_move_actions()
	_resolve_hud_nodes()
	_configure_minimap_visuals()
	_spawn_position = global_position
	current_hp = max_hp
	_update_health_bar()

	_setup_minimap_camera()
	_setup_music_visuals()

func _setup_music_visuals() -> void:
	var music_mgr = get_tree().get_first_node_in_group("music_manager")
	if music_mgr == null:
		return
	
	_music_attack = music_mgr.create_notes_particles(Color(1.0, 0.1, 0.1), 24) # Intense attack
	_music_move = music_mgr.create_notes_particles(Color(0.1, 0.8, 1.0), 4)    # Subtle movement
	_music_follow = music_mgr.create_notes_particles(Color(0.1, 1.0, 0.1), 3)  # Subtle follow
	
	for p in [_music_attack, _music_move, _music_follow]:
		add_child(p)
		p.position = Vector3(0, 1.8, 0)
		p.emitting = false

func _physics_process(delta: float) -> void:
	# Check if music manager is now available
	if _music_attack == null:
		_setup_music_visuals()
	
	# Update music note states
	if _music_attack:
		var is_moving = Vector2(velocity.x, velocity.z).length() > 0.1
		var is_attacking = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		
		# Detect if mouse is actually being moved by the player
		var mouse_vel = Input.get_last_mouse_velocity().length()
		var is_mouse_active = mouse_vel > 20.0 # Threshold to avoid micro-jitters
		
		# Strictly exclusive logic
		if is_attacking:
			_music_attack.emitting = true
			_music_move.emitting = false
			_music_follow.emitting = false
		elif is_moving:
			_music_attack.emitting = false
			_music_move.emitting = true
			_music_follow.emitting = false
		elif is_mouse_active:
			_music_attack.emitting = false
			_music_move.emitting = false
			_music_follow.emitting = true
		else:
			_music_attack.emitting = false
			_music_move.emitting = false
			_music_follow.emitting = false

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

	_apply_movement(delta)

	# Gravity — accumulated independently of horizontal movement
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 5
	else:
		velocity.y = 0.0

	move_and_slide()
	
	# Control music notes visuals
	if _music_particles:
		var horizontal_velocity := Vector2(velocity.x, velocity.z)
		if horizontal_velocity.length() > 0.1:
			if not _music_particles.emitting:
				_music_particles.emitting = true
		else:
			if _music_particles.emitting:
				_music_particles.emitting = false

	_clamp_to_current_level()
	_update_minimap_camera(delta)

	

	


func take_damage(amount: float) -> void:
	current_hp -= amount
	time_since_last_damage = 0.0
	_update_health_bar()


	
	if current_hp <= 0:
		die()


func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos


func _ensure_move_actions() -> void:
	_ensure_action("move_forward", KEY_W)
	_ensure_action("move_back", KEY_S)
	_ensure_action("move_left", KEY_A)
	_ensure_action("move_right", KEY_D)


func _ensure_action(action_name: String, key: Key) -> void:
	if InputMap.has_action(action_name):
		return

	InputMap.add_action(action_name)
	var event := InputEventKey.new()
	event.keycode = key
	InputMap.action_add_event(action_name, event)


func _apply_movement(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_vector.is_zero_approx():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var move_direction := _get_move_direction(input_vector)
	velocity.x = move_direction.x * speed
	velocity.z = move_direction.z * speed

	var target_rotation := atan2(move_direction.x, move_direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, clampf(rotation_speed * delta, 0.0, 1.0))


func _get_move_direction(input_vector: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(input_vector.x, 0.0, input_vector.y).normalized()

	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var move_direction := (right * input_vector.x) - (forward * input_vector.y)
	move_direction.y = 0.0
	return move_direction.normalized()


func _clamp_to_current_level() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null or not current_scene.has_method("clamp_position_to_current_level"):
		return

	var clamped_pos: Vector3 = current_scene.clamp_position_to_current_level(global_position)
	if clamped_pos.is_equal_approx(global_position):
		return

	global_position = clamped_pos
	velocity.x = 0.0
	velocity.z = 0.0


func _configure_minimap_visuals() -> void:
	for child in find_children("*", "VisualInstance3D"):
		child.layers = 2


func _setup_minimap_camera() -> void:
	if minimap_camera == null:
		return

	minimap_camera.top_level = true
	minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	minimap_camera.cull_mask = 1048575 - 2
	_snap_minimap_camera()


func _snap_minimap_camera() -> void:
	if minimap_camera == null:
		return

	minimap_camera.global_position = global_position + Vector3.UP * minimap_camera_height
	minimap_camera.global_transform = Transform3D(_get_minimap_basis(), minimap_camera.global_position)
	minimap_camera.size = _get_minimap_size()


func _update_minimap_camera(delta: float) -> void:
	if minimap_camera == null:
		return

	var target_position := global_position + Vector3.UP * minimap_camera_height
	var weight := 1.0 - exp(-minimap_follow_smooth * delta)
	minimap_camera.global_position = minimap_camera.global_position.lerp(target_position, weight)
	minimap_camera.global_transform = Transform3D(_get_minimap_basis(), minimap_camera.global_position)
	minimap_camera.size = _get_minimap_size()


func _get_minimap_basis() -> Basis:
	var screen_up := Vector3.FORWARD
	var main_camera := get_viewport().get_camera_3d()
	if main_camera != null and main_camera != minimap_camera:
		screen_up = -main_camera.global_transform.basis.z
		screen_up.y = 0.0
		if screen_up.length_squared() > 0.0001:
			screen_up = screen_up.normalized()
		else:
			screen_up = Vector3.FORWARD

	return Basis.looking_at(Vector3.DOWN, screen_up)


func _get_minimap_size() -> float:
	var main_camera := get_viewport().get_camera_3d()
	if main_camera == null or main_camera == minimap_camera:
		return minimap_camera_size

	var visible_rect := get_viewport().get_visible_rect()
	if visible_rect.size.x <= 0.0 or visible_rect.size.y <= 0.0:
		return minimap_camera_size

	var plane_y := global_position.y
	var center_projection: Dictionary = _project_main_camera_to_plane(main_camera, visible_rect.size * 0.5, plane_y)
	if not center_projection.get("valid", false):
		return minimap_camera_size

	var camera_center: Vector3 = center_projection["point"]
	var screen_points := [
		Vector2.ZERO,
		Vector2(visible_rect.size.x, 0.0),
		Vector2(0.0, visible_rect.size.y),
		visible_rect.size,
	]

	var camera_half_extent := minimap_camera_size * 0.5
	for screen_point in screen_points:
		var projection: Dictionary = _project_main_camera_to_plane(main_camera, screen_point, plane_y)
		if not projection.get("valid", false):
			continue

		var world_point: Vector3 = projection["point"]
		var delta := world_point - camera_center
		delta.y = 0.0
		camera_half_extent = maxf(camera_half_extent, maxf(absf(delta.x), absf(delta.z)))

	var look_ahead_max := _get_main_camera_look_ahead_max()
	var player_offset_max := 0.0
	if minimap_cursor_focus_factor < 0.999:
		player_offset_max = (minimap_cursor_focus_factor * camera_half_extent + look_ahead_max) / (1.0 - minimap_cursor_focus_factor)

	var minimap_half_extent := camera_half_extent + player_offset_max
	return maxf(minimap_camera_size, minimap_half_extent * 2.0 * minimap_camera_margin)


func _get_main_camera_look_ahead_max() -> float:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		var value: Variant = current_scene.get("cam_look_ahead_max")
		if value is float:
			return value
		if value is int:
			return float(value)
	return minimap_look_ahead_fallback


func _project_main_camera_to_plane(camera: Camera3D, screen_point: Vector2, plane_y: float) -> Dictionary:
	var ray_origin := camera.project_ray_origin(screen_point)
	var ray_direction := camera.project_ray_normal(screen_point)
	if absf(ray_direction.y) <= 0.0001:
		return {"valid": false}

	var distance := (plane_y - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return {"valid": false}

	return {
		"valid": true,
		"point": ray_origin + ray_direction * distance,
	}


func die() -> void:
	for box in get_tree().get_nodes_in_group("boxes"):
		if box.has_method("_activate_reset_to_spawn"):
			box._activate_reset_to_spawn()
			
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_snap_minimap_camera()
	current_hp = max_hp
	time_since_last_damage = 0.0
	_update_health_bar()


	object_reset.emit()
	player_died.emit()


	

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
func _resolve_hud_nodes() -> void:
	var scene_root := get_tree().current_scene
	if scene_root != null:
		damage_overlay = scene_root.get_node_or_null("GameHUD/HUDRoot/PlayerHUD/DamageOverlay") as ColorRect
		health_bar = scene_root.get_node_or_null("GameHUD/HUDRoot/PlayerHUD/HealthBar/Margin/VBox/HealthProgress") as ProgressBar
		minimap_camera = scene_root.get_node_or_null("GameHUD/HUDRoot/PlayerHUD/MinimapPanel/Margin/SubViewportContainer/SubViewport/MinimapCamera") as Camera3D

	# Fallback for legacy scene layout
	if damage_overlay == null:
		damage_overlay = get_node_or_null("PlayerHUD/DamageOverlay") as ColorRect
	if health_bar == null:
		health_bar = get_node_or_null("PlayerHUD/HealthBar/Margin/VBox/HealthProgress") as ProgressBar
	if minimap_camera == null:
		minimap_camera = get_node_or_null("PlayerHUD/MinimapPanel/Margin/SubViewportContainer/SubViewport/MinimapCamera") as Camera3D
