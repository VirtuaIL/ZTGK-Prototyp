extends CharacterBody3D

enum AIState { WANDER, CHASE, ATTACK, DEAD, PASSIVE }

# ── Health ──
@export var max_health: float = 250.0
@export var respawn_time: float = 3.0
var health: float = max_health

# ── Movement ──
@export var move_speed: float = 2.5
@export var chase_speed: float = 5.0
@export var rotation_speed: float = 8.0

# ── Detection & combat ──
@export var detection_range: float = 16.0
@export var lose_range: float = 22.0
@export var attack_range: float = 1.8
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.0

# ── Wander ──
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

var _attack_timer: float = 0.0
var _player_ref: CharacterBody3D = null

var damage_cooldowns: Dictionary = {}
var _knockback: Vector3 = Vector3.ZERO

# ── HP bar visuals ──
var hp_bar_bg: MeshInstance3D
var hp_bar_fill: MeshInstance3D
var hp_bar_fill_mat: StandardMaterial3D
var hp_label: Label3D


func _ready() -> void:
	add_to_group("enemies")
	# Decouple from parent's non-uniform transform so move_and_slide works
	top_level = true
	_spawn_transform = global_transform
	_collision_layer_saved = collision_layer
	_collision_mask_saved = collision_mask
	health = max_health

	_create_hp_bar()
	_create_hp_label()
	_update_hp_bar()

	# Start with a small random pause so not all enemies move at once
	_wander_pause_timer = randf_range(0.0, wander_pause_max)
	
	# Connect to player death to respawn
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		if p.has_signal("player_died"):
			p.player_died.connect(_respawn)


