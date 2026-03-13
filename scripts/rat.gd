extends CharacterBody3D

signal fallen_into_abyss(rat: CharacterBody3D)

@export var spring_stiffness: float = 12.0
@export var damping:          float = 0.86
@export var separation_dist:  float = 0.5
@export var separation_force: float = 12.0
@export var max_speed:        float = 20.0

@export var damage_per_hit: float = 8.0
@export var hit_range:      float = 0.6

var player: Node3D = null

var _target_position: Vector3 = Vector3.ZERO
var _spring_velocity: Vector3 = Vector3.ZERO
var _target_ready:    bool    = false  # don't spring until first target is set
var _neighbors:       Array   = []


func _physics_process(delta: float) -> void:
	if player == null or not _target_ready:
		return

	# Abyss
	if global_position.y < -10.0:
		fallen_into_abyss.emit(self)
		return

	# Gravity
	if not is_on_floor():
		_spring_velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 0.5

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

	velocity = _spring_velocity
	move_and_slide()
	_spring_velocity = velocity  # sync after collision response

	# Face direction of travel
	var move_dir := Vector3(velocity.x, 0.0, velocity.z)
	if move_dir.length() > 0.4:
		rotation.y = lerp_angle(rotation.y, atan2(move_dir.x, move_dir.z), 14.0 * delta)

	_check_damage()


func set_target(pos: Vector3) -> void:
	_target_position = pos
	_target_ready    = true


func set_neighbors(n: Array) -> void:
	_neighbors = n


func _check_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) < hit_range:
			enemy.take_damage(damage_per_hit, get_instance_id())


func respawn_at(pos: Vector3) -> void:
	global_position  = pos
	_spring_velocity = Vector3.ZERO
	_target_position = pos
	_target_ready    = true
