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
var mouse_is_down_middle: bool = false

# Rats that are currently acting as box carriers
var carrier_rats: Dictionary = {}
# Per-carrier-rat offset from the box center (world-space XZ offset at the time of surrounding)
var carrier_rat_offsets: Dictionary = {}
var last_draw_pos: Vector3 = Vector3(-1000, -1000, -1000)
var is_drawing_line: bool = false
var current_build_y: float = -1000.0
var _ctrl_was_pressed: bool = false

var current_drawn_path: PackedVector3Array = []
var min_point_dist_squared: float = 0.05

# All positions in the most recently issued build command.
# Used so any traveling rat can anchor near any brush point, not just its own.
var active_build_positions: Array[Vector3] = []

const DRAW_MODE_PATH := 0
const DRAW_MODE_CIRCLE := 1

@export_enum("Path", "Circle")
var build_draw_mode: int = DRAW_MODE_CIRCLE

@export var use_wide_brush: bool = false
@export var brush_half_width: float = 0.3
@export var brush_half_width_min: float = 0.1
@export var brush_half_width_max: float = 1.5
@export var brush_half_width_step: float = 0.05

@export var brush_lane_pairs: int = 1 # number of extra line pairs (left/right)
@export var brush_lane_pairs_min: int = 0
@export var brush_lane_pairs_max: int = 4
@export var brush_lane_spacing: float = 0.3 # distance between parallel lines

@export var circle_radius: float = 0.5
@export var circle_radius_min: float = 0.25
@export var circle_radius_max: float = 4.0
@export var circle_radius_step: float = 0.25
@export var circle_fill_spacing: float = 0.5

var current_circle_center: Vector3 = Vector3.ZERO

var grabbed_box: box = null
var grabbed_box_last_pos: Vector3 = Vector3.ZERO
var mmb_press_screen_pos: Vector2 = Vector2.ZERO

@export var box_drag_lerp_factor: float = 0.008

var line_mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh
var line_material: StandardMaterial3D

var unified_shape_combiner: CSGCombiner3D


func _ready() -> void:
	immediate_mesh = ImmediateMesh.new()
	line_mesh_instance = MeshInstance3D.new()
	
	unified_shape_combiner = CSGCombiner3D.new()
	unified_shape_combiner.use_collision = true
	unified_shape_combiner.collision_layer = 1 # layer 1 is solid to player
	add_child(unified_shape_combiner)
	line_mesh_instance.mesh = immediate_mesh
	
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color.WHITE
	# Slight thickness isn't supported out of the box with standard lines easily in Godot 4, 
	# but unshaded white will be very visible.
	line_mesh_instance.material_override = line_material
	
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

		if mouse_is_down_middle and grabbed_box:
			_process_box_drag()

		# Always show circular brush preview when in circle mode, even when not dragging
		if build_draw_mode == DRAW_MODE_CIRCLE and not mouse_is_down_left:
			var hit := _get_mouse_ground_hit()
			if hit:
				var raw_pos: Vector3 = hit.position + hit.normal * 0.25
				if current_build_y <= -500.0:
					current_build_y = raw_pos.y
				raw_pos.y = current_build_y
				current_circle_center = raw_pos
				_update_circle_preview(false)
			elif current_build_y > -500.0:
				# No geometry under cursor — project onto last valid Y plane and show preview in red
				var fallback := _get_mouse_pos_at_y(current_build_y)
				if fallback != Vector3.ZERO:
					current_circle_center = fallback
					_update_circle_preview(true)

	_ctrl_was_pressed = ctrl_pressed

	if mode != 1:
		mouse_is_down_left = false
		mouse_is_down_right = false
		is_drawing_line = false
		current_build_y = -1000.0
		active_build_positions.clear() # Clear active build positions when leaving build mode

	_check_formation_sync()
	_check_carrier_arrival()
	_check_travel_anchoring()

	# Keep carrier rats' blob_target synced to the box position every frame
	_update_carrier_rat_targets()


