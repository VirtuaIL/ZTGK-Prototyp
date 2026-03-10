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

var mode: int = 0: # 0 = COMBAT, 1 = BUILD
	set(new_mode):
		mode = new_mode
		if mode == 0:
			# Return rats to player
			for rat in rats:
				rat.is_following_player = true
			mouse_is_down_left = false
			mouse_is_down_right = false

# Drawing & Blob
var built_positions: Dictionary = {}
var mouse_is_down_left: bool = false
var left_click_start_pos: Vector2 = Vector2(-1, -1)
var is_dragging_left: bool = false
var drag_threshold_squared: float = 100.0 # 10 pixels squared threshold

var mouse_is_down_right: bool = false
var last_draw_pos: Vector3 = Vector3(-1000, -1000, -1000)
var is_drawing_line: bool = false
var current_build_y: float = -1000.0
var _ctrl_was_pressed: bool = false

var current_drawn_path: PackedVector3Array = []
var min_point_dist_squared: float = 0.05

var line_mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh

var unified_shape_combiner: CSGCombiner3D


func _ready() -> void:
	immediate_mesh = ImmediateMesh.new()
	line_mesh_instance = MeshInstance3D.new()
	
	unified_shape_combiner = CSGCombiner3D.new()
	unified_shape_combiner.use_collision = true
	unified_shape_combiner.collision_layer = 1 # layer 1 is solid to player
	add_child(unified_shape_combiner)
	line_mesh_instance.mesh = immediate_mesh
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	# Slight thickness isn't supported out of the box with standard lines easily in Godot 4, 
	# but unshaded white will be very visible.
	line_mesh_instance.material_override = mat
	
	add_child(line_mesh_instance)


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
	if mode == 1:
		if ctrl_pressed and not _ctrl_was_pressed:
			recall_all_rats()

		if mouse_is_down_left:
			if not is_dragging_left:
				var current_mouse_pos := get_viewport().get_mouse_position()
				if left_click_start_pos.distance_squared_to(current_mouse_pos) > drag_threshold_squared:
					is_dragging_left = true
			
			if is_dragging_left:
				_process_build_drag()
		
		if mouse_is_down_right:
			_process_blob_follow()

	_ctrl_was_pressed = ctrl_pressed

	if mode != 1:
		mouse_is_down_left = false
		mouse_is_down_right = false
		is_drawing_line = false
		current_build_y = -1000.0

	_check_formation_sync()


func _check_formation_sync() -> void:
	if mode != 1:
		return
		
	var any_traveling = false
	var any_waiting = false
	
	for rat in rats:
		if rat.state == rat.State.TRAVEL_TO_BUILD:
			any_traveling = true
			break
		elif rat.state == rat.State.WAITING_FOR_FORMATION:
			any_waiting = true
			
	# If no rats are traveling, but some are waiting, they have all arrived.
	if not any_traveling and any_waiting:
		for rat in rats:
			if rat.state == rat.State.WAITING_FOR_FORMATION:
				rat.activate_physics()
		_form_unified_mesh()


func _form_unified_mesh() -> void:
	# Clear the existing unified mesh components
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	# Find all rats in STATIC state (acting as build structure)
	var static_rats: Array = []
	for rat in rats:
		if rat.state == rat.State.STATIC:
			static_rats.append(rat)
			rat.hide_visuals()
			# Disable individual collision so player only collides with the CSG
			rat.set_collision_layer_value(1, false)

	if static_rats.is_empty():
		return

	# Add CSG primitives for each rat
	# Since rats are placed closely based on step size, slightly thickened shapes blend well
	for rat in static_rats:
		# Use a CSGSphere3D to get an organic blob look
		# It's slightly larger than the rat visual bounds to fuse with neighbors
		var sphere = CSGSphere3D.new()
		sphere.radius = 0.35 
		sphere.radial_segments = 12
		sphere.rings = 6
		sphere.global_position = rat.global_position + Vector3(0, 0.1, 0)
		
		# Apply rat material color (brown)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.30, 0.18) # Matches standard rat brown
		sphere.material = mat
		
		unified_shape_combiner.add_child(sphere)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		# Left-click drawing
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mode == 1:
				if mb.pressed:
					mouse_is_down_left = true
					left_click_start_pos = mb.position
					is_dragging_left = false
					current_drawn_path.clear()
				else:
					if not is_dragging_left:
						_send_horde_to_point()
					else:
						_distribute_rats_on_path()
					
					mouse_is_down_left = false
					current_build_y = -1000.0
					is_drawing_line = false
					current_drawn_path.clear()
					immediate_mesh.clear_surfaces()
				get_viewport().set_input_as_handled()
			return
			
		# Right-click blob control
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mode == 1:
				mouse_is_down_right = mb.pressed
				if not mb.pressed:
					# Stop updating blob target, keep rats at last known target
					pass
				get_viewport().set_input_as_handled()
			return

	# Wave targeting input (Combat Mode)
	if not wave_pending:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
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
	var count := rats.size()
	# Scale radius based on rat count: min 1.5, grows with more rats
	var radius: float = maxf(1.5, count * 0.5)
	for i in range(count):
		var angle := (TAU / count) * i
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
	
	# Destroy the unified mesh
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	for rat in rats:
		rat.release_rat()
	# Reset drawing state
	mouse_is_down_left = false
	is_dragging_left = false
	mouse_is_down_right = false
	is_drawing_line = false
	current_build_y = -1000.0
	current_drawn_path.clear()
	immediate_mesh.clear_surfaces()
	for rat in rats:
		rat.is_following_player = true


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

	raw_pos.y = current_build_y
	
	if current_drawn_path.is_empty():
		current_drawn_path.append(raw_pos)
	else:
		var last_recorded_pos = current_drawn_path[current_drawn_path.size() - 1]
		if last_recorded_pos.distance_squared_to(raw_pos) > min_point_dist_squared:
			current_drawn_path.append(raw_pos)
			
	_update_drawn_line(raw_pos)


