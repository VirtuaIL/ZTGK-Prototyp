extends CharacterBody3D

enum AIState {WANDER, SUSPICIOUS, CHASE, CATCH, PASSIVE}

# ── Movement ──
@export var move_speed: float = 1.4
@export var chase_speed: float = 3.2
@export var rotation_speed: float = 8.0

# ── Detection (FOV cone) ──
@export var fov_angle: float = 60.0          # Half-angle of the vision cone (degrees)
@export var view_range: float = 14.0         # How far the enemy can see
@export var catch_range: float = 1.8         # Distance to instantly catch the player
@export var lose_range: float = 20.0         # Distance at which the enemy gives up chasing
@export var suspicion_time: float = 1.5      # Seconds of continuous sight before CATCH
@export var alert_decay_rate: float = 1.0    # Suspicion lost per second when player not visible

# ── Wander / patrol ──
@export var wander_radius: float = 5.0
@export var wander_pause_min: float = 1.0
@export var wander_pause_max: float = 3.0

# ── Internal state ──
var ai_state: AIState = AIState.WANDER
var _spawn_transform: Transform3D
var _is_dead: bool = false
var _collision_layer_saved: int
var _collision_mask_saved: int

var _wander_target: Vector3 = Vector3.ZERO
var _wander_pause_timer: float = 0.0
var _has_wander_target: bool = false

var _suspicion_level: float = 0.0  # 0 → suspicion_time = fully alerted
var _player_ref: CharacterBody3D = null
var _last_known_player_pos: Vector3 = Vector3.ZERO

# ── Detection indicator ──
var _indicator: Label3D

# ── Visual FOV cone ──
var _fov_mesh: MeshInstance3D
var _fov_material: StandardMaterial3D
const FOV_SEGMENTS: int = 24
const FOV_Y_OFFSET: float = 0.05  # Slightly above floor to avoid z-fighting


func _ready() -> void:
	add_to_group("enemies")
	top_level = true
	collision_mask = collision_mask | (1 << 8)
	_spawn_transform = global_transform
	_collision_layer_saved = collision_layer
	_collision_mask_saved = collision_mask

	_create_indicator()
	_create_fov_cone()

	_wander_pause_timer = randf_range(0.0, wander_pause_max)

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		if p.has_signal("player_died"):
			p.player_died.connect(_on_player_died)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	# ── Gravity ──
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 5.0
	else:
		velocity.y = 0.0

	# ── Map bounds ──
	if global_position.y < -15.0:
		_die()
		return

	# ── AI state machine ──
	match ai_state:
		AIState.PASSIVE:
			velocity.x = 0.0
			velocity.z = 0.0
		AIState.WANDER:
			_process_wander(delta)
		AIState.SUSPICIOUS:
			_process_suspicious(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.CATCH:
			velocity.x = 0.0
			velocity.z = 0.0

	_update_indicator()
	_update_fov_cone()
	move_and_slide()


# ═══════════════════════════════════════════════
#  WANDER — idle patrol around spawn
# ═══════════════════════════════════════════════
func _process_wander(delta: float) -> void:
	_find_player()

	# Check FOV
	if _can_see_player():
		_suspicion_level += delta
		if _suspicion_level >= suspicion_time:
			ai_state = AIState.CHASE
			_has_wander_target = false
			return
		ai_state = AIState.SUSPICIOUS
		_has_wander_target = false
		return
	else:
		_suspicion_level = maxf(0.0, _suspicion_level - alert_decay_rate * delta)

	# Pause between wander movements
	if not _has_wander_target:
		_wander_pause_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * delta * 5.0)
		if _wander_pause_timer <= 0.0:
			_pick_wander_target()
		return

	var to_target := _wander_target - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 0.5:
		_has_wander_target = false
		_wander_pause_timer = randf_range(wander_pause_min, wander_pause_max)
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var dir := to_target.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

	var target_angle := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)


func _pick_wander_target() -> void:
	var spawn_pos := _spawn_transform.origin
	var angle := randf() * TAU
	var radius := randf_range(1.0, wander_radius)
	_wander_target = spawn_pos + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_wander_target.y = global_position.y
	_has_wander_target = true


# ═══════════════════════════════════════════════
#  SUSPICIOUS — player spotted, building suspicion
# ═══════════════════════════════════════════════
func _process_suspicious(delta: float) -> void:
	if _can_see_player():
		_suspicion_level += delta
		_last_known_player_pos = _player_ref.global_position

		# Face player
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

		if _suspicion_level >= suspicion_time:
			# Suspicion bar full — catch immediately, no chase phase
			_catch_player()
			return
	else:
		_suspicion_level -= alert_decay_rate * delta
		if _suspicion_level <= 0.0:
			_suspicion_level = 0.0
			ai_state = AIState.WANDER
			return

	# Slow approach while suspicious
	velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 3.0)
	velocity.z = move_toward(velocity.z, 0.0, move_speed * delta * 3.0)