## Anchors any rat that is traveling and comes within anchor_radius of any
## active brush position, so rats can float as bridge pieces mid-path.
func _check_travel_anchoring() -> void:
	if active_build_positions.is_empty():
		return
	for rat in rats:
		if rat.state != rat.State.TRAVEL_TO_BUILD:
			continue
		if rat.is_anchored:
			continue
		var flat_rat := Vector2(rat.global_position.x, rat.global_position.z)
		for bp in active_build_positions:
			var flat_bp := Vector2(bp.x, bp.z)
			if flat_rat.distance_to(flat_bp) <= rat.anchor_radius:
				rat.is_anchored = true
				break


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
		# Skip rats that are currently carrying boxes
		if carrier_rats.has(rat):
			continue
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
		sphere.global_position = rat.global_position + Vector3(0, -0.35, 0)
		
		# Apply rat material color (brown)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.30, 0.18) # Matches standard rat brown
		sphere.material = mat
		
		unified_shape_combiner.add_child(sphere)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		# Scroll wheel controls brush in build modes
		if mode == 1 and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if build_draw_mode == DRAW_MODE_PATH and use_wide_brush:
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					brush_lane_pairs += 1
				else:
					brush_lane_pairs -= 1
				brush_lane_pairs = clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
			elif build_draw_mode == DRAW_MODE_CIRCLE:
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					circle_radius += circle_radius_step
				else:
					circle_radius -= circle_radius_step
				circle_radius = clampf(circle_radius, circle_radius_min, circle_radius_max)
				if mouse_is_down_left:
					_update_circle_preview()

			get_viewport().set_input_as_handled()
			return
		
		# Left-click drawing
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mode == 1:
				if mb.pressed:
					mouse_is_down_left = true
					left_click_start_pos = mb.position
					is_dragging_left = false
					current_drawn_path.clear()
					current_build_y = -1000.0  # Always lock Y from the actual drag-start hit
				else:
					if not is_dragging_left:
						_send_horde_to_point()
					else:
						if build_draw_mode == DRAW_MODE_PATH:
							_distribute_rats_on_path()
						elif build_draw_mode == DRAW_MODE_CIRCLE:
							_build_circle_if_possible()
					
					mouse_is_down_left = false
					current_build_y = -1000.0
					is_drawing_line = false
					current_drawn_path.clear()
					immediate_mesh.clear_surfaces()
				get_viewport().set_input_as_handled()
			return
			
		# Right-click: blob control (as before)
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mode == 1:
				if mb.pressed:
					mouse_is_down_right = true
				else:
					mouse_is_down_right = false
				get_viewport().set_input_as_handled()
			return

		# Middle-click: box interaction (surround / grab / release)
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mode == 1:
				if mb.pressed:
					mmb_press_screen_pos = mb.position
					if grabbed_box != null:
						# Box already grabbed — just start/resume dragging immediately.
						# Release is handled on MMB release if the mouse barely moved (click).
						mouse_is_down_middle = true
						get_viewport().set_input_as_handled()
						return

					# No box currently grabbed — raycast to find one
					var camera_m: Camera3D = get_viewport().get_camera_3d()
					var ray_origin_m: Vector3 = camera_m.project_ray_origin(mb.position)
					var ray_dir_m: Vector3 = camera_m.project_ray_normal(mb.position)
					var space_state_m := camera_m.get_world_3d().direct_space_state
					var query_m := PhysicsRayQueryParameters3D.create(ray_origin_m, ray_origin_m + ray_dir_m * 1000.0)
					var hit_m := space_state_m.intersect_ray(query_m)

					if hit_m and hit_m.collider is box:
						var b: box = hit_m.collider
						mouse_is_down_middle = true
						if not b.is_surrounded:
							_surround_box_with_rats(b)
						grabbed_box = b
						grabbed_box_last_pos = b.global_position
						get_viewport().set_input_as_handled()
						return

					# No box hit – ignore
					mouse_is_down_middle = false
				else:
					# MMB released — check if this was a quick click (tiny mouse movement)
					# or a real drag. Only release the box on a click, not after dragging.
					mouse_is_down_middle = false
					if grabbed_box != null:
						var moved_sq := mmb_press_screen_pos.distance_squared_to(mb.position)
						if moved_sq < drag_threshold_squared:
							# Short click — release the box
							_release_box_carriers(grabbed_box)
							grabbed_box = null
							grabbed_box_last_pos = Vector3.ZERO
						# else: was a drag — keep the box grabbed for the next drag
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
	# Release any grabbed box and its carrier rats first
	if grabbed_box != null:
		_release_box_carriers(grabbed_box)
		grabbed_box = null
		grabbed_box_last_pos = Vector3.ZERO
		mouse_is_down_middle = false

	active_build_positions.clear()
	built_positions.clear()
	carrier_rats.clear()
	carrier_rat_offsets.clear()
	
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
	#query.collision_mask = 1  # Only environment/floor
	return space_state.intersect_ray(query)


