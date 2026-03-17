extends CharacterBody3D
class_name Rat

enum State {FOLLOW, ORBIT, WAVE, TRAVEL_TO_BUILD, WAITING_FOR_FORMATION, STATIC}

@export var follow_speed: float = 6.0
@export var orbit_radius: float = 4.0
@export var orbit_speed: float = 4.0
@export var max_follow_distance: float = 22.0
@export var travel_timeout: float = 3.0

# Spring-damp parameters (used in FOLLOW state)
@export var spring_stiffness: float = 30.0
@export var damping:          float = 0.8
@export var separation_dist:  float = 0.5
@export var separation_force: float = 12.0
@export var max_speed:        float = 26.0
@export var edge_avoidance_enabled: bool = true
@export var edge_probe_distance: float = 0.45
@export var edge_max_drop: float = 0.6
@export var release_boost_speed: float = 14.0
@export var release_boost_up: float = 20.0
@export var release_boost_time: float = 0.25

var state: State = State.FOLLOW
var player: Node3D = null
var follow_offset: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var lerp_speed: float = 8.0
var extra_spin_speed: float = 0.0

# Spring-damp internal state
var _spring_velocity: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO
var _target_ready:    bool    = false
var _neighbors:       Array   = []

# Blob State (Build Mode) — kept for blob_target compat
var is_following_player: bool = true
var blob_target: Vector3 = Vector3.ZERO

# Wave state
var wave_direction: Vector3 = Vector3.ZERO
var wave_speed: float = 18.0
var wave_timer: float = 0.0
var wave_duration: float = 0.8

# Damage
var damage_per_hit: float = 10.0
var hit_range: float = 0.8
var attack_cooldown: float = 0.0

# Build state
var build_target: Vector3 = Vector3.ZERO
var _travel_timer: float = 0.0

# Carrier flag — set while this rat is assigned to carry a box;
# prevents brush operations from reassigning it
var is_carrier: bool = false

# Fall recovery
@export var fall_death_y: float = -1.0
@export var respawn_time: float = 1.0
@export var spawn_player_distance: float = 3.0
@export var respawn_near_player_when_near_spawn: bool = true

# Bridge anchoring — when true, gravity and fall-recovery are suppressed
# so rats can float in mid-air to form bridges
var is_anchored: bool = false
@export var anchor_radius: float = 2.0

var is_fallen: bool = false
var _recall_boost_timer: float = 0.0


func _ready() -> void:
	follow_offset = Vector3(
		randf_range(-1.5, 1.5),
		0.0,
		randf_range(-1.5, 1.5)
	)
	
	# Layer 1 = Floor, Layer 2 = Player, Layer 3 = Movable Objects, Layer 4 = Walls
	collision_layer = 0 # Rats don't need to be hit by anything except maybe projectiles
	collision_mask = 9 | (1 << 8)  # Floor (1) + Walls (8) + RatStructures (9)
	
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(45.0)


func _physics_process(delta: float) -> void:
	if player == null:
		return
		
	if attack_cooldown > 0.0:
		attack_cooldown = maxf(0.0, attack_cooldown - delta)

	if _recall_boost_timer > 0.0:
		_recall_boost_timer = max(0.0, _recall_boost_timer - delta)
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.001:
			var dir := to_player.normalized()
			velocity.x = dir.x * release_boost_speed
			velocity.z = dir.z * release_boost_speed
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 50
		else:
			velocity.y = 0.0
		move_and_slide()
		return

	# Fall recovery first so distance check doesn't pull rats to player mid-fall.
	if not is_anchored and global_position.y < fall_death_y:
		_start_respawn()
		return

	# Distance recovery — if a follower gets too far (e.g., stuck behind doors), snap near player.
	# Avoid snapping while falling off the world.
	if state == State.FOLLOW and not is_carrier and not is_anchored and not is_fallen and is_on_floor():
		var dist_sq: float = _flat_distance_squared(global_position, player.global_position)
		if dist_sq > max_follow_distance * max_follow_distance:
			_teleport_to_player()
			return

	# Gravity and fall-recovery are skipped for anchored rats (near build target)
	# so they can float as bridge pieces
	if is_anchored or state == State.TRAVEL_TO_BUILD or state == State.WAITING_FOR_FORMATION:
		velocity.y = 0.0
		if state == State.TRAVEL_TO_BUILD:
			global_position.y = build_target.y
	else:
		# Gravity — applied every frame, preserved across all states
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 50
		else:
			velocity.y = 0.0

		# Fall recovery is handled above before distance checks.

	match state:
		State.FOLLOW:
			_process_follow_spring(delta)
			_check_damage()
		State.ORBIT:
			_process_orbit(delta)
			_check_damage()
		State.WAVE:
			_process_wave(delta)
			_check_damage()
		State.TRAVEL_TO_BUILD:
			_process_travel_to_build(delta)
		State.WAITING_FOR_FORMATION:
			return
		State.STATIC:
			return

	if extra_spin_speed != 0.0:
		rotation.y += extra_spin_speed * delta


