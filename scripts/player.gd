# player.gd
extends CharacterBody3D

signal mode_changed(mode: String)
signal fell_into_void()

enum Mode { COMBAT, PUZZLE }

@export var speed: float = 7.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 20.0
@export var fall_threshold: float = -5.0   # Y poniżej którego = przepaść

var current_mode: Mode = Mode.COMBAT
var is_playing_instrument: bool = false
var _spawn_point: Vector3 = Vector3.ZERO
var _is_respawning: bool = false

func _ready() -> void:
	_spawn_point = global_position
	# Pozwól graczowi wchodzić na małe stopnie/krawędzie
	floor_max_angle     = deg_to_rad(75.0)   # domyślnie 45°, zwiększ
	floor_snap_length   = 0.3                # snap do podłogi przy schodzeniu
	floor_stop_on_slope = false
	max_slides          = 6

func _physics_process(delta: float) -> void:
	if _is_respawning:
		return
	if global_position.y < fall_threshold:
		_is_respawning = true
		fell_into_void.emit()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0

	if is_playing_instrument:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var input_dir := Vector3.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.z = Input.get_axis("move_forward", "move_back")
	input_dir = input_dir.rotated(Vector3.UP, deg_to_rad(45.0))

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		velocity.x = input_dir.x * speed
		velocity.z = input_dir.z * speed
		var target_angle := atan2(input_dir.x, input_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0.0, speed * delta * 5.0)

	move_and_slide()

	# Step climbing — wejście na małe krawędzie (kładki szczurów)
	if is_on_floor() and get_slide_collision_count() > 0:
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			var normal := col.get_normal()
			# Jeśli kolizja jest boczna (normalVector prawie poziomy)
			if abs(normal.y) < 0.3:
				# Sprawdź czy to niska przeszkoda — rzuć ray w dół przed graczem
				var space := get_world_3d().direct_space_state
				var move_dir := Vector3(velocity.x, 0, velocity.z).normalized()
				if move_dir.length() < 0.1:
					continue
				var ray_start := global_position + move_dir * 0.35 + Vector3(0, 0.5, 0)
				var ray_end   := ray_start + Vector3(0, -0.6, 0)
				var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
				query.exclude = [self]
				query.collision_mask = 9
				var result := space.intersect_ray(query)
				if result:
					var step_height: float = result.position.y - global_position.y
					# Jeśli stopień jest niski (do 0.45 jednostki) — wskocz na niego
					if step_height > 0.02 and step_height < 0.45:
						velocity.y = 5.0   # małe popchnięcie w górę

func respawn() -> void:
	global_position = _spawn_point
	velocity        = Vector3.ZERO
	_is_respawning  = false

func set_spawn_point(pos: Vector3) -> void:
	_spawn_point = pos

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_TAB:
			_toggle_mode()
			get_viewport().set_input_as_handled()

func _toggle_mode() -> void:
	if current_mode == Mode.COMBAT:
		current_mode = Mode.PUZZLE
		mode_changed.emit("puzzle")
	else:
		current_mode = Mode.COMBAT
		mode_changed.emit("combat")

func set_playing_instrument(active: bool) -> void:
	is_playing_instrument = active

func is_puzzle_mode() -> bool:
	return current_mode == Mode.PUZZLE

func is_combat_mode() -> bool:
	return current_mode == Mode.COMBAT