# Projects the mouse ray to a horizontal plane at the given Y level.
# Used as a fallback when dragging over gaps (no collision beneath cursor).
func _get_mouse_pos_at_y(y: float) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.0001:
		# Ray nearly horizontal — can't intersect a horizontal plane
		return Vector3.ZERO
	var t := (y - ray_origin.y) / ray_dir.y
	return ray_origin + ray_dir * t


func _process_build_drag() -> void:
	var hit := _get_mouse_ground_hit()

	var raw_pos: Vector3
	if hit:
		raw_pos = hit.position + hit.normal * 0.25
		if current_build_y <= -500.0:
			current_build_y = raw_pos.y
		raw_pos.y = current_build_y
	elif current_build_y > -500.0:
		# No ground under cursor but drag is already in progress —
		# project to the locked Y plane so the path continues over gaps.
		var fallback := _get_mouse_pos_at_y(current_build_y)
		if fallback == Vector3.ZERO:
			return
		raw_pos = fallback
	else:
		# Drag hasn't started on ground yet — ignore
		return

	if build_draw_mode == DRAW_MODE_PATH:
		if current_drawn_path.is_empty():
			current_drawn_path.append(raw_pos)
		else:
			var last_recorded_pos = current_drawn_path[current_drawn_path.size() - 1]
			if last_recorded_pos.distance_squared_to(raw_pos) > min_point_dist_squared:
				current_drawn_path.append(raw_pos)
		
		_update_drawn_line(raw_pos)
	elif build_draw_mode == DRAW_MODE_CIRCLE:
		if current_drawn_path.is_empty():
			current_drawn_path.append(raw_pos)
		else:
			var last_recorded_pos_circle = current_drawn_path[current_drawn_path.size() - 1]
			if last_recorded_pos_circle.distance_squared_to(raw_pos) > min_point_dist_squared:
				current_drawn_path.append(raw_pos)

		current_circle_center = raw_pos
		_update_circle_preview()


func _update_drawn_line(end_pos: Vector3, invalid_surface: bool = false) -> void:
	immediate_mesh.clear_surfaces()
	
	if current_drawn_path.size() == 0:
		return

	if line_material:
		line_material.albedo_color = Color(1, 0, 0) if invalid_surface else Color.WHITE
	
	# Small vertical offset to prevent z-fighting with the ground
	var offset := Vector3(0, 0.1, 0)

	# Center line strip (original behavior)
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for pos in current_drawn_path:
		immediate_mesh.surface_add_vertex(pos + offset)
	# Add the current cursor pos as the uncommitted end of the line
	immediate_mesh.surface_add_vertex(end_pos + offset)
	immediate_mesh.surface_end()

	if not use_wide_brush:
		return

	# Precompute lateral direction for each point along the path (XZ plane)
	var count := current_drawn_path.size()
	var laterals: Array[Vector3] = []
	laterals.resize(count)

	for i in range(count):
		var p: Vector3 = current_drawn_path[i]
		var dir: Vector3

		if count == 1:
			dir = end_pos - p
		elif i == 0:
			dir = current_drawn_path[1] - current_drawn_path[0]
		elif i == count - 1:
			dir = current_drawn_path[count - 1] - current_drawn_path[count - 2]
		else:
			dir = current_drawn_path[i + 1] - current_drawn_path[i - 1]

		dir.y = 0.0
		if dir.length() < 0.001:
			dir = Vector3.FORWARD
		else:
			dir = dir.normalized()

		laterals[i] = dir.cross(Vector3.UP).normalized()

	# Lateral for the uncommitted end point
	var end_dir: Vector3 = end_pos - current_drawn_path[count - 1]
	end_dir.y = 0.0
	if end_dir.length() < 0.001:
		end_dir = Vector3.FORWARD
	else:
		end_dir = end_dir.normalized()
	var end_lateral := end_dir.cross(Vector3.UP).normalized()

	# Draw multiple parallel strips with constant spacing; scroll wheel changes how many
	var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
	if pairs <= 0:
		return

	var lane_count := 1 + pairs * 2
	var center_index := float(lane_count - 1) / 2.0

	for lane_index in range(lane_count):
		if lane_index == int(center_index):
			continue # center line already drawn above

		var factor := float(lane_index) - center_index
		var lateral_offset_scale := factor * brush_lane_spacing

		immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for j in range(count):
			var pos: Vector3 = current_drawn_path[j]
			var lat: Vector3 = laterals[j] * lateral_offset_scale
			immediate_mesh.surface_add_vertex(pos + lat + offset)
		immediate_mesh.surface_add_vertex(end_pos + end_lateral * lateral_offset_scale + offset)
		immediate_mesh.surface_end()


