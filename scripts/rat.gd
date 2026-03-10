extends CharacterBody3D

enum State {FOLLOW, ORBIT, WAVE, TRAVEL_TO_BUILD, STATIC, RUN_TO_CONSUME}
signal fallen_into_abyss(rat: CharacterBody3D)

@export var follow_speed: float = 6.0
@export var orbit_radius: float = 4.0
@export var orbit_speed: float = 4.0

var state: State = State.FOLLOW
var player: Node3D = null
var follow_offset: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var lerp_speed: float = 8.0

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
var build_rot_y: float = 0.0


func _ready() -> void:
	follow_offset = Vector3(
		randf_range(-1.5, 1.5),
		0.0,
		randf_range(-1.5, 1.5)
	)


func _physics_process(delta: float) -> void:
	if player == null:
		return

	# Apply gravity - only for moving/following rats
	var needs_gravity := (state != State.STATIC and state != State.TRAVEL_TO_BUILD and state != State.RUN_TO_CONSUME)
	if needs_gravity and not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	elif state == State.STATIC or state == State.TRAVEL_TO_BUILD or state == State.RUN_TO_CONSUME:
		velocity.y = 0 # Maintain height for bridges/consumption run
	
	# Abyss detection
	if global_position.y < -10.0:
		fallen_into_abyss.emit(self)
		return

	match state:
		State.STATIC:
			collision_layer = 4 # Layer 3: Solid for players
			return
		_:
			collision_layer = 0 # No layer: Players walk through

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
		State.RUN_TO_CONSUME:
			_process_consume(delta)


func _process_consume(delta: float) -> void:
	var move_step := follow_speed * 3.0 * delta
	var dist := global_position.distance_to(build_target)

	if dist > move_step:
		global_position = global_position.move_toward(build_target, move_step)
		# Face target
		var dir := global_position.direction_to(build_target)
		if dir.length() > 0.1:
			var target_angle := atan2(dir.x, dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)
	else:
		fallen_into_abyss.emit(self) # Re-use abyss signal to mark rat as "dead/consumed"


func _process_follow(delta: float) -> void:
	var target := player.global_position + follow_offset
	var direction := (target - global_position)
	direction.y = 0.0

	if direction.length() > 0.3:
		var move_dir := direction.normalized()
		velocity.x = move_dir.x * follow_speed
		velocity.z = move_dir.z * follow_speed
		var target_angle := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, follow_speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0, follow_speed * delta * 5.0)

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
	velocity = (new_pos - current) / max(delta, 0.001)

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

	velocity = wave_direction * wave_speed
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
	var move_step := follow_speed * 3.0 * delta
	var dist := global_position.distance_to(build_target)

	if dist > move_step:
		global_position = global_position.move_toward(build_target, move_step)
		rotation.y = lerp_angle(rotation.y, build_rot_y, lerp_speed * delta)
	else:
		state = State.STATIC
		global_position = build_target
		rotation.y = build_rot_y
		velocity = Vector3.ZERO


func build_at(pos: Vector3, rot_y: float = 0.0) -> void:
	if state == State.FOLLOW:
		state = State.TRAVEL_TO_BUILD
		build_target = pos
		build_rot_y = rot_y

func run_to_consume(pos: Vector3) -> void:
	if state == State.FOLLOW:
		state = State.RUN_TO_CONSUME
		build_target = pos

func release_rat() -> void:
	if state == State.STATIC or state == State.TRAVEL_TO_BUILD:
		state = State.FOLLOW
		velocity.y = 5.0


func respawn_at(pos: Vector3) -> void:
	state = State.FOLLOW
	global_position = pos
	velocity = Vector3.ZERO
