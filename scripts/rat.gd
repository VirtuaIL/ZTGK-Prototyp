extends CharacterBody3D

enum State {FOLLOW, ORBIT, WAVE}

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


func _ready() -> void:
	follow_offset = Vector3(
		randf_range(-1.5, 1.5),
		0.0,
		randf_range(-1.5, 1.5)
	)

	# Body mesh (small box = rat body)
	var body_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.15, 0.4)
	body_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.18)
	body_mesh.material_override = mat
	body_mesh.position.y = 0.075
	add_child(body_mesh)

	# Tail (thin cylinder)
	var tail_mesh := MeshInstance3D.new()
	var tail := CylinderMesh.new()
	tail.top_radius = 0.015
	tail.bottom_radius = 0.025
	tail.height = 0.3
	tail_mesh.mesh = tail
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.55, 0.38, 0.25)
	tail_mesh.material_override = tail_mat
	tail_mesh.position = Vector3(0, 0.06, -0.3)
	tail_mesh.rotation_degrees = Vector3(70, 0, 0)
	add_child(tail_mesh)

	# Head (small sphere)
	var head_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.14
	head_mesh.mesh = sphere
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.5, 0.35, 0.2)
	head_mesh.material_override = head_mat
	head_mesh.position = Vector3(0, 0.1, 0.2)
	add_child(head_mesh)


func _physics_process(delta: float) -> void:
	if player == null:
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


func _process_follow(delta: float) -> void:
	var target := player.global_position + follow_offset
	var direction := (target - global_position)
	direction.y = 0.0

	if direction.length() > 0.3:
		var move_dir := direction.normalized()
		velocity = move_dir * follow_speed
		var target_angle := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, follow_speed * delta * 5.0)

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
