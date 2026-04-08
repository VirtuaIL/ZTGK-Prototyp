extends CharacterBody3D

const CheeseScene := preload("res://scenes/rat/cheese.tscn")
const DamageTextScene := preload("res://scenes/ui/damage_text.tscn")

signal enemy_died

enum AIState { WANDER, CHASE, ATTACK, DEAD, PASSIVE }

# ── Health ──
@export var max_health: float = 120.0
@export var respawn_time: float = 3.0
var health: float = max_health

# ── Movement ──
@export var move_speed: float = 1.4
@export var chase_speed: float = 2.6
@export var rotation_speed: float = 8.0

# ── Detection & combat ──
@export var detection_range: float = 16.0
@export var lose_range: float = 22.0
@export var attack_range: float = 3.0
@export var attack_damage: float = 15.0
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

enum AttackType { NONE, SLASH, STEP }
var current_attack: AttackType = AttackType.NONE
var attack_prepare_timer: float = 0.0
@export var attack_delay: float = 0.5
var attack_marker: MeshInstance3D = null

var damage_cooldowns: Dictionary = {}
var _knockback: Vector3 = Vector3.ZERO
var level_id: int = 0

# ── HP bar visuals ──
var hp_bar_bg: MeshInstance3D
var hp_bar_fill: MeshInstance3D
var hp_bar_fill_mat: StandardMaterial3D
var hp_label: Label3D

var is_stuck_in_blob: bool = false
var blob_center: Vector3 = Vector3.ZERO


func _ready() -> void:
	for child in find_children("*", "VisualInstance3D"):
		child.layers = 2
	add_to_group("enemies")
	# Decouple from parent's non-uniform transform so move_and_slide works
	top_level = true
	collision_mask = collision_mask | (1 << 8) # Include RatStructures (9)
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
			pass #p.player_died.connect(_respawn)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
		
	if is_stuck_in_blob:
		var target := blob_center
		target.y = global_position.y
		global_position = target
		velocity = Vector3.ZERO
		move_and_slide()
		current_attack = AttackType.NONE
		if attack_marker != null:
			attack_marker.visible = false
		return

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
			return
		AIState.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0
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
	# Check if player/rat is near
	_find_target()
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
	_find_target()
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

	# Slow down while attacking
	velocity.x = move_toward(velocity.x, 0.0, chase_speed * delta * 5.0)
	velocity.z = move_toward(velocity.z, 0.0, chase_speed * delta * 5.0)

	if current_attack != AttackType.NONE:
		# We are winding up an attack
		attack_prepare_timer -= delta
		if attack_prepare_timer <= 0.0:
			_execute_attack()
			current_attack = AttackType.NONE
			_attack_timer = attack_cooldown
		return

	# Attack timer
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		if dist > attack_range * 1.5:
			ai_state = AIState.CHASE
			return
		_pick_and_start_attack()
	else:
		# Face target while waiting
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

func _pick_and_start_attack() -> void:
	var mgr = get_tree().get_first_node_in_group("rat_manager")
	var rat_count = 0
	if mgr != null and "rats" in mgr:
		var are_visible = not mgr.has_method("are_rats_hidden") or not mgr.are_rats_hidden()
		var purple_active = mgr.get("buff_purple_timer") != null and mgr.buff_purple_timer > 0.0
		if are_visible and not purple_active:
			for rat in mgr.rats:
				if is_instance_valid(rat) and rat.global_position.distance_squared_to(global_position) < attack_range * attack_range:
					rat_count += 1
				
	if rat_count > 3:
		current_attack = AttackType.STEP
	else:
		current_attack = AttackType.SLASH
		
	attack_prepare_timer = attack_delay
	# Flash yellow to indicate windup
	var body: MeshInstance3D = get_child(0) as MeshInstance3D
	if body and body.material_override:
		body.material_override.albedo_color = Color(1.0, 1.0, 0.0)
		
	if attack_marker == null:
		attack_marker = MeshInstance3D.new()
		attack_marker.layers = 2
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2, 0.0, 0.2)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		attack_marker.material_override = mat
		add_child(attack_marker)
		
	attack_marker.visible = true
	var immediate = ImmediateMesh.new()
	attack_marker.mesh = immediate
	immediate.clear_surfaces()
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var r = attack_range
	if current_attack == AttackType.STEP:
		var segments = 32
		for i in range(segments):
			var a1 = (float(i) / segments) * TAU
			var a2 = (float(i + 1) / segments) * TAU
			immediate.surface_add_vertex(Vector3(0, 0.1, 0))
			immediate.surface_add_vertex(Vector3(sin(a1)*r, 0.1, cos(a1)*r))
			immediate.surface_add_vertex(Vector3(sin(a2)*r, 0.1, cos(a2)*r))
	else:
		var segments = 16
		for i in range(segments):
			var a1 = -PI/4 + (float(i)/segments) * (PI/2)
			var a2 = -PI/4 + (float(i+1)/segments) * (PI/2)
			immediate.surface_add_vertex(Vector3(0, 0.1, 0))
			immediate.surface_add_vertex(Vector3(-sin(a1)*r, 0.1, cos(a1)*r)) # local forward in godot is +z normally? We used -sin, 0, cos for forward.
			immediate.surface_add_vertex(Vector3(-sin(a2)*r, 0.1, cos(a2)*r))
	immediate.surface_end()

