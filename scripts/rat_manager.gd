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

# Drawing/Build State
var _ctrl_was_pressed: bool = false
var is_build_mode: bool = false
var brush_node: Node3D # Changed to Node3D to hold multiple ghosts
var ghost_meshes: Array[MeshInstance3D] = []
var SHAPE_SIZE: int = 40 # Number of rats in a bridge
var brush_rotation_offset: float = 0.0
var bridge_scene_obj = preload("res://scenes/rat_bridge.tscn")


var dead_rats: Array[CharacterBody3D] = []
var player_ref: CharacterBody3D

signal rat_count_changed(active: int, total: int)


func _ready() -> void:
	_setup_brush()
	# Connect to existing rats
	for child in get_tree().get_nodes_in_group("rats"):
		if child is CharacterBody3D:
			register_rat(child)
	
	player_ref = get_tree().get_first_node_in_group("player")


func _setup_brush() -> void:
	brush_node = Node3D.new()
	add_child(brush_node)
	
	for i in range(SHAPE_SIZE):
		var ghost := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.15, 0.4)
		ghost.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 1.0, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost.material_override = mat
		brush_node.add_child(ghost)
		ghost_meshes.append(ghost)
		var z_offset := 0.0
		if i < 20:
			z_offset = (i * 0.4) - 3.8
			ghost.position = Vector3(0.25, 0.075, z_offset)
			ghost.rotation_degrees = Vector3(0, -90, 0)
		else:
			z_offset = ((i - 20) * 0.4) - 3.8
			ghost.position = Vector3(-0.25, 0.075, z_offset)
			ghost.rotation_degrees = Vector3(0, 90, 0)
	
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

	if is_build_mode:
		# Use discrete input below rather than continuous processing
		_update_brush_pos()


func _input(event: InputEvent) -> void:
	# 1. Clicks (Both Build Mode and Combat Mode)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		
		# Left click
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if is_build_mode:
				_place_shape()
				get_viewport().set_input_as_handled()
				return
			
			if wave_pending:
				_fire_wave_at_mouse(mb.position)
				wave_pending = false
				get_viewport().set_input_as_handled()
				return

	# 2. Rotation (Only Build Mode)
	if not is_build_mode:
		return

	# Action rotation
	if event.is_action_pressed("rotate_left"):
		brush_rotation_offset += 45.0
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("rotate_right"):
		brush_rotation_offset -= 45.0
		get_viewport().set_input_as_handled()
		return

	# Mouse wheel rotation
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			brush_rotation_offset += 45.0
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			brush_rotation_offset -= 45.0
			get_viewport().set_input_as_handled()
			return


func register_rat(rat: CharacterBody3D) -> void:
	if not rats.has(rat):
		rats.append(rat)
		rat.add_to_group("rats")
		if not rat.fallen_into_abyss.is_connected(_on_rat_fallen):
			rat.fallen_into_abyss.connect(_on_rat_fallen)
	rat_count_changed.emit(rats.size() - dead_rats.size(), rats.size())


func _on_rat_fallen(rat: CharacterBody3D) -> void:
	if dead_rats.has(rat):
		return
	
	dead_rats.append(rat)
	rat.visible = false
	rat.set_physics_process(false)
	rat.process_mode = Node.PROCESS_MODE_DISABLED
	
	rat_count_changed.emit(rats.size() - dead_rats.size(), rats.size())
	
	# Respawn after 5 seconds
	var timer := get_tree().create_timer(5.0)
	timer.timeout.connect(_respawn_rat.bind(rat))


func _respawn_rat(rat: CharacterBody3D) -> void:
	dead_rats.erase(rat)
	rat.visible = true
	rat.set_physics_process(true)
	rat.process_mode = Node.PROCESS_MODE_INHERIT
	
	var spawn_pos := Vector3.ZERO
	if is_instance_valid(rat.player):
		var angle := randf() * TAU
		spawn_pos = rat.player.global_position + Vector3(cos(angle) * 2.0, 2.0, sin(angle) * 2.0)
	elif is_instance_valid(player_ref):
		var angle := randf() * TAU
		spawn_pos = player_ref.global_position + Vector3(cos(angle) * 2.0, 2.0, sin(angle) * 2.0)
	
	rat.respawn_at(spawn_pos)
	rat_count_changed.emit(rats.size() - dead_rats.size(), rats.size())


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
	for rat in rats:
		rat.release_rat()


func _get_mouse_3d_pos() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	# 1. Try physics raycast (hits floor/walls)
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collision_mask = 0xFFFFFFFF  # Hit any layer
	var hit := space_state.intersect_ray(query)
	
	if hit:
		return hit.position
	
	# 2. Fallback: Project onto a horizontal plane at player's feet
	var plane_y := 0.0
	if player_ref:
		plane_y = player_ref.global_position.y
	
	# Plane equation: normal * (P - P0) = 0
	# Ray equation: P = origin + t * dir
	# Solve for t: normal * (origin + t * dir - P0) = 0
	# t = (normal * P0 - normal * origin) / (normal * dir)
	
	var normal := Vector3.UP
	var denom := normal.dot(ray_dir)
	if abs(denom) > 0.0001:
		var t := (normal.dot(Vector3(0, plane_y, 0)) - normal.dot(ray_origin)) / denom
		if t > 0:
			return ray_origin + ray_dir * t
			
	return Vector3.ZERO


func _place_shape() -> void:
	if not is_build_mode: return
	
	var free_rats: Array[CharacterBody3D] = []
	for rat in rats:
		if rat.state == rat.State.FOLLOW:
			free_rats.append(rat)
	
	if free_rats.size() < SHAPE_SIZE:
		return # Not enough rats
		
	# 1. Spawn the bridge immediately
	var bridge = bridge_scene_obj.instantiate()
	get_parent().add_child(bridge)
	bridge.global_position = brush_node.global_position
	bridge.rotation.y = brush_node.rotation.y
	
	# 2. Command rats to run and "consume" themselves at multiple points along the bridge to look cool
	var current_ghost_positions: Array[Vector3] = []
	for g in ghost_meshes:
		current_ghost_positions.append(g.global_position)
		
	for i in range(SHAPE_SIZE):
		var rat: CharacterBody3D = free_rats.pop_front()
		rat.run_to_consume(current_ghost_positions[i])



func set_build_mode(enabled: bool) -> void:
	is_build_mode = enabled
	brush_node.visible = enabled


func _update_brush_pos() -> void:
	var pos := _get_mouse_3d_pos()
	if pos != Vector3.ZERO:
		brush_node.global_position = pos
		
		# Rotate bridge 
		var base_angle_deg := 0.0
		if player_ref:
			var hit_pos: Vector3 = pos
			var player_pos: Vector3 = player_ref.global_position
			var dir: Vector3 = (hit_pos - player_pos)
			dir.y = 0
			if dir.length() > 0.1:
				base_angle_deg = rad_to_deg(atan2(dir.x, dir.z))
		
		# Explicitly set rotation via degrees
		brush_node.rotation_degrees = Vector3(0, base_angle_deg + brush_rotation_offset, 0)
		brush_node.visible = true
	else:
		brush_node.visible = false
