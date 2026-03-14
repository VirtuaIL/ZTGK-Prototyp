extends CharacterBody3D

enum State {FOLLOW, ORBIT, WAVE, TRAVEL_TO_BUILD, WAITING_FOR_FORMATION, STATIC}

@export var follow_speed: float = 6.0
@export var orbit_radius: float = 4.0
@export var orbit_speed: float = 4.0

# Spring-damp parameters (used in FOLLOW state)
@export var spring_stiffness: float = 12.0
@export var damping:          float = 0.86
@export var separation_dist:  float = 0.5
@export var separation_force: float = 12.0
@export var max_speed:        float = 20.0

var state: State = State.FOLLOW
var player: Node3D = null
var follow_offset: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var lerp_speed: float = 8.0

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

# Build state
var build_target: Vector3 = Vector3.ZERO

# Carrier flag — set while this rat is assigned to carry a box;
# prevents brush operations from reassigning it
var is_carrier: bool = false

# Fall recovery
@export var fall_death_y: float = -1.0

# Bridge anchoring — when true, gravity and fall-recovery are suppressed
# so rats can float in mid-air to form bridges
var is_anchored: bool = false
@export var anchor_radius: float = 2.0


func _ready() -> void:
	follow_offset = Vector3(
		randf_range(-1.5, 1.5),
		0.0,
		randf_range(-1.5, 1.5)
	)
	
	# Layer 1 = Floor, Layer 2 = Player, Layer 3 = Movable Objects, Layer 4 = Walls
	collision_layer = 0 # Rats don't need to be hit by anything except maybe projectiles
	collision_mask = 9  # Collide with Floor (1) and Walls (8) by default


func _physics_process(delta: float) -> void:
	if player == null:
		return

	# Gravity and fall-recovery are skipped for anchored rats (near build target)
	# so they can float as bridge pieces
	if is_anchored:
		velocity.y = 0.0
	else:
		# Gravity — applied every frame, preserved across all states
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 50
		else:
			velocity.y = 0.0

		# Fall recovery — cancel orders and return to player if fallen off the world.
		if global_position.y < fall_death_y:
			is_anchored = false
			state = State.FOLLOW
			is_following_player = true
			_spring_velocity = Vector3.ZERO
			velocity = Vector3.ZERO
			set_collision_layer_value(1, false)
			show_visuals()
			global_position = player.global_position + Vector3(
				randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)
			)
			return

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
	move_and_slide()
	# Sync spring velocity with collision response (horizontal only)
	_spring_velocity.x = velocity.x
	_spring_velocity.z = velocity.z

	# Face direction of travel
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
	move_and_slide()

	var target_angle := atan2(wave_direction.x, wave_direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)


func _check_damage() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < hit_range:
			enemy.take_damage(damage_per_hit, get_instance_id())


func _process_travel_to_build(delta: float) -> void:
	# Use XZ-only distance so gravity doesn't prevent arrival
	var flat_self := Vector2(global_position.x, global_position.z)
	var flat_target := Vector2(build_target.x, build_target.z)
	var dist := flat_self.distance_to(flat_target)

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


func release_rat() -> void:
	if state == State.STATIC or state == State.TRAVEL_TO_BUILD or state == State.WAITING_FOR_FORMATION:
		state = State.FOLLOW
		is_anchored = false
		is_carrier = false
		_spring_velocity = Vector3.ZERO
		velocity.y = 5.0
		# Lose solidity
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