func _update_drawn_line(end_pos: Vector3) -> void:
	immediate_mesh.clear_surfaces()
	
	if current_drawn_path.size() == 0:
		return
		
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	
	# Small vertical offset to prevent z-fighting with the ground
	var offset := Vector3(0, 0.1, 0)
	
	for pos in current_drawn_path:
		immediate_mesh.surface_add_vertex(pos + offset)
		
	# Add the current cursor pos as the uncommitted end of the line
	immediate_mesh.surface_add_vertex(end_pos + offset)
	
	immediate_mesh.surface_end()


func _distribute_rats_on_path() -> void:
	if current_drawn_path.size() < 2:
		return
		
	var path_length: float = 0.0
	var segments: Array[float] = []
	for i in range(1, current_drawn_path.size()):
		var segment_len = current_drawn_path[i-1].distance_to(current_drawn_path[i])
		path_length += segment_len
		segments.append(segment_len)
		
	built_positions.clear()
	
	# Destroy the unified mesh from any previous build
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	for rat in rats:
		rat.release_rat()
		
	var available_rats: Array = []
	for rat in rats:
		if rat.state == rat.State.FOLLOW:
			available_rats.append(rat)
			
	var rat_count = available_rats.size()
	if rat_count == 0:
		return
		
	if rat_count == 1:
		available_rats[0].build_at(current_drawn_path[0])
		return
		
	var dist_between_rats = path_length / float(rat_count - 1)
	var current_dist_on_path: float = 0.0
	
	for i in range(rat_count):
		# Start and end snap exactly
		if i == 0:
			available_rats[0].build_at(current_drawn_path[0])
			continue
		elif i == rat_count - 1:
			available_rats[i].build_at(current_drawn_path[-1])
			continue
			
		var target_dist = i * dist_between_rats
		
		# Find segment containing target_dist
		var accum: float = 0.0
		var segment_idx: int = 0
		var segment_start: float = 0.0
		
		for j in range(segments.size()):
			if accum + segments[j] >= target_dist:
				segment_idx = j
				segment_start = accum
				break
			accum += segments[j]
			
		# Interpolate
		var segment_t = (target_dist - segment_start) / max(0.0001, segments[segment_idx])
		var point_a = current_drawn_path[segment_idx]
		var point_b = current_drawn_path[segment_idx + 1]
		var interp_pos = point_a.lerp(point_b, segment_t)
		
		available_rats[i].build_at(interp_pos)


func _send_horde_to_point() -> void:
	var hit := _get_mouse_ground_hit()
	if not hit:
		return
		
	var target_pos: Vector3 = hit.position
	target_pos.x = snapped(target_pos.x, 0.5)
	target_pos.y = hit.position.y
	target_pos.z = snapped(target_pos.z, 0.5)

	# Free all currently built rats to rally them
	built_positions.clear()
	
	# Destroy the unified mesh from any previous build
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	for rat in rats:
		rat.release_rat()

	# Arrange rats in a small circle/grid around target
	var available_rats: Array = []
	for rat in rats:
		# all should be follow state after release, but filter just in case
		if rat.state == rat.State.FOLLOW:
			available_rats.append(rat)
			
	var count = available_rats.size()
	if count == 0:
		return

	# simple circle formation
	var ring_radius = 0.5
	if count > 8:
		ring_radius = 1.0
		
	for i in range(count):
		var angle = (TAU / count) * i
		var build_pos = target_pos + Vector3(
			cos(angle) * ring_radius,
			0,
			sin(angle) * ring_radius
		)
		var rat = available_rats[i]
		rat.build_at(build_pos)
		built_positions[build_pos] = true


func _process_blob_follow() -> void:
	var hit := _get_mouse_ground_hit()
	if not hit:
		return

	var raw_pos: Vector3 = hit.position
	
	for rat in rats:
		if rat.state == rat.State.FOLLOW:
			rat.is_following_player = false
			rat.blob_target = raw_pos


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
