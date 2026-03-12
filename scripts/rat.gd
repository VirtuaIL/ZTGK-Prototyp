# rat.gd — rozszerzony o direct_attack i parametr speed_mult dla wave
extends CharacterBody3D

enum State {FOLLOW, ORBIT, WAVE, DIRECT_ATTACK, TRAVEL_TO_BUILD, STATIC}

@export var follow_speed: float = 6.0
@export var orbit_radius: float = 4.0
@export var orbit_speed: float = 4.0

var state: State = State.FOLLOW
var player: Node3D = null
var follow_offset: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var lerp_speed: float = 8.0

# Wave
var wave_direction: Vector3 = Vector3.ZERO
var wave_speed: float = 18.0
var wave_speed_mult: float = 1.0
var wave_timer: float = 0.0
var wave_duration: float = 0.8

# Direct attack
var direct_target: Vector3 = Vector3.ZERO
var direct_delay: float = 0.0
var direct_timer: float = 0.0

# Damage
var damage_per_hit: float = 10.0
var hit_range: float = 0.8

# Build
var build_target: Vector3 = Vector3.ZERO

var _bridge_body: StaticBody3D = null

@export var gravity: float = 18.0
var _airborne: bool = false

func _ready() -> void:
	follow_offset = Vector3(
		randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)
	)

func _physics_process(delta: float) -> void:
	if player == null:
		return

	if _bridge_body != null and is_instance_valid(_bridge_body) and state == State.STATIC:
		_bridge_body.global_position = global_position + Vector3(0, 0.2, 0)

	match state:
		State.FOLLOW:          _process_follow(delta)
		State.ORBIT:           _process_orbit(delta);  _check_damage()
		State.WAVE:            _process_wave(delta);   _check_damage()
		State.DIRECT_ATTACK:   _process_direct(delta); _check_damage()
		State.TRAVEL_TO_BUILD: _process_travel_to_build(delta)
		State.STATIC:          return

func _process_follow(delta: float) -> void:
	if global_position.y < player.global_position.y - 8.0:
		global_position = player.global_position + follow_offset
		velocity = Vector3.ZERO
		return
	# Grawitacja
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0

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
		velocity.x = move_toward(velocity.x, 0.0, follow_speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0.0, follow_speed * delta * 5.0)
	move_and_slide()

# Podobnie w _process_travel_to_build:
func _process_travel_to_build(delta: float) -> void:
	var dist := global_position.distance_to(build_target)
	if dist > 0.1:
		var dir := global_position.direction_to(build_target)
		velocity = dir * follow_speed * 3.0
		var y_diff: float = build_target.y - global_position.y
		velocity.y = y_diff * 10.0
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), lerp_speed * delta)
		move_and_slide()
	else:
		print("[rat] reached build target, going STATIC")  # DEBUG
		state = State.STATIC
		global_position = build_target
		velocity = Vector3.ZERO
		_spawn_bridge_collision()

func _process_orbit(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	var target_pos := player.global_position + Vector3(
		cos(orbit_angle) * orbit_radius, 0.0, sin(orbit_angle) * orbit_radius
	)
	var current := global_position
	var new_pos := current.lerp(target_pos, lerp_speed * delta)
	velocity = (new_pos - current) / max(delta, 0.001)
	var forward_dir := Vector3(-sin(orbit_angle), 0.0, cos(orbit_angle))
	rotation.y = lerp_angle(rotation.y, atan2(forward_dir.x, forward_dir.z), lerp_speed * delta)
	move_and_slide()

func set_orbit(angle: float, radius: float = 4.0) -> void:
	orbit_angle = angle
	orbit_radius = radius
	state = State.ORBIT

func set_follow() -> void:
	state = State.FOLLOW

func set_wave(direction: Vector3, delay: float, speed_mult: float = 1.0) -> void:
	wave_direction = direction.normalized()
	wave_timer = -delay
	wave_speed_mult = speed_mult
	state = State.WAVE

func _process_wave(delta: float) -> void:
	wave_timer += delta
	if wave_timer < 0.0:
		return
	if wave_timer >= wave_duration:
		set_follow()
		return
	velocity = wave_direction * wave_speed * wave_speed_mult
	move_and_slide()
	rotation.y = lerp_angle(rotation.y, atan2(wave_direction.x, wave_direction.z), lerp_speed * delta)

# ─── Direct attack ─────────────────────────────
func set_direct_attack(target: Vector3, delay: float) -> void:
	direct_target = target
	direct_delay = delay
	direct_timer = 0.0
	state = State.DIRECT_ATTACK

func _process_direct(delta: float) -> void:
	direct_timer += delta
	if direct_timer < direct_delay:
		return  # czekaj na swoją kolejkę
	var dir := global_position.direction_to(direct_target)
	var dist := global_position.distance_to(direct_target)
	if dist > 0.3:
		velocity = dir * follow_speed * 3.0
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), lerp_speed * delta)
		move_and_slide()
	else:
		# Dotarł do celu — uderz i wróć
		_check_damage()
		set_follow()

func _check_damage() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if global_position.distance_to(enemy.global_position) < hit_range:
			enemy.take_damage(damage_per_hit, get_instance_id())

func build_at(pos: Vector3) -> void:
	if state == State.FOLLOW:
		state = State.TRAVEL_TO_BUILD
		build_target = pos

func _spawn_bridge_collision() -> void:
	if _bridge_body != null:
		return
	_bridge_body = StaticBody3D.new()
	_bridge_body.name = "BridgeTile"
	_bridge_body.collision_layer = 8
	_bridge_body.collision_mask  = 0

	var shape := CollisionShape3D.new()
	var box   := BoxShape3D.new()
	# Szerszy i niższy box — gracz wchodzi na niego łagodniej
	box.size  = Vector3(0.6, 0.15, 0.6)   # płaski, szeroki
	shape.shape = box
	_bridge_body.add_child(shape)
	get_tree().current_scene.add_child(_bridge_body)
	# Ustaw tak żeby górna krawędź była NA poziomie szczura (nie nad nim)
	_bridge_body.global_position = global_position + Vector3(0, 0.075, 0)

func _remove_bridge_collision() -> void:
	if _bridge_body != null and is_instance_valid(_bridge_body):
		_bridge_body.queue_free()
	_bridge_body = null

func release_rat() -> void:
	_remove_bridge_collision()
	if state == State.STATIC or state == State.TRAVEL_TO_BUILD:
		state = State.FOLLOW
		# Lekki skok w górę — grawitacja w _process_follow zrobi resztę
		# Jeśli szczur jest nad przepaścią — spadnie naturalnie
		velocity = Vector3(
			randf_range(-0.8, 0.8),
			randf_range(1.5, 3.5),
			randf_range(-0.8, 0.8)
		)