func _get_available_follow_rats() -> Array:
	var available_rats: Array[CharacterBody3D] = []
	for rat in rats:
		if rat.state == rat.State.FOLLOW and not rat.is_carrier:
			available_rats.append(rat)
	return available_rats


func _compute_circle_fill_positions(center: Vector3) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var radius := circle_radius
	var spacing := circle_fill_spacing
	if spacing <= 0.01:
		spacing = 0.01

	var max_steps: int = int(ceil(radius / spacing))
	for ix in range(-max_steps, max_steps + 1):
		for iz in range(-max_steps, max_steps + 1):
			var offset := Vector3(float(ix) * spacing, 0.0, float(iz) * spacing)
			if offset.x * offset.x + offset.z * offset.z <= radius * radius + 0.001:
				positions.append(center + offset)
	return positions


func _compute_circle_path_fill_positions(path: PackedVector3Array) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var used := {}

	var spacing := circle_fill_spacing
	if spacing <= 0.01:
		spacing = 0.01

	for center in path:
		var circle_positions := _compute_circle_fill_positions(center)
		for p in circle_positions:
			# Quantize to grid to deduplicate overlapping points from neighboring circles
			var key := Vector2i(int(round(p.x / spacing)), int(round(p.z / spacing)))
			if not used.has(key):
				used[key] = true
				positions.append(p)

	return positions


func _update_circle_preview(invalid_surface: bool = false) -> void:
	immediate_mesh.clear_surfaces()

	var center := current_circle_center
	var path_for_preview := current_drawn_path
	if path_for_preview.is_empty():
		path_for_preview = PackedVector3Array()
		path_for_preview.append(center)

	var fill_positions := _compute_circle_path_fill_positions(path_for_preview)
	var required := fill_positions.size()
	# Count only non-carrier rats for the preview
	var total_rats := 0
	for rat in rats:
		if not rat.is_carrier:
			total_rats += 1
	var enough_rats := total_rats >= required

	if line_material:
		if invalid_surface:
			line_material.albedo_color = Color(1, 0, 0) # Red: hovering over invalid/empty area
		else:
			line_material.albedo_color = Color.WHITE if enough_rats else Color(1, 0, 0)

	# Draw circle outline
	var segments := 32
	var offset := Vector3(0, 0.1, 0)
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(segments + 1):
		var t := float(i) / float(segments) * TAU
		var x := cos(t) * circle_radius
		var z := sin(t) * circle_radius
		immediate_mesh.surface_add_vertex(center + Vector3(x, 0, z) + offset)
	immediate_mesh.surface_end()

	# Highlight the area that can actually be built with current available rats
	if required == 0:
		return

	var max_buildable: int = min(total_rats, required)
	var mark_radius: float = circle_fill_spacing * 0.25
	if mark_radius <= 0.02:
		mark_radius = 0.02

	for i in range(max_buildable):
		var p := fill_positions[i] + offset
		immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		immediate_mesh.surface_add_vertex(p + Vector3(-mark_radius, 0, 0))
		immediate_mesh.surface_add_vertex(p + Vector3(mark_radius, 0, 0))
		immediate_mesh.surface_add_vertex(p + Vector3(0, 0, -mark_radius))
		immediate_mesh.surface_add_vertex(p + Vector3(0, 0, mark_radius))
		immediate_mesh.surface_end()