func _physics_process(delta: float) -> void:
	# ── Gravity ──
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 5.0
	else:
		velocity.y = 0.0

	# ── Map bounds check ──
	# If the enemy falls off the map, it dies
	if global_position.y < -15.0 and not _is_dead:
		_die()
		return

	# ── Tick damage cooldowns ──
	var to_remove: Array = []
	for key in damage_cooldowns:
		damage_cooldowns[key] -= delta
		if damage_cooldowns[key] <= 0.0:
			to_remove.append(key)
	for key in to_remove:
		damage_cooldowns.erase(key)

	# ── AI state machine ──
	match ai_state:
		AIState.PASSIVE:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			return
		AIState.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			return
		AIState.WANDER:
			_process_wander(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.ATTACK:
			_process_attack(delta)

	# Apply and decay knockback
	_knockback = _knockback.lerp(Vector3.ZERO, 10.0 * delta)
	velocity += _knockback

	move_and_slide()


# ═══════════════════════════════════════════════
#  WANDER — idle patrol around spawn
# ═══════════════════════════════════════════════
func _process_wander(delta: float) -> void:
	# Check if player is near
	_find_player()
	if _player_ref and _distance_to_player() < detection_range:
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

	# Move toward wander target
	var to_target := _wander_target - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 0.5:
		# Reached target, start pause
		_has_wander_target = false
		_wander_pause_timer = randf_range(wander_pause_min, wander_pause_max)
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var dir := to_target.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed

	# Face movement direction
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
#  CHASE — move toward player
# ═══════════════════════════════════════════════
func _process_chase(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		return

	var dist := _distance_to_player()

	# Lost player
	if dist > lose_range:
		ai_state = AIState.WANDER
		return

	# Close enough to attack
	if dist < attack_range:
		ai_state = AIState.ATTACK
		_attack_timer = 0.0  # Attack immediately on first contact
		return

	# Move toward player
	var to_player := _player_ref.global_position - global_position
	to_player.y = 0.0
	var dir := to_player.normalized()
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed

	var target_angle := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)


# ═══════════════════════════════════════════════
#  ATTACK — hit player on cooldown
# ═══════════════════════════════════════════════
func _process_attack(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		return

	var dist := _distance_to_player()

	# Player moved away
	if dist > attack_range * 1.5:
		ai_state = AIState.CHASE
		return

	# Face player
	var to_player := _player_ref.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.01:
		var target_angle := atan2(to_player.x, to_player.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

	# Slow down while attacking
	velocity.x = move_toward(velocity.x, 0.0, chase_speed * delta * 5.0)
	velocity.z = move_toward(velocity.z, 0.0, chase_speed * delta * 5.0)

	# Attack timer
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		if _player_ref.has_method("take_damage"):
			_player_ref.take_damage(attack_damage)
		_flash_attack()


# ═══════════════════════════════════════════════
#  F2 PASSIVE TOGGLE
# ═══════════════════════════════════════════════
func toggle_passive() -> void:
	if ai_state == AIState.PASSIVE:
		# Resume normal AI
		ai_state = AIState.WANDER
		_has_wander_target = false
		_wander_pause_timer = randf_range(0.0, wander_pause_max)
	else:
		# Go passive: reset to spawn (also revives dead enemies)
		if _is_dead:
			_respawn()
		ai_state = AIState.PASSIVE
		_has_wander_target = false
		global_transform = _spawn_transform
		velocity = Vector3.ZERO


func is_passive() -> bool:
	return ai_state == AIState.PASSIVE


# ═══════════════════════════════════════════════
#  DAMAGE & DEATH (preserved from original)
# ═══════════════════════════════════════════════
func take_damage(amount: float, source_id: int = -1, hit_pos: Vector3 = Vector3.ZERO) -> void:
	
	if _is_dead or ai_state == AIState.PASSIVE:
		return
	if source_id >= 0:
		if damage_cooldowns.has(source_id):
			return
		damage_cooldowns[source_id] = 0.3

	health -= amount
	health = maxf(health, 0.0)
	_update_hp_bar()
	_flash_hit()

	if hit_pos != Vector3.ZERO:
		var dir := (global_position - hit_pos)
		dir.y = 0.0
		if dir.length() > 0.01:
			_knockback += dir.normalized() * 18.0

	# Being hit by rats? Chase that player!
	if ai_state == AIState.WANDER:
		_find_player()
		if _player_ref:
			ai_state = AIState.CHASE

	if health <= 0.0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	ai_state = AIState.DEAD
	damage_cooldowns.clear()
	collision_layer = 0
	collision_mask = 0

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0, 0, 0), 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		visible = false
	)

	# Stay dead — no auto-respawn. F2 toggle revives all enemies.


func _respawn() -> void:
	_is_dead = false
	visible = true
	scale = Vector3.ONE
	global_transform = _spawn_transform
	health = max_health
	_update_hp_bar()
	collision_layer = _collision_layer_saved
	collision_mask = _collision_mask_saved
	ai_state = AIState.WANDER
	_has_wander_target = false
	_wander_pause_timer = randf_range(wander_pause_min, wander_pause_max)
	velocity = Vector3.ZERO


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


func _flash_attack() -> void:
	# Brief red pulse on attack
	var body: MeshInstance3D = get_child(0) as MeshInstance3D
	if body and body.material_override:
		var original_color: Color = Color(0.8, 0.15, 0.15)
		body.material_override.albedo_color = Color(1.0, 0.4, 0.0)  # Orange flash
		var tween := create_tween()
		tween.tween_property(body.material_override, "albedo_color", original_color, 0.2)


func _flash_hit() -> void:
	var body: MeshInstance3D = get_child(0) as MeshInstance3D
	if body and body.material_override:
		var original_color: Color = Color(0.8, 0.15, 0.15)
		body.material_override.albedo_color = Color(1.0, 1.0, 1.0)
		var tween := create_tween()
		tween.tween_property(body.material_override, "albedo_color", original_color, 0.15)


# ═══════════════════════════════════════════════
#  HP BAR (unchanged from original)
# ═══════════════════════════════════════════════
func _create_hp_bar() -> void:
	var bar_width: float = 1.0
	var bar_height: float = 0.08

	hp_bar_bg = MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(bar_width, bar_height)
	hp_bar_bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.15, 0.15, 0.9)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 1
	hp_bar_bg.material_override = bg_mat
	hp_bar_bg.position.y = 2.2
	add_child(hp_bar_bg)

	hp_bar_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(bar_width, bar_height)
	hp_bar_fill.mesh = fill_mesh
	hp_bar_fill_mat = StandardMaterial3D.new()
	hp_bar_fill_mat.albedo_color = Color(0.2, 0.9, 0.3)
	hp_bar_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hp_bar_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_bar_fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hp_bar_fill_mat.no_depth_test = true
	hp_bar_fill_mat.render_priority = 2
	hp_bar_fill.material_override = hp_bar_fill_mat
	hp_bar_fill.position.y = 2.2
	add_child(hp_bar_fill)


func _create_hp_label() -> void:
	hp_label = Label3D.new()
	hp_label.text = str(int(health))
	hp_label.position.y = 2.4
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.pixel_size = 0.01
	hp_label.outline_size = 6
	hp_label.outline_modulate = Color(0, 0, 0, 0.9)
	add_child(hp_label)


func _update_hp_bar() -> void:
	var ratio: float = health / max_health
	hp_bar_fill.scale.x = ratio
	hp_bar_fill.position.x = - (1.0 - ratio) * 0.5

	if ratio > 0.5:
		hp_bar_fill_mat.albedo_color = Color(0.2, 0.9, 0.3)
	elif ratio > 0.25:
		hp_bar_fill_mat.albedo_color = Color(0.9, 0.8, 0.2)
	else:
		hp_bar_fill_mat.albedo_color = Color(0.9, 0.2, 0.15)

	if hp_label:
		hp_label.text = str(int(ceil(health)))