# ═══════════════════════════════════════════════
#  CHASE — pursue the player
# ═══════════════════════════════════════════════
func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		_suspicion_level = 0.0
		return

	# Update last known position if we can still see them
	if _can_see_player():
		_last_known_player_pos = _player_ref.global_position

	var dist := _distance_to_player()

	# Reached the player → catch!
	if dist < catch_range:
		_catch_player()
		return

	# Lost player
	if dist > lose_range:
		ai_state = AIState.WANDER
		_suspicion_level = 0.0
		return

	# Move toward player (or last known position)
	var chase_target := _player_ref.global_position if _can_see_player() else _last_known_player_pos
	var to_target := chase_target - global_position
	to_target.y = 0.0
	var dir := to_target.normalized()
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed

	var target_angle := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

	# If chasing last known pos and arrived, give up
	if not _can_see_player():
		var flat_dist := Vector2(global_position.x - _last_known_player_pos.x, global_position.z - _last_known_player_pos.z).length()
		if flat_dist < 1.5:
			ai_state = AIState.WANDER
			_suspicion_level = 0.0


# ═══════════════════════════════════════════════
#  CATCH — player is caught, instant reset
# ═══════════════════════════════════════════════
func _catch_player() -> void:
	ai_state = AIState.CATCH
	if _player_ref and _player_ref.has_method("die"):
		_player_ref.die()
	# After catch, return to wander after a moment
	await get_tree().create_timer(1.0).timeout
	ai_state = AIState.WANDER
	_suspicion_level = 0.0
	global_transform = _spawn_transform
	velocity = Vector3.ZERO


# ═══════════════════════════════════════════════
#  FOV DETECTION
# ═══════════════════════════════════════════════
func _can_see_player() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_find_player()
		if _player_ref == null:
			return false

	var to_player := _player_ref.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	# Range check
	if dist > view_range:
		return false

	# Angle check (FOV cone)
	var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var angle_to_player := rad_to_deg(forward.angle_to(to_player.normalized()))
	if angle_to_player > fov_angle:
		return false

	# Line-of-sight raycast
	var space_state := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 1.0
	var target := _player_ref.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.collision_mask = 1 | 2 | 8 | (1 << 8)  # Floor + Player + Walls + RatStructures
	query.exclude = [self.get_rid()]
	var hit := space_state.intersect_ray(query)

	if hit and hit.collider == _player_ref:
		return true

	return false


# ═══════════════════════════════════════════════
#  F2 PASSIVE TOGGLE (preserved)
# ═══════════════════════════════════════════════
func toggle_passive() -> void:
	if ai_state == AIState.PASSIVE:
		ai_state = AIState.WANDER
		_has_wander_target = false
		_wander_pause_timer = randf_range(0.0, wander_pause_max)
		_suspicion_level = 0.0
	else:
		if _is_dead:
			_respawn()
		ai_state = AIState.PASSIVE
		_has_wander_target = false
		_suspicion_level = 0.0
		global_transform = _spawn_transform
		velocity = Vector3.ZERO


func is_passive() -> bool:
	return ai_state == AIState.PASSIVE


