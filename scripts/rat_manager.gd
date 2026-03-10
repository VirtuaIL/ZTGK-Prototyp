extends Node3D

signal orbit_started()
signal orbit_ended()
signal wave_started()
signal wave_ended()

var rats: Array[CharacterBody3D] = []
var orbit_active: bool = false
var orbit_duration: float = 10.0
var orbit_timer: float = 0.0

var wave_active: bool = false
var wave_duration: float = 1.0
var wave_timer: float = 0.0
var wave_pending: bool = false

# Drawing
var built_positions: Dictionary = {}
var mouse_is_down_right: bool = false
var last_draw_pos: Vector3 = Vector3(-1000, -1000, -1000)
var is_drawing_line: bool = false
var current_build_y: float = -1000.0
var _ctrl_was_pressed: bool = false
var is_build_mode: bool = false
var brush_node: MeshInstance3D


func _ready() -> void:
	_setup_brush()


func _setup_brush() -> void:
	brush_node = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.45
	ring.outer_radius = 0.5
	brush_node.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brush_node.material_override = mat
	add_child(brush_node)
	brush_node.visible = false


func _process(delta: float) -> void:
	if orbit_active:
		orbit_timer -= delta
		if orbit_timer <= 0.0:
			deactivate_orbit()

	if wave_active:
		wave_timer -= delta
		if wave_timer <= 0.0:
			wave_active = false
			wave_ended.emit()

	# Detect Ctrl press to recall all placed rats
	var ctrl_pressed := Input.is_key_pressed(KEY_CTRL)
	if ctrl_pressed and not _ctrl_was_pressed:
		recall_all_rats()
	_ctrl_was_pressed = ctrl_pressed

	if mouse_is_down_right or (is_build_mode and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_process_build_drag()

	if is_build_mode:
		_update_brush_pos()


func _unhandled_input(event: InputEvent) -> void:
	# Right-click drawing — only in Build Mode
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if is_build_mode:
				mouse_is_down_right = mb.pressed
				if not mb.pressed:
					current_build_y = -1000.0
					is_drawing_line = false
				get_viewport().set_input_as_handled()
			else:
				mouse_is_down_right = false
			return

	# Wave targeting input
	if not wave_pending:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if is_build_mode:
				get_viewport().set_input_as_handled()
				return # Drag logic handles it in _process
			
			_fire_wave_at_mouse(mb.position)
			wave_pending = false
			get_viewport().set_input_as_handled()


func register_rat(rat: CharacterBody3D) -> void:
	rats.append(rat)


func activate_orbit() -> void:
	if orbit_active:
		deactivate_orbit()
		return

	# Cancel targeting if pending
	wave_pending = false

	orbit_active = true
	orbit_timer = orbit_duration
	
	var total_rats := rats.size()
	var rats_per_ring := 15
	var ring_spacing := 1.2
	var base_radius := 2.0
	
	for i in range(total_rats):
		var ring_index := floori(float(i) / rats_per_ring)
		var index_in_ring := i % rats_per_ring
		
		# Get actual count for THIS ring to spread evenly
		var current_ring_count := rats_per_ring
		if (ring_index + 1) * rats_per_ring > total_rats:
			current_ring_count = total_rats % rats_per_ring
		
		var radius := base_radius + (ring_index * ring_spacing)
		var angle := (TAU / current_ring_count) * index_in_ring
		
		# Offset angle per ring for better visual distribution
		angle += ring_index * 0.5
		
		rats[i].set_orbit(angle, radius)
	
	orbit_started.emit()


func deactivate_orbit() -> void:
	orbit_active = false
	orbit_timer = 0.0
	for rat in rats:
		rat.set_follow()
	orbit_ended.emit()


func get_orbit_progress() -> float:
	if not orbit_active:
		return 0.0
	return orbit_timer / orbit_duration


func activate_wave() -> void:
	# Cancel orbit if active
	if orbit_active:
		deactivate_orbit()

	# Enter targeting mode — wait for click
	wave_pending = true


func _fire_wave_at_mouse(screen_pos: Vector2) -> void:
	wave_active = true
	wave_timer = wave_duration

	var player_node: Node3D = rats[0].player
	var player_pos: Vector3 = player_node.global_position

	# Raycast mouse to ground plane (Y=0)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)

	var forward := Vector3(0, 0, 1)
	if abs(ray_dir.y) > 0.001:
		var t: float = - ray_origin.y / ray_dir.y
		var ground_hit: Vector3 = ray_origin + ray_dir * t
		forward = (ground_hit - player_pos)
		forward.y = 0.0

	if forward.length() < 0.1:
		forward = Vector3(0, 0, 1)
	forward = forward.normalized()

	var count := rats.size()
	for i in range(count):
		var spread: float = deg_to_rad(remap(i, 0, count - 1, -30.0, 30.0))
		var dir: Vector3 = forward.rotated(Vector3.UP, spread)
		var delay: float = randf_range(0.0, 0.15)
		rats[i].set_wave(dir, delay)
	wave_started.emit()


func on_stratagem_activated(stratagem_id: String) -> void:
	match stratagem_id:
		"rat_orbit":
			activate_orbit()
		"rat_wave":
			activate_wave()


func recall_all_rats() -> void:
	built_positions.clear()
	for rat in rats:
		rat.release_rat()
	# Reset drawing state
	mouse_is_down_right = false
	is_drawing_line = false
	current_build_y = -1000.0


func _get_mouse_ground_hit() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collision_mask = 1  # Only environment/floor
	return space_state.intersect_ray(query)


func _process_build_drag() -> void:
	var hit := _get_mouse_ground_hit()
	if not hit:
		return

	var raw_pos: Vector3 = hit.position + hit.normal * 0.25
	if current_build_y <= -500.0:
		current_build_y = raw_pos.y

	if is_drawing_line:
		var dist := last_draw_pos.distance_to(raw_pos)
		var steps := maxi(1, ceili(dist / 0.125))
		for i in range(1, steps + 1):
			var inter_pos := last_draw_pos.lerp(raw_pos, float(i) / steps)
			_try_build_at(inter_pos)
	else:
		is_drawing_line = true
		_try_build_at(raw_pos)
	last_draw_pos = raw_pos


func _try_build_at(raw_pos: Vector3) -> void:
	var build_pos := raw_pos
	build_pos.x = snapped(build_pos.x, 0.5)
	build_pos.y = current_build_y
	build_pos.z = snapped(build_pos.z, 0.5)

	if built_positions.has(build_pos):
		return

	var free_rat: CharacterBody3D = null
	for rat in rats:
		if rat.state == rat.State.FOLLOW:
			free_rat = rat
			break

	if free_rat:
		free_rat.build_at(build_pos)
		built_positions[build_pos] = true


func set_build_mode(enabled: bool) -> void:
	is_build_mode = enabled
	brush_node.visible = enabled
	if not enabled:
		mouse_is_down_right = false
		is_drawing_line = false
		current_build_y = -1000.0


func _update_brush_pos() -> void:
	var hit := _get_mouse_ground_hit()
	if hit:
		brush_node.global_position = hit.position + Vector3(0, 0.1, 0)
		brush_node.visible = true
	else:
		brush_node.visible = false