func _process_follow_spring(delta: float) -> void:
	if not _target_ready:
		return

	# Spring toward target — flatten Y so it doesn't bounce vertically
	var to_target := _target_position - global_position
	to_target.y *= 0.2
	_spring_velocity += to_target * spring_stiffness * delta

	# Separation from neighbors
	for neighbor in _neighbors:
		if not is_instance_valid(neighbor):
			continue
		var nb := neighbor as Node3D
		if nb == null:
			continue
		var diff: Vector3 = global_position - nb.global_position
		diff.y = 0.0
		var dist: float = diff.length()
		if dist < separation_dist and dist > 0.001:
			_spring_velocity += diff.normalized() * (separation_dist - dist) * separation_force * delta

	# Framerate-independent damping
	_spring_velocity *= pow(damping, delta * 60.0)

	# Clamp horizontal speed
	var hvel := Vector2(_spring_velocity.x, _spring_velocity.z)
	if hvel.length() > max_speed:
		hvel = hvel.normalized() * max_speed
		_spring_velocity.x = hvel.x
		_spring_velocity.z = hvel.y

	# Preserve gravity-driven vertical velocity, add spring horizontal
	velocity.x = _spring_velocity.x
	velocity.z = _spring_velocity.z
	if _should_block_edge(Vector2(velocity.x, velocity.z)):
		velocity.x = 0.0
		velocity.z = 0.0
		_spring_velocity.x = 0.0
		_spring_velocity.z = 0.0
	move_and_slide()
	# Sync spring velocity with collision response (horizontal only)
	_spring_velocity.x = velocity.x
	_spring_velocity.z = velocity.z

	# Face direction of travel (skip if spinning in combat)
	if extra_spin_speed == 0.0:
		var move_dir := Vector3(velocity.x, 0.0, velocity.z)
		if move_dir.length() > 0.4:
			rotation.y = lerp_angle(rotation.y, atan2(move_dir.x, move_dir.z), 14.0 * delta)


func set_target(pos: Vector3) -> void:
	_target_position = pos
	_target_ready    = true


func set_neighbors(n: Array) -> void:
	_neighbors = n


func _process_orbit(delta: float) -> void:
	orbit_angle += orbit_speed * delta

	var target_pos := player.global_position + Vector3(
		cos(orbit_angle) * orbit_radius,
		0.0,
		sin(orbit_angle) * orbit_radius
	)

	var current := global_position
	var new_pos := current.lerp(target_pos, lerp_speed * delta)
	var lerp_vel: Vector3 = (new_pos - current) / max(delta, 0.001)
	velocity.x = lerp_vel.x
	velocity.z = lerp_vel.z
	if _should_block_edge(Vector2(velocity.x, velocity.z)):
		velocity.x = 0.0
		velocity.z = 0.0

	var forward_dir := Vector3(-sin(orbit_angle), 0.0, cos(orbit_angle))
	var target_angle := atan2(forward_dir.x, forward_dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)

	move_and_slide()


func set_orbit(angle: float, radius: float = 4.0) -> void:
	orbit_angle = angle
	orbit_radius = radius
	state = State.ORBIT


func set_follow() -> void:
	state = State.FOLLOW


func set_wave(direction: Vector3, delay: float) -> void:
	wave_direction = direction.normalized()
	wave_timer = - delay
	state = State.WAVE


func _process_wave(delta: float) -> void:
	wave_timer += delta
	if wave_timer < 0.0:
		return # still in delay

	if wave_timer >= wave_duration:
		set_follow()
		return

	velocity.x = wave_direction.x * wave_speed
	velocity.z = wave_direction.z * wave_speed
	if _should_block_edge(Vector2(velocity.x, velocity.z)):
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()

	var target_angle := atan2(wave_direction.x, wave_direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)


func _check_damage() -> void:
	if attack_cooldown > 0.0:
		return
		
	var enemies := get_tree().get_nodes_in_group("enemies")
	enemies += (get_tree().get_nodes_in_group("bosses"))
	#print(global_position.distance_to(get_tree().get_nodes_in_group("bosses")[0].global_position))
	
	for enemy in enemies:
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < hit_range:
			enemy.take_damage(damage_per_hit, get_instance_id(), global_position)
			attack_cooldown = 1.0
			break


func _process_travel_to_build(delta: float) -> void:
	# Use XZ-only distance so gravity doesn't prevent arrival
	var flat_self := Vector2(global_position.x, global_position.z)
	var flat_target := Vector2(build_target.x, build_target.z)
	var dist := flat_self.distance_to(flat_target)
	_travel_timer += delta
	if travel_timeout > 0.0 and _travel_timer >= travel_timeout:
		state = State.WAITING_FOR_FORMATION
		global_position = build_target
		velocity = Vector3.ZERO
		return

	if dist <= anchor_radius:
		is_anchored = true

	if dist > 0.1:
		var dir := Vector2(flat_target - flat_self).normalized()
		velocity.x = dir.x * follow_speed * 2.0
		velocity.z = dir.y * follow_speed * 2.0
		var target_angle := atan2(dir.x, dir.y)
		rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)
		move_and_slide()
	else:
		state = State.WAITING_FOR_FORMATION
		global_position = build_target
		velocity = Vector3.ZERO