# ═══════════════════════════════════════════════
#  DEATH / RESPAWN (preserved for compatibility)
# ═══════════════════════════════════════════════
func take_damage(_amount: float, _source_id: int = -1, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	pass


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	set_physics_process(false)
	visible = false


func _respawn() -> void:
	_is_dead = false
	set_physics_process(true)
	visible = true
	scale = Vector3.ONE
	var body: MeshInstance3D = get_child(0) as MeshInstance3D
	if body:
		body.scale = Vector3.ONE
	global_transform = _spawn_transform
	collision_layer = _collision_layer_saved
	collision_mask = _collision_mask_saved
	ai_state = AIState.WANDER
	_has_wander_target = false
	_suspicion_level = 0.0
	_wander_pause_timer = randf_range(wander_pause_min, wander_pause_max)
	velocity = Vector3.ZERO


func _on_player_died() -> void:
	_respawn()


# ═══════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════
func _find_player() -> void:
	if _player_ref != null and is_instance_valid(_player_ref):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player_ref = players[0] as CharacterBody3D


func _distance_to_player() -> float:
	if _player_ref == null:
		return INF
	var dx := global_position.x - _player_ref.global_position.x
	var dz := global_position.z - _player_ref.global_position.z
	return sqrt(dx * dx + dz * dz)


# ═══════════════════════════════════════════════
#  DETECTION INDICATOR (replaces HP bar)
# ═══════════════════════════════════════════════
func _create_indicator() -> void:
	_indicator = Label3D.new()
	_indicator.text = ""
	_indicator.position.y = 2.2
	_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_indicator.pixel_size = 0.01
	_indicator.font_size = 48
	_indicator.outline_size = 8
	_indicator.outline_modulate = Color(0, 0, 0, 0.9)
	add_child(_indicator)


func _update_indicator() -> void:
	if _indicator == null:
		return

	match ai_state:
		AIState.WANDER, AIState.PASSIVE:
			if _suspicion_level > 0.0:
				_indicator.text = "?"
				_indicator.modulate = Color(1.0, 0.9, 0.2)
			else:
				_indicator.text = ""
		AIState.SUSPICIOUS:
			var pct := _suspicion_level / suspicion_time
			_indicator.text = "?"
			_indicator.modulate = Color(1.0, 0.6 * (1.0 - pct), 0.0)
			_indicator.font_size = int(lerpf(48.0, 72.0, pct))
		AIState.CHASE, AIState.CATCH:
			_indicator.text = "!"
			_indicator.modulate = Color(1.0, 0.1, 0.1)
			_indicator.font_size = 72


# ═══════════════════════════════════════════════
#  VISUAL FOV CONE
# ═══════════════════════════════════════════════
func _create_fov_cone() -> void:
	_fov_mesh = MeshInstance3D.new()
	_fov_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_fov_material = StandardMaterial3D.new()
	_fov_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fov_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fov_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fov_material.no_depth_test = false
	_fov_material.albedo_color = Color(0.2, 0.8, 0.3, 0.18)
	_fov_mesh.material_override = _fov_material

	var im := ImmediateMesh.new()
	_fov_mesh.mesh = im
	_rebuild_fov_geometry(im)

	add_child(_fov_mesh)


func _rebuild_fov_geometry(im: ImmediateMesh) -> void:
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_angle_rad := deg_to_rad(fov_angle)
	var origin := Vector3(0.0, FOV_Y_OFFSET, 0.0)

	for i in range(FOV_SEGMENTS):
		var t0 := float(i) / float(FOV_SEGMENTS)
		var t1 := float(i + 1) / float(FOV_SEGMENTS)
		var angle0 := lerpf(-half_angle_rad, half_angle_rad, t0)
		var angle1 := lerpf(-half_angle_rad, half_angle_rad, t1)

		var p0 := Vector3(sin(angle0) * view_range, FOV_Y_OFFSET, cos(angle0) * view_range)
		var p1 := Vector3(sin(angle1) * view_range, FOV_Y_OFFSET, cos(angle1) * view_range)

		var alpha0: float = 0.22 * (1.0 - abs(t0 - 0.5) * 2.0)
		var alpha1: float = 0.22 * (1.0 - abs(t1 - 0.5) * 2.0)

		im.surface_set_color(Color(1, 1, 1, 0.3))
		im.surface_add_vertex(origin)
		im.surface_set_color(Color(1, 1, 1, alpha0))
		im.surface_add_vertex(p0)
		im.surface_set_color(Color(1, 1, 1, alpha1))
		im.surface_add_vertex(p1)

	im.surface_end()


func _update_fov_cone() -> void:
	if _fov_mesh == null or _fov_material == null:
		return

	if ai_state == AIState.PASSIVE or ai_state == AIState.CATCH or _is_dead:
		_fov_mesh.visible = false
		return
	_fov_mesh.visible = true

	var cone_color: Color
	match ai_state:
		AIState.WANDER:
			if _suspicion_level > 0.0:
				var pct := _suspicion_level / suspicion_time
				cone_color = Color(0.2, 0.8, 0.3, 0.18).lerp(Color(1.0, 0.8, 0.1, 0.28), pct)
			else:
				cone_color = Color(0.2, 0.8, 0.3, 0.18)
		AIState.SUSPICIOUS:
			var pct := _suspicion_level / suspicion_time
			cone_color = Color(1.0, 0.7, 0.1, 0.28).lerp(Color(1.0, 0.2, 0.1, 0.4), pct)
		AIState.CHASE:
			cone_color = Color(1.0, 0.15, 0.1, 0.35)
		_:
			cone_color = Color(0.2, 0.8, 0.3, 0.18)

	_fov_material.albedo_color = cone_color

	_fov_mesh.position = Vector3.ZERO
	_fov_mesh.rotation = Vector3.ZERO
