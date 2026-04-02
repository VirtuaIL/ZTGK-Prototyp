extends CharacterBody3D

enum AIState {WANDER, CHASE, ATTACK, DEAD, PASSIVE}

# ── Movement ──
@export var move_speed: float = 1.4
@export var chase_speed: float = 3.2
@export var rotation_speed: float = 8.0

# ── Detection ──
@export var detection_range: float = 14.0    # How far the enemy can detect the player/rats
@export var attack_range: float = 2.0        # Distance to start attacking
@export var lose_range: float = 25.0         # Distance at which the enemy gives up chasing

# ── Health ──
@export var max_hp: float = 100.0
var current_hp: float = 100.0

# ── Combat ──
@export var attack_damage: float = 15.0      # Damage dealt to player per hit
@export var attack_cooldown_time: float = 1.2 # Seconds between attacks
var _attack_cooldown: float = 0.0

# ── Wander / patrol ──
@export var patrol_path: NodePath
var _patrol_points: Array[Vector3] = []
var _current_patrol_index: int = 0

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

var _player_ref: CharacterBody3D = null
var _last_known_player_pos: Vector3 = Vector3.ZERO

# ── Visual indicator ──
var _indicator: Label3D

# ── HP Bar ──
var _hp_bar: Label3D

# ── Damage flash ──
var _damage_flash_timer: float = 0.0
var _original_color: Color = Color.WHITE
var _body_mesh: MeshInstance3D = null


func _ready() -> void:
	add_to_group("enemies")
	top_level = true
	collision_mask = collision_mask | (1 << 8)
	_spawn_transform = global_transform
	_collision_layer_saved = collision_layer
	_collision_mask_saved = collision_mask
	current_hp = max_hp

	_create_indicator()
	_create_hp_bar()
	
	# Find body mesh for damage flash
	_body_mesh = get_child(0) as MeshInstance3D

	if patrol_path != NodePath():
		var path_node = get_node_or_null(patrol_path)
		if path_node:
			for child in path_node.get_children():
				if child is Node3D:
					_patrol_points.append(child.global_position)
		_resume_patrol()

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

	# ── Attack cooldown ──
	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	
	# ── Damage flash ──
	if _damage_flash_timer > 0.0:
		_damage_flash_timer -= delta
		if _damage_flash_timer <= 0.0 and _body_mesh:
			# Reset color
			if _body_mesh.material_overlay:
				_body_mesh.material_overlay = null

	# ── AI state machine ──
	match ai_state:
		AIState.PASSIVE:
			velocity.x = 0.0
			velocity.z = 0.0
		AIState.WANDER:
			_process_wander(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.ATTACK:
			_process_attack(delta)
		AIState.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0

	_update_indicator()
	_update_hp_bar()
	move_and_slide()


# ═══════════════════════════════════════════════
#  WANDER — idle patrol around spawn
# ═══════════════════════════════════════════════
func _process_wander(delta: float) -> void:
	_find_player()

	# Simple detection — if player is within range, chase!
	if _can_detect_player():
		ai_state = AIState.CHASE
		_has_wander_target = false
		return

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


func _resume_patrol() -> void:
	if _patrol_points.size() > 0:
		var closest_idx := 0
		var min_dist := INF
		for i in range(_patrol_points.size()):
			var d := global_position.distance_squared_to(_patrol_points[i])
			if d < min_dist:
				min_dist = d
				closest_idx = i
		_current_patrol_index = closest_idx

func _pick_wander_target() -> void:
	if _patrol_points.size() > 0:
		var target: Vector3 = _patrol_points[_current_patrol_index]
		_wander_target = target
		_wander_target.y = global_position.y
		_has_wander_target = true
		_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
	else:
		var spawn_pos := _spawn_transform.origin
		var angle := randf() * TAU
		var radius := randf_range(1.0, wander_radius)
		_wander_target = spawn_pos + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_wander_target.y = global_position.y
		_has_wander_target = true


# ═══════════════════════════════════════════════
#  CHASE — pursue the player
# ═══════════════════════════════════════════════
func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		_resume_patrol()
		return

	var dist := _distance_to_player()

	# Close enough → attack!
	if dist < attack_range:
		ai_state = AIState.ATTACK
		return

	# Lost player
	if dist > lose_range:
		ai_state = AIState.WANDER
		_resume_patrol()
		return

	# Move toward player
	var to_target := _player_ref.global_position - global_position
	to_target.y = 0.0
	var dir := to_target.normalized()
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed

	var target_angle := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)