func activate_physics() -> void:
	if state == State.WAITING_FOR_FORMATION:
		state = State.STATIC
		set_collision_layer_value(1, true)


func build_at(pos: Vector3) -> void:
	# Carrier rats must not be redirected to brush destinations
	if is_carrier:
		return
	if state == State.FOLLOW:
		state = State.TRAVEL_TO_BUILD
		build_target = pos
		_travel_timer = 0.0


func release_rat(with_boost: bool = false) -> void:
	if state == State.STATIC or state == State.TRAVEL_TO_BUILD or state == State.WAITING_FOR_FORMATION:
		state = State.FOLLOW
		is_anchored = false
		is_carrier = false
		_spring_velocity = Vector3.ZERO
		if with_boost and player != null:
			var to_player := player.global_position - global_position
			to_player.y = 0.0
			if to_player.length() > 0.001:
				var dir := to_player.normalized()
				_spring_velocity.x = dir.x * release_boost_speed
				_spring_velocity.z = dir.z * release_boost_speed
				velocity.x = _spring_velocity.x
				velocity.z = _spring_velocity.z
			velocity.y = release_boost_up
			_recall_boost_timer = release_boost_time
		else:
			velocity.y = 5.0
		_travel_timer = 0.0
		# Lose solidity
		set_collision_layer_value(1, false)
		show_visuals()


func _teleport_to_player() -> void:
	_reset_to_follow()
	global_position = player.global_position + Vector3(
		randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)
	)


func _start_respawn() -> void:
	if is_fallen:
		return
	is_fallen = true
	_reset_to_follow()
	hide_visuals()
	set_physics_process(false)
	await get_tree().create_timer(respawn_time).timeout
	_respawn_at_spawn_point()


func _respawn_at_spawn_point() -> void:
	var spawn := _get_nearest_spawn(global_position)
	if spawn == null:
		_teleport_to_player()
		_finish_respawn()
		return
	if player == null:
		global_position = spawn.global_position + Vector3(
			randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6)
		)
		_finish_respawn()
		return
	global_position = spawn.global_position + Vector3(
		randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6)
	)
	if not respawn_near_player_when_near_spawn:
		_finish_respawn()
		return
	_wait_for_player_near_spawn(spawn)


func _wait_for_player_near_spawn(spawn: Node3D) -> void:
	while player != null and spawn != null:
		var player_dist := _flat_distance(player.global_position, spawn.global_position)
		if player_dist <= spawn_player_distance:
			global_position = player.global_position + Vector3(
				randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)
			)
			break
		await get_tree().process_frame
	_finish_respawn()


func force_respawn_near_player() -> void:
	if player == null:
		return
	_reset_to_follow()
	global_position = player.global_position + Vector3(
		randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)
	)
	_finish_respawn()


func force_respawn_at_position(pos: Vector3) -> void:
	_reset_to_follow()
	global_position = pos
	_finish_respawn()


func _get_nearest_spawn(pos: Vector3) -> Node3D:
	var spawns := get_tree().get_nodes_in_group("rat_spawn")
	var best: Node3D = null
	var best_dist := INF
	for s in spawns:
		var n := s as Node3D
		if n == null:
			continue
		var d := _flat_distance_squared(n.global_position, pos)
		if d < best_dist:
			best_dist = d
			best = n
	return best


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return sqrt(_flat_distance_squared(a, b))


func _flat_distance_squared(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


func _finish_respawn() -> void:
	is_fallen = false
	show_visuals()
	set_physics_process(true)



func _reset_to_follow() -> void:
	is_anchored = false
	state = State.FOLLOW
	is_following_player = true
	_spring_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	set_collision_layer_value(1, false)
	show_visuals()


func hide_visuals() -> void:
	$Body.hide()
	$Tail.hide()
	$Head.hide()


func show_visuals() -> void:
	$Body.show()
	$Tail.show()
	$Head.show()


func set_wall_collision(enabled: bool) -> void:
	set_collision_mask_value(4, enabled)


func _should_block_edge(hvel: Vector2) -> bool:
	if not edge_avoidance_enabled:
		return false
	if _recall_boost_timer > 0.0:
		return false
	if is_anchored:
		return false
	if state == State.TRAVEL_TO_BUILD or state == State.WAITING_FOR_FORMATION or state == State.STATIC:
		return false
	if hvel.length() < 0.01:
		return false

	var forward := Vector3(hvel.x, 0.0, hvel.y).normalized()
	var probe_pos := global_position + forward * edge_probe_distance
	return not _has_floor_near(probe_pos, edge_max_drop)


func _has_floor_near(pos: Vector3, max_drop: float) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var ss := world.direct_space_state
	var origin := pos + Vector3.UP * 0.3
	var end := pos + Vector3.DOWN * (max_drop + 0.8)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 1 | (1 << 8) # Floor + RatStructures
	query.exclude = [self]
	var hit := ss.intersect_ray(query)
	if not hit:
		return false
	return hit.position.y >= global_position.y - max_drop