func _build_circle_if_possible() -> void:
	var fill_positions := _compute_circle_path_fill_positions(current_drawn_path)
	if fill_positions.is_empty():
		return

	# Destroy previous build
	built_positions.clear()
	for child in unified_shape_combiner.get_children():
		child.queue_free()
	for rat in rats:
		rat.release_rat()

	# Recompute available rats after release
	var available_rats: Array = _get_available_follow_rats()

	var count: int = min(available_rats.size(), fill_positions.size())
	active_build_positions.clear()
	for i in range(count):
		var rat = available_rats[i]
		var pos = fill_positions[i]
		rat.build_at(pos)
		active_build_positions.append(pos)


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
		if rat.state == rat.State.FOLLOW and not rat.is_carrier:
			available_rats.append(rat)
			
	var rat_count = available_rats.size()
	if rat_count == 0:
		return
		
	if rat_count == 1:
		var single_pos := current_drawn_path[0]
		if use_wide_brush:
			# Push lone rat to center lane of a theoretical wide brush
			var dir_single := (current_drawn_path[1] - current_drawn_path[0])
			dir_single.y = 0.0
			if dir_single.length() < 0.001:
				dir_single = Vector3.FORWARD
			else:
				dir_single = dir_single.normalized()
			var lateral_single := dir_single.cross(Vector3.UP).normalized() * brush_half_width
			single_pos = current_drawn_path[0]  # center; could be adjusted if needed
		available_rats[0].build_at(single_pos)
		return
		
	var dist_between_rats = path_length / float(rat_count - 1)
	var current_dist_on_path: float = 0.0
	
	for i in range(rat_count):
		# Start and end snap exactly
		if i == 0:
			var start_pos := current_drawn_path[0]
			if use_wide_brush and rat_count > 2:
				# Determine lane based on index
				var lane_idx := 0 # center by default
				# For first rat we keep it center to anchor the path
				start_pos = current_drawn_path[0]
			available_rats[0].build_at(start_pos)
			continue
		elif i == rat_count - 1:
			var end_pos := current_drawn_path[-1]
			if use_wide_brush and rat_count > 2:
				# Keep last rat on center for consistency
				end_pos = current_drawn_path[-1]
			available_rats[i].build_at(end_pos)
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
		var point_a: Vector3 = current_drawn_path[segment_idx]
		var point_b: Vector3 = current_drawn_path[segment_idx + 1]
		var interp_pos = point_a.lerp(point_b, segment_t)
		
		if use_wide_brush:
			# Compute local forward direction and lateral base direction
			var dir := point_b - point_a
			dir.y = 0.0
			if dir.length() < 0.001:
				dir = Vector3.FORWARD
			else:
				dir = dir.normalized()
			var lateral_dir := dir.cross(Vector3.UP).normalized()

			# Distribute rats across a variable number of lanes.
			# Lane count is 1 center lane plus left/right pairs, with constant spacing.
			var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
			if pairs > 0:
				var lane_count := 1 + pairs * 2
				var center_index := float(lane_count - 1) / 2.0
				var lane_index := i % lane_count
				var factor := float(lane_index) - center_index
				interp_pos += lateral_dir * brush_lane_spacing * factor

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
		if rat.state == rat.State.FOLLOW and not rat.is_carrier:
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


func _surround_box_with_rats(b: box) -> void:
	var center: Vector3 = b.global_position

	var available_rats: Array[CharacterBody3D] = []
	for rat in rats:
		if rat.state == rat.State.FOLLOW and not rat.is_carrier:
			available_rats.append(rat)

	var count: int = available_rats.size()
	if count == 0:
		return

	var needed: int = min(b.carriers_required, count)
	if needed <= 0:
		return

	var ring_radius := 1.0
	if needed > 8:
		ring_radius = 1.5

	b.carrier_rats.clear()

	for i in range(needed):
		var angle := (TAU / needed) * i
		# Offset is relative to the box center so it can be reapplied as the box moves
		var offset := Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)
		var pos := center + offset
		var r: CharacterBody3D = available_rats[i]
		# Make this rat a carrier without entering the build/static pipeline.
		# Keep it in FOLLOW state but have it follow its offset around the box.
		# Zero out follow_offset so the rat targets its exact ring position
		# (arrival check in _check_carrier_arrival compares against blob_target directly).
		r.state = r.State.FOLLOW
		r.is_following_player = false
		r.follow_offset = Vector3.ZERO
		r.blob_target = pos
		r.is_carrier = true
		b.carrier_rats.append(r)
		# Remember the offset so we can update blob_target every frame as the box moves
		carrier_rat_offsets[r] = offset

	# Rats are on their way — dragging is locked until they arrive
	b.is_surrounded = false

	# Connect to box_reset so we can release carriers if the box falls
	if not b.box_reset.is_connected(_on_box_reset):
		b.box_reset.connect(_on_box_reset.bind(b))