# ═══════════════════════════════════════════════
#  ATTACK — deal damage to player when in range
# ═══════════════════════════════════════════════
func _process_attack(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		_resume_patrol()
		return

	var dist := _distance_to_player()

	# If player moved out of attack range, chase again
	if dist > attack_range * 1.5:
		ai_state = AIState.CHASE
		return

	# Face the player
	var to_player := _player_ref.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.01:
		var target_angle := atan2(to_player.x, to_player.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

	# Stop moving while attacking
	velocity.x = move_toward(velocity.x, 0.0, chase_speed * delta * 5.0)
	velocity.z = move_toward(velocity.z, 0.0, chase_speed * delta * 5.0)

	# Deal damage on cooldown
	if _attack_cooldown <= 0.0:
		if _player_ref.has_method("take_damage"):
			_player_ref.take_damage(attack_damage)
		_attack_cooldown = attack_cooldown_time


# ═══════════════════════════════════════════════
#  DETECTION — simple range-based (no FOV cone / stealth)
# ═══════════════════════════════════════════════
func _can_detect_player() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_find_player()
		if _player_ref == null:
			return false

	var dist := _distance_to_player()
	if dist > detection_range:
		return false

	# Line-of-sight raycast (still check for walls)
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
		_resume_patrol()
	else:
		if _is_dead:
			_respawn()
		ai_state = AIState.PASSIVE
		_has_wander_target = false
		global_transform = _spawn_transform
		velocity = Vector3.ZERO


func is_passive() -> bool:
	return ai_state == AIState.PASSIVE


# ═══════════════════════════════════════════════
#  DAMAGE / DEATH / RESPAWN
# ═══════════════════════════════════════════════
func take_damage(amount: float, _source_id: int = -1, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	if _is_dead:
		return
	current_hp -= amount
	
	# Damage flash
	_damage_flash_timer = 0.15
	if _body_mesh:
		var flash_mat := StandardMaterial3D.new()
		flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flash_mat.albedo_color = Color(1.0, 0.3, 0.3, 0.6)
		flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_body_mesh.material_overlay = flash_mat
	
	# If not already chasing, start chasing
	if ai_state == AIState.WANDER or ai_state == AIState.PASSIVE:
		_find_player()
		ai_state = AIState.CHASE
	
	if current_hp <= 0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	ai_state = AIState.DEAD
	set_physics_process(false)
	visible = false
	collision_layer = 0
	collision_mask = 0
	
	# Respawn after delay
	await get_tree().create_timer(5.0).timeout
	_respawn()


func _respawn() -> void:
	_is_dead = false
	current_hp = max_hp
	set_physics_process(true)
	visible = true
	scale = Vector3.ONE
	var body: MeshInstance3D = get_child(0) as MeshInstance3D
	if body:
		body.scale = Vector3.ONE
		body.material_overlay = null
	global_transform = _spawn_transform
	collision_layer = _collision_layer_saved
	collision_mask = _collision_mask_saved
	ai_state = AIState.WANDER
	_has_wander_target = false
	_wander_pause_timer = randf_range(wander_pause_min, wander_pause_max)
	velocity = Vector3.ZERO
	_attack_cooldown = 0.0
	_resume_patrol()


func _on_player_died() -> void:
	# Return to wander when player dies (respawns)
	if ai_state == AIState.CHASE or ai_state == AIState.ATTACK:
		ai_state = AIState.WANDER
		_has_wander_target = false
		_resume_patrol()


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
#  DETECTION INDICATOR
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
			_indicator.text = ""
		AIState.CHASE:
			_indicator.text = "!"
			_indicator.modulate = Color(1.0, 0.5, 0.1)
			_indicator.font_size = 60
		AIState.ATTACK:
			_indicator.text = "⚔"
			_indicator.modulate = Color(1.0, 0.1, 0.1)
			_indicator.font_size = 72
		AIState.DEAD:
			_indicator.text = ""


# ═══════════════════════════════════════════════
#  HP BAR
# ═══════════════════════════════════════════════
func _create_hp_bar() -> void:
	_hp_bar = Label3D.new()
	_hp_bar.text = ""
	_hp_bar.position.y = 2.6
	_hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar.pixel_size = 0.008
	_hp_bar.font_size = 32
	_hp_bar.outline_size = 4
	_hp_bar.outline_modulate = Color(0, 0, 0, 0.8)
	add_child(_hp_bar)


func _update_hp_bar() -> void:
	if _hp_bar == null:
		return
	
	if _is_dead or current_hp >= max_hp:
		_hp_bar.text = ""
		return
	
	var ratio := clampf(current_hp / max_hp, 0.0, 1.0)
	var bar_length := 10
	var filled := int(round(ratio * bar_length))
	var empty := bar_length - filled
	
	_hp_bar.text = "█".repeat(filled) + "░".repeat(empty)
	
	# Color based on HP ratio
	if ratio > 0.6:
		_hp_bar.modulate = Color(0.3, 1.0, 0.3)
	elif ratio > 0.3:
		_hp_bar.modulate = Color(1.0, 0.8, 0.2)
	else:
		_hp_bar.modulate = Color(1.0, 0.2, 0.2)
