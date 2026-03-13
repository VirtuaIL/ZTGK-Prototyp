extends CharacterBody3D

enum State {FOLLOW, ORBIT, WAVE, TRAVEL_TO_BUILD, WAITING_FOR_FORMATION, STATIC}

@export var follow_speed: float = 6.0
@export var orbit_radius: float = 4.0
@export var orbit_speed: float = 4.0

var state: State = State.FOLLOW
var player: Node3D = null
var follow_offset: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var lerp_speed: float = 8.0

# Blob State (Build Mode)
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
	
	# Default: only collide with environment (Layer 1 is Player, normally Layer 2 is Environment)
	# Assuming Environment is Layer 1 here for simplicity, or we just disable Layer 1 so player doesn't collide
	set_collision_layer_value(1, false)


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
		# Bypasses release_rat() which has a state guard and silently does nothing
		# for FOLLOW/WAVE/ORBIT rats.
		if global_position.y < fall_death_y:
			is_anchored = false
			state = State.FOLLOW
			is_following_player = true
			velocity = Vector3.ZERO
			set_collision_layer_value(1, false)
			show_visuals()
			# Teleport back near the player so the rat can resume following
			global_position = player.global_position + Vector3(
				randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)
			)
			return

	match state:
		State.FOLLOW:
			_process_follow(delta)
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


func _process_follow(delta: float) -> void:
	var target: Vector3
	if is_following_player:
		target = player.global_position + follow_offset
	else:
		target = blob_target + follow_offset

	var direction := (target - global_position)
	direction.y = 0.0

	if direction.length() > 0.3:
		var move_dir := direction.normalized()
		velocity.x = move_dir.x * follow_speed
		velocity.z = move_dir.z * follow_speed
		var target_angle := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, follow_speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0.0, follow_speed * delta * 5.0)

	move_and_slide()


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

	# Also check proximity to own build_target for anchoring
	# (additional positions are checked by rat_manager against the full brush)

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