func _on_box_reset(b: box) -> void:
	# Box fell and teleported back — release its carriers and reset grab state
	_release_box_carriers(b)
	if grabbed_box == b:
		grabbed_box = null
		grabbed_box_last_pos = Vector3.ZERO
		mouse_is_down_middle = false


func _process_blob_follow() -> void:
	var hit := _get_mouse_ground_hit()
	if not hit:
		return

	var raw_pos: Vector3 = hit.position
	
	for rat in rats:
		if rat.state == rat.State.FOLLOW:
			rat.is_following_player = false
			rat.blob_target = raw_pos


func _check_carrier_arrival() -> void:
	# Once all carrier rats on the grabbed box have reached their positions,
	# snap them precisely and mark the box as surrounded to unlock dragging.
	if grabbed_box == null or grabbed_box.is_surrounded:
		return
	# Snap rats to their target once they are close — prevents them getting stuck
	# on the box collider and never fully arriving.
	var snap_dist_sq := 5.5 * 5.5
	for r in grabbed_box.carrier_rats:
		if r == null:
			continue
		var flat_pos := Vector2(r.global_position.x, r.global_position.z)
		var flat_target := Vector2(r.blob_target.x, r.blob_target.z)
		if flat_pos.distance_squared_to(flat_target) <= snap_dist_sq:
			# Teleport the rat to its exact slot so it can't be blocked
			r.global_position = Vector3(r.blob_target.x, r.global_position.y, r.blob_target.z)
			r.velocity = Vector3.ZERO

	# Now check if every rat is at its target
	var arrival_dist_sq := 0.05 * 0.05
	for r in grabbed_box.carrier_rats:
		if r == null:
			continue
		var flat_pos := Vector2(r.global_position.x, r.global_position.z)
		var flat_target := Vector2(r.blob_target.x, r.blob_target.z)
		if flat_pos.distance_squared_to(flat_target) > arrival_dist_sq:
			return  # at least one rat hasn't snapped yet
	grabbed_box.is_surrounded = true


func _process_box_drag() -> void:
	if grabbed_box == null:
		return

	# Block dragging until all carrier rats have reached the box
	if not grabbed_box.is_surrounded:
		return

	var hit := _get_mouse_ground_hit()
	if not hit:
		return

	var current_pos: Vector3 = grabbed_box.global_position
	var target_pos: Vector3 = hit.position
	target_pos.y = current_pos.y

	# Move box towards target slowly for a carried feel
	var new_pos: Vector3 = current_pos.lerp(target_pos, box_drag_lerp_factor)

	grabbed_box.global_position = new_pos
	# Carrier rats' blob_target is updated in _update_carrier_rat_targets() each frame


func _update_carrier_rat_targets() -> void:
	# Update blob_target for carrier rats on the grabbed box so they
	# continuously follow the box as it moves during drag.
	if grabbed_box == null or not grabbed_box.is_surrounded:
		return
	var box_pos: Vector3 = grabbed_box.global_position
	for r in grabbed_box.carrier_rats:
		if r and carrier_rat_offsets.has(r):
			r.blob_target = box_pos + carrier_rat_offsets[r]


func _release_box_carriers(b: box) -> void:
	if b == null:
		return

	for r in b.carrier_rats:
		if r:
			r.is_carrier = false
			r.is_following_player = true
			r.release_rat()
			if carrier_rats.has(r):
				carrier_rats.erase(r)
			carrier_rat_offsets.erase(r)
	b.carrier_rats.clear()
	b.is_surrounded = false


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