func _execute_attack() -> void:
	if attack_marker != null:
		attack_marker.visible = false
	_flash_attack()
	
	var targets = []
	var players = get_tree().get_nodes_in_group("player")
	var mgr = get_tree().get_first_node_in_group("rat_manager")
	targets.append_array(players)
	if mgr != null and "rats" in mgr:
		var are_visible = not mgr.has_method("are_rats_hidden") or not mgr.are_rats_hidden()
		var purple_active = mgr.get("buff_purple_timer") != null and mgr.buff_purple_timer > 0.0
		if are_visible and not purple_active:
			for r in mgr.rats:
				if is_instance_valid(r):
					targets.append(r)
		
	var r_radius = attack_range
	var slash_angle = deg_to_rad(45.0) # 45 each side = 90 deg total
	var my_forward = Vector3(sin(rotation.y), 0, cos(rotation.y))
	
	for t in targets:
		if not is_instance_valid(t) or not t.is_inside_tree():
			continue
		var to_t = t.global_position - global_position
		to_t.y = 0.0
		var d = to_t.length()
		
		if current_attack == AttackType.STEP:
			if d <= r_radius:
				_damage_target(t)
		elif current_attack == AttackType.SLASH:
			if d <= r_radius:
				var dir = to_t.normalized()
				var angle_diff = acos(clampf(my_forward.dot(dir), -1.0, 1.0))
				if angle_diff <= slash_angle:
					_damage_target(t)

func _damage_target(t: Node3D) -> void:
	if t.is_in_group("player") and t.has_method("take_damage"):
		t.take_damage(attack_damage)
	elif t is Rat and t.has_method("die"):
		t.die()


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


func is_dead() -> bool:
	return _is_dead


# ═══════════════════════════════════════════════
#  DAMAGE & DEATH (preserved from original)
# ═══════════════════════════════════════════════
func take_damage(amount: float, source_id: int = -1, hit_pos: Vector3 = Vector3.ZERO, text_color: Color = Color.WHITE) -> void:
	
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

	if DamageTextScene:
		var dt = DamageTextScene.instantiate()
		get_parent().add_child(dt)
		dt.global_position = global_position + Vector3(0, 1.5, 0)
		if hit_pos != Vector3.ZERO:
			dt.global_position = hit_pos + Vector3(0, 0.5, 0)
		dt.set_damage(int(ceil(amount)), text_color)

	if hit_pos != Vector3.ZERO:
		var dir := (global_position - hit_pos)
		dir.y = 0.0
		if dir.length() > 0.01:
			_knockback += dir.normalized() * 1.0
			if _knockback.length() > 5.0:
				_knockback = _knockback.normalized() * 5.0

	if ai_state == AIState.WANDER:
		_find_target()
		if _player_ref:
			ai_state = AIState.CHASE

	if health <= 0.0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	set_physics_process(false)
	ai_state = AIState.DEAD
	damage_cooldowns.clear()
	collision_layer = 0
	collision_mask = 0

	var body: MeshInstance3D = get_child(0) as MeshInstance3D
	var tween := create_tween()
	if body:
		tween.tween_property(body, "scale", Vector3(0, 0, 0), 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		visible = false
		enemy_died.emit()
		
		if randf() <= 0.5:
			if CheeseScene:
				var c = CheeseScene.instantiate()
				get_parent().add_child(c)
				# Losowe wyrzucenie przedmiotu – nie centralnie pod wrogiem
				var throw_angle := randf() * TAU
				var throw_dist := randf_range(1.2, 2.5)
				c.global_position = global_position + Vector3(
					cos(throw_angle) * throw_dist,
					0.0,
					sin(throw_angle) * throw_dist
				)
				if c.has_method("set_type"):
					c.set_type(randi() % 4)
	)

	# Stay dead — no auto-respawn. F2 toggle revives all enemies.


func _respawn() -> void:
	_is_dead = false
	set_physics_process(true)
	visible = true
	scale = Vector3.ONE
	var body: MeshInstance3D = get_child(0) as MeshInstance3D
	if body:
		body.scale = Vector3.ONE
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
func _find_target() -> void:
	var targets: Array[Node3D] = []
	var players := get_tree().get_nodes_in_group("player")
	targets.append_array(players)
	
	var mgr = get_tree().get_first_node_in_group("rat_manager")
	if mgr != null and "rats" in mgr:
		# Exclude rats from targeting entirely if they are hidden
		var are_visible = not mgr.has_method("are_rats_hidden") or not mgr.are_rats_hidden()
		var purple_active = mgr.get("buff_purple_timer") != null and mgr.buff_purple_timer > 0.0
		if are_visible and not purple_active:
			for rat in mgr.rats:
				if is_instance_valid(rat):
					targets.append(rat as Node3D)
				
	var best_d := INF
	var best_t: Node3D = null
	
	for t in targets:
		if is_instance_valid(t) and t.is_inside_tree():
			var curr_d = global_position.distance_squared_to(t.global_position)
			# Reduce effective distance to player so enemies heavily prioritize Bard over Rats at similar distances
			if t.is_in_group("player"):
				curr_d -= 3.0
				
			if curr_d < best_d:
				best_d = curr_d
				best_t = t
				
	_player_ref = best_t as CharacterBody3D


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
	hp_bar_bg.layers = 2
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
	hp_bar_fill.layers = 2
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
