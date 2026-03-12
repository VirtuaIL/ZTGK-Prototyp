# puzzle_object.gd
extends RigidBody3D

signal grabbed()
signal released()

var is_highlighted: bool = false
var _original_mat: StandardMaterial3D = null
var _mesh: MeshInstance3D = null

var is_carried: bool = false
var carry_target: Node3D = null
var _carry_height: float = 0.9

# Ociężałość — obiekt dąży do kursora ale powoli i z oporem
var carry_max_speed: float = 4.0      # max prędkość przenoszenia
var carry_acceleration: float = 3.0   # jak szybko przyspiesza (niskie = ociężałe)
var carry_deadzone: float = 0.3       # strefa martwa — nie rusza się jeśli kursor blisko

func _ready() -> void:
	add_to_group("puzzle_objects")
	for child in get_children():
		if child is MeshInstance3D:
			_mesh = child as MeshInstance3D
			break
	if _mesh != null and _mesh.mesh != null:
		_original_mat = _mesh.mesh.surface_get_material(0) as StandardMaterial3D

func _physics_process(delta: float) -> void:
	if not is_carried:
		return

	# Zablokuj rotację — obiekt nie przewraca się
	angular_velocity = Vector3.ZERO
	rotation = Vector3(0.0, rotation.y, 0.0)   # tylko obrót Y zachowany

	var mouse_ground := _get_mouse_ground_pos()
	var target_pos   := Vector3(mouse_ground.x, _carry_height, mouse_ground.z)
	var to_target    := target_pos - global_position

	# Strefa martwa — nie drgaj gdy kursor blisko środka
	var horiz_dist: float = Vector2(to_target.x, to_target.z).length()
	var vert_dist: float  = abs(to_target.y)

	# Prędkość pozioma — ociężała, w kierunku kursora
	var desired_vel := Vector3.ZERO
	if horiz_dist > carry_deadzone:
		var horiz_dir := Vector3(to_target.x, 0.0, to_target.z).normalized()
		# Prędkość rośnie z odległością, ale ma maksimum
		var speed := minf(horiz_dist * carry_acceleration, carry_max_speed)
		desired_vel = horiz_dir * speed

	# Prędkość pionowa — utrzymuj wysokość
	if vert_dist > 0.05:
		desired_vel.y = to_target.y * carry_acceleration * 2.0
	else:
		desired_vel.y = 0.0

	# Płynne przejście do pożądanej prędkości (nie skacze)
	linear_velocity = linear_velocity.lerp(desired_vel, delta * 6.0)

func _get_mouse_ground_pos() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return global_position
	var mouse_pos  := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir    := camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.001:
		return global_position
	var t: float = (_carry_height - ray_origin.y) / ray_dir.y
	return ray_origin + ray_dir * t

# ── Moce ─────────────────────────────────────────────────

func apply_push(from_pos: Vector3, force: float = 12.0) -> void:
	freeze = false
	var dir := (global_position - from_pos)
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3(1, 0, 0)
	linear_velocity = Vector3.ZERO
	apply_central_impulse(dir.normalized() * force)
	_flash_color(Color(0.3, 0.75, 1.0))

func apply_pull(to_pos: Vector3, force: float = 14.0) -> void:
	freeze = false
	var dir := (to_pos - global_position)
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	linear_velocity = Vector3.ZERO
	apply_central_impulse(dir.normalized() * force)
	_flash_color(Color(1.0, 0.65, 0.2))

func start_carry(target: Node3D) -> void:
	freeze = false
	is_carried = true
	carry_target = target
	gravity_scale = 0.0
	linear_damp  = 5.0
	angular_damp = 99.0   # tłumi wszelką rotację
	lock_rotation = true   # blokada rotacji w RigidBody3D
	grabbed.emit()
	_flash_color(Color(0.55, 0.35, 1.0))

func stop_carry() -> void:
	if not is_carried:
		return
	is_carried    = false
	carry_target  = null
	gravity_scale = 1.0
	linear_damp   = 0.5
	angular_damp  = 0.1
	lock_rotation = false
	linear_velocity  = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	released.emit()

# ── Podświetlenie ─────────────────────────────────────────

func set_highlight(active: bool) -> void:
	is_highlighted = active
	if _mesh == null:
		return
	if active:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.95, 0.5)
		mat.emission_enabled = true
		mat.emission         = Color(0.5, 0.45, 0.1)
		mat.emission_energy_multiplier = 2.0
		_mesh.material_override = mat
	else:
		_mesh.material_override = null

func _flash_color(color: Color) -> void:
	if _mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission         = color
	mat.emission_energy_multiplier = 2.5
	_mesh.material_override = mat
	var tween := create_tween()
	tween.tween_interval(0.25)
	tween.tween_callback(func():
		if is_highlighted:
			set_highlight(true)
		else:
			_mesh.material_override = null
	)
