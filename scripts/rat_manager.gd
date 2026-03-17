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

@export var rat_scene: PackedScene = preload("res://scenes/rat.tscn")
@export var min_cap: int = 40
@export var max_cap: int = 60
@export var start_with_min: bool = true
@export var spawn_radius_min: float = 0.8
@export var spawn_radius_max: float = 2.2
@export var auto_respawn_if_empty: bool = true
@export var rat_spawn_bonus_amount: int = 10
@export var rat_spawn_bonus_radius: float = 2.5
@export var rat_spawn_one_shot: bool = true
@export var min_cap_respawn_cooldown: float = 0.75

var _player: CharacterBody3D = null
var _empty_respawn_triggered: bool = false
var _min_respawn_cooldown: float = 0.0
var _rat_spawn_used: Dictionary = {}

var mode: int = 0: # 0 = COMBAT, 1 = BUILD
	set(new_mode):
		var old_mode := mode
		mode = new_mode
		if mode == 0 and old_mode == 1:
			# Returning from BUILD to COMBAT:
			# carrier rats stay with their object, free rats resume mouse follow
			for rat in rats:
				if not rat.is_carrier:
					rat.is_following_player = true
			mouse_is_down_left = false
			mouse_is_down_right = false
			combat_lmb_down = false
			combat_rmb_down = false
		if mode == 1 and old_mode == 0:
			combat_lmb_down = false
			combat_rmb_down = false
			pass

# Drawing & Blob
var built_positions: Dictionary = {}
var mouse_is_down_left: bool = false
var left_click_start_pos: Vector2 = Vector2(-1, -1)
var is_dragging_left: bool = false
var drag_threshold_squared: float = 100.0 # 10 pixels squared threshold

var mouse_is_down_right: bool = false
var combat_lmb_down: bool = false
var combat_rmb_down: bool = false

# Rats that are currently acting as box carriers
var carrier_rats: Dictionary = {}
# Per-carrier-rat offset from the box center (world-space XZ offset at the time of surrounding)
var carrier_rat_offsets: Dictionary = {}
var last_draw_pos: Vector3 = Vector3(-1000, -1000, -1000)
var is_drawing_line: bool = false
var current_build_y: float = -1000.0

var current_drawn_path: PackedVector3Array = []
var min_point_dist_squared: float = 0.05

# All positions in the most recently issued build command.
var active_build_positions: Array[Vector3] = []

# Vertical offset applied to build positions sampled from the surface.
# Default aligns rat collision bottom with the surface (rat height is 0.15).
@export var build_surface_offset: float = 0.1
@export var build_force_timeout: float = 2.5

const DRAW_MODE_PATH := 0
const DRAW_MODE_CIRCLE := 1

@export_enum("Path", "Circle")
var build_draw_mode: int = DRAW_MODE_CIRCLE

@export var use_wide_brush: bool = false
@export var brush_half_width: float = 0.3
@export var brush_half_width_min: float = 0.1
@export var brush_half_width_max: float = 1.5
@export var brush_half_width_step: float = 0.05

@export var brush_lane_pairs: int = 1
@export var brush_lane_pairs_min: int = 0
@export var brush_lane_pairs_max: int = 4
@export var brush_lane_spacing: float = 0.3

@export var circle_radius: float = 0.5
@export var circle_radius_min: float = 0.25
@export var circle_radius_max: float = 4.0
@export var circle_radius_step: float = 0.25
@export var circle_fill_spacing: float = 0.5

var current_circle_center: Vector3 = Vector3.ZERO
var _build_force_timer: float = 0.0

var grabbed_object: CharacterBody3D = null
var grabbed_object_last_pos: Vector3 = Vector3.ZERO
var rmb_press_screen_pos: Vector2 = Vector2.ZERO

@export var box_drag_lerp_factor: float = 0.008
@export var carrier_min_count: int = 1
@export var carrier_drag_speed_min_mult: float = 0.08
@export var carrier_drag_speed_max_mult: float = 0.5
@export var carrier_drag_speed_curve: float = 2.2
@export var carrier_pick_radius: float = 6.0
@export var object_rotation_step: float = 22.5
@export var smooth_rotation_mode: bool = false
@export var smooth_rotation_speed: float = 90.0
@export var combat_circle_radius: float = 2.5
@export var combat_circle_rotation_speed: float = 2.5
@export var combat_spin_speed: float = 10.0

@export var rats_collide_with_walls: bool = true:
	set(value):
		rats_collide_with_walls = value
		for rat in rats:
			if rat.has_method("set_wall_collision"):
				rat.set_wall_collision(value)

var _is_rotating_left: bool = false
var _is_rotating_right: bool = false
var _hovered_object: Node3D = null

var line_mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh
var line_material: StandardMaterial3D

var unified_shape_combiner: CSGCombiner3D

# ── Blob offsets (sunflower pattern) ──────────────────────────────────────────
const BLOB_RADIUS_BASE: float = 1.8
const BLOB_SPREAD: float = 0.22
var _blob_offsets: Array[Vector3] = []

# ── Combat draw (stream/arc) ──────────────────────────────────────────────────
const STREAM_SPACING: float = 0.42
const DRAW_SAMPLE_DIST: float = 0.2
const MOUSE_TRAIL_MAX: int = 500
var _mouse_trail: Array[Vector3] = []   # continuous mouse position history
var _mouse_trail_last: Vector3 = Vector3.ZERO
var _build_in_progress: bool = false
var _combat_circle_angle: float = 0.0



# ── Neighbor throttle ─────────────────────────────────────────────────────────
const NEIGHBOR_RADIUS: float = 1.1
const NEIGHBOR_TICK: int = 3
var _neighbor_tick: int = 0

# ── Dragging object state (RMB in BUILD) ─────────────────────────────────────
var _rmb_dragging_object: bool = false


func _ready() -> void:
	add_to_group("rat_manager")
	_clamp_caps()

	immediate_mesh = ImmediateMesh.new()
	line_mesh_instance = MeshInstance3D.new()
	
	unified_shape_combiner = CSGCombiner3D.new()
	unified_shape_combiner.use_collision = true
	unified_shape_combiner.collision_layer = 1
	add_child(unified_shape_combiner)
	line_mesh_instance.mesh = immediate_mesh
	
	line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color.WHITE
	line_mesh_instance.material_override = line_material
	
	add_child(line_mesh_instance)

func setup_player(player: CharacterBody3D) -> void:
	_player = player
	if _player and not _player.is_in_group("player"):
		_player.add_to_group("player")
	if start_with_min and rats.is_empty():
		ensure_min_cap()


func _clamp_caps() -> void:
	if max_cap < 0:
		max_cap = 0
	if min_cap < 0:
		min_cap = 0
	if min_cap > max_cap:
		min_cap = max_cap


func get_total_rat_count() -> int:
	var count := 0
	for rat in rats:
		if rat != null:
			count += 1
	return count


func get_max_cap() -> int:
	return max_cap


func get_min_cap() -> int:
	return min_cap


func increase_min_cap(amount: int) -> void:
	if amount <= 0:
		return
	min_cap = clampi(min_cap + amount, 0, max_cap)
	ensure_min_cap()


func restore_to_min(require_empty: bool = false) -> void:
	if require_empty and get_active_rat_count() > 0:
		return
	ensure_min_cap()


func ensure_min_cap() -> void:
	_clamp_caps()
	var total := get_total_rat_count()
	var target := min_cap
	if total >= target:
		return
	var spawn_count := target - total
	_spawn_rats(spawn_count)


func _spawn_rats(count: int) -> void:
	if count <= 0:
		return
	if rat_scene == null:
		push_error("rat_scene is not set in RatManager.")
		return
	var capacity := max_cap - get_total_rat_count()
	if capacity <= 0:
		return
	count = min(count, capacity)

	var parent_node := get_parent()
	if parent_node == null:
		parent_node = self

	var base_pos := global_position
	if _player:
		base_pos = _player.global_position
	var spawns := get_tree().get_nodes_in_group("rat_spawn")
	var spawn_nodes: Array[Node3D] = []
	for s in spawns:
		var n := s as Node3D
		if n != null:
			spawn_nodes.append(n)
	if spawn_nodes.size() > 1 and _player:
		spawn_nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(_player.global_position) < b.global_position.distance_squared_to(_player.global_position)
		)

	for i in range(count):
		var rat := rat_scene.instantiate()
		var angle := randf() * TAU
		var radius := randf_range(spawn_radius_min, spawn_radius_max)
		var spawn_center := base_pos
		if not spawn_nodes.is_empty():
			var idx := i % spawn_nodes.size()
			spawn_center = spawn_nodes[idx].global_position
		rat.position = spawn_center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		rat.player = _player
		parent_node.add_child(rat)
		if _player:
			rat.add_collision_exception_with(_player)
			_player.add_collision_exception_with(rat)
		register_rat(rat)

	build_blob_offsets()


func _spawn_rats_at_center(count: int, center: Vector3) -> void:
	if count <= 0:
		return
	if rat_scene == null:
		push_error("rat_scene is not set in RatManager.")
		return
	var capacity := max_cap - get_total_rat_count()
	if capacity <= 0:
		return
	count = min(count, capacity)

	var parent_node := get_parent()
	if parent_node == null:
		parent_node = self

	for i in range(count):
		var rat := rat_scene.instantiate()
		var angle := randf() * TAU
		var radius := randf_range(spawn_radius_min, spawn_radius_max)
		rat.position = center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		rat.player = _player
		parent_node.add_child(rat)
		if _player:
			rat.add_collision_exception_with(_player)
			_player.add_collision_exception_with(rat)
		register_rat(rat)

	build_blob_offsets()


func _spawn_rats_near_player(count: int) -> void:
	if _player == null:
		return
	_spawn_rats_at_center(count, _player.global_position)


func _get_fallen_rats() -> Array[Rat]:
	var fallen: Array[Rat] = []
	for rat in rats:
		var r := rat as Rat
		if r != null and r.is_fallen:
			fallen.append(r)
	return fallen


func _check_empty_respawn() -> void:
	var active := get_active_rat_count()
	if auto_respawn_if_empty and active == 0:
		if _empty_respawn_triggered:
			return
		_empty_respawn_triggered = true
		_respawn_min_cap_near_player()
	else:
		_empty_respawn_triggered = false

	if active < min_cap and _min_respawn_cooldown <= 0.0:
		_respawn_min_cap_near_player()
		_min_respawn_cooldown = max(0.05, min_cap_respawn_cooldown)


func _respawn_min_cap_near_player() -> void:
	_clamp_caps()
	if _player == null:
		return
	var target := min_cap
	if target <= 0:
		return
	var active := get_active_rat_count()
	var needed := target - active
	if needed <= 0:
		return

	var fallen := _get_fallen_rats()
	for r in fallen:
		if needed <= 0:
			break
		r.force_respawn_near_player()
		needed -= 1

	if needed > 0:
		_spawn_rats_near_player(needed)


func _check_rat_spawn_bonus() -> void:
	if _player == null:
		return
	if rat_spawn_bonus_amount <= 0:
		return
	var spawns := get_tree().get_nodes_in_group("rat_spawn")
	for s in spawns:
		var n := s as Node3D
		if n == null:
			continue
		if rat_spawn_one_shot and _rat_spawn_used.has(n):
			continue
		if n.global_position.distance_to(_player.global_position) > rat_spawn_bonus_radius:
			continue
		_give_rat_spawn_bonus(n.global_position)
		if rat_spawn_one_shot:
			_rat_spawn_used[n] = true


func _give_rat_spawn_bonus(spawn_center: Vector3) -> void:
	var add := rat_spawn_bonus_amount
	var capacity := max_cap - get_total_rat_count()
	if capacity <= 0:
		return
	add = min(add, capacity)

	var fallen := _get_fallen_rats()
	for r in fallen:
		if add <= 0:
			break
		var angle := randf() * TAU
		var radius := randf_range(spawn_radius_min, spawn_radius_max)
		var pos := spawn_center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		r.force_respawn_at_position(pos)
		add -= 1

	if add > 0:
		_spawn_rats_at_center(add, spawn_center)


func _process(delta: float) -> void:
	if _build_force_timer > 0.0:
		_build_force_timer = max(0.0, _build_force_timer - delta)
	if _min_respawn_cooldown > 0.0:
		_min_respawn_cooldown = max(0.0, _min_respawn_cooldown - delta)
	_update_edge_avoidance()
	if orbit_active:
		orbit_timer -= delta
		if orbit_timer <= 0.0:
			deactivate_orbit()

	if wave_active:
		wave_timer -= delta
		if wave_timer <= 0.0:
			wave_active = false
			wave_ended.emit()

	# ── COMBAT mode: rats follow cursor in arc/stream ──
	if mode == 0:
		_update_combat_mouse_follow(delta)
	
	# ── BUILD mode (Ctrl held) ──
	if mode == 1:
		if mouse_is_down_left:
			if not is_dragging_left:
				var current_mouse_pos := get_viewport().get_mouse_position()
				if left_click_start_pos.distance_squared_to(current_mouse_pos) > drag_threshold_squared:
					is_dragging_left = true
			
			if is_dragging_left:
				_process_build_drag()
		
		if _rmb_dragging_object and grabbed_object:
			_process_object_drag()
			if smooth_rotation_mode:
				if _is_rotating_left:
					grabbed_object.rotate_y(deg_to_rad(smooth_rotation_speed * delta))
				if _is_rotating_right:
					grabbed_object.rotate_y(deg_to_rad(-smooth_rotation_speed * delta))



	if mode != 1:
		mouse_is_down_left = false
		mouse_is_down_right = false
		is_drawing_line = false
		current_build_y = -1000.0
		_build_in_progress = _has_build_in_progress()
		if not _build_in_progress:
			active_build_positions.clear()

	_check_formation_sync()
	_check_carrier_arrival()
	_check_travel_anchoring()
	_update_carrier_rat_targets()
	_update_free_rats_follow_player()
	_process_hover()

	# ── Neighbor throttle ──
	_neighbor_tick += 1
	if _neighbor_tick >= NEIGHBOR_TICK:
		_neighbor_tick = 0
		_assign_neighbors()

	# ── Cursor Preview ──
	_update_cursor_preview()
	_check_empty_respawn()
	_check_rat_spawn_bonus()


func _update_edge_avoidance() -> void:
	var enabled := true
	if mode == 1 and (mouse_is_down_left or is_dragging_left):
		enabled = false
	for rat in rats:
		var r := rat as Rat
		if r:
			r.edge_avoidance_enabled = enabled


# ── COMBAT: arc/stream follow ──────────────────────────────────────────────────

func _update_combat_mouse_follow(delta: float) -> void:
	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		return

	# Track mouse position as a trail
	if _mouse_trail.is_empty():
		_mouse_trail.append(mouse_world)
		_mouse_trail_last = mouse_world
	elif mouse_world.distance_to(_mouse_trail_last) >= DRAW_SAMPLE_DIST:
		_mouse_trail.append(mouse_world)
		_mouse_trail_last = mouse_world
		if _mouse_trail.size() > MOUSE_TRAIL_MAX:
			_mouse_trail.pop_front()

	# Collect active rats
	var active: Array[CharacterBody3D] = []
	for rat in rats:
		if not rat.is_carrier and rat.state == rat.State.FOLLOW:
			active.append(rat)

	var count := active.size()
	if count == 0:
		return

	# Apply per-rat spin when RMB is held without LMB
	var spin_speed := 0.0
	if combat_rmb_down and not combat_lmb_down:
		spin_speed = combat_spin_speed
	for rat in rats:
		if rat.state == rat.State.FOLLOW and not rat.is_carrier:
			rat.extra_spin_speed = spin_speed
		else:
			rat.extra_spin_speed = 0.0

	# LMB: circle around cursor
	if combat_lmb_down:
		if combat_rmb_down:
			_combat_circle_angle += combat_circle_rotation_speed * delta
		var angle_step := TAU / float(count)
		for i in range(count):
			var angle := _combat_circle_angle + angle_step * float(i)
			var target := mouse_world + Vector3(cos(angle) * combat_circle_radius, 0.0, sin(angle) * combat_circle_radius)
			target.y = mouse_world.y
			active[i].set_target(target)
		return

	# Need at least 2 points for arc distribution
	if _mouse_trail.size() < 2:
		# Fallback: set all rats to mouse position
		for rat in active:
			rat.set_target(mouse_world)
		return

	# Arc-length parameterization of the trail
	var arc: Array[float] = [0.0]
	for i in range(1, _mouse_trail.size()):
		arc.append(arc[i - 1] + _mouse_trail[i].distance_to(_mouse_trail[i - 1]))
	var total: float = arc[-1]

	# Calculate how much to resemble a blob based on brush size
	var blob_blend := 0.0
	var blob_scale := 1.0
	if build_draw_mode == DRAW_MODE_CIRCLE:
		blob_blend = clampf((circle_radius - circle_radius_min) / max(0.1, circle_radius_max - circle_radius_min), 0.0, 1.0)
		blob_scale = circle_radius / 0.5
	elif build_draw_mode == DRAW_MODE_PATH:
		blob_blend = clampf(float(brush_lane_pairs - brush_lane_pairs_min) / maxf(1.0, float(brush_lane_pairs_max - brush_lane_pairs_min)), 0.0, 1.0)
		var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
		blob_scale = float(1 + pairs * 2) / 2.5

	if _blob_offsets.size() != count:
		build_blob_offsets()

	for i in range(count):
		# 1) Calculate Arc/Stream Target
		var dist_back := float(i) * STREAM_SPACING
		var arc_pos := total - dist_back

		var t_stream: Vector3
		var lateral_dir := Vector3.ZERO
		
		if arc_pos <= 0.0:
			t_stream = _mouse_trail[0]
			if _mouse_trail.size() >= 2:
				var dir := _mouse_trail[1] - _mouse_trail[0]
				dir.y = 0.0
				lateral_dir = dir.normalized().cross(Vector3.UP).normalized()
		else:
			t_stream = _arc_sample(_mouse_trail, arc, arc_pos)
			
			var lo := 0
			var hi := arc.size() - 1
			while lo < hi - 1:
				var mid := (lo + hi) / 2
				if arc[mid] <= arc_pos:
					lo = mid
				else:
					hi = mid
			
			var dir := _mouse_trail[hi] - _mouse_trail[lo]
			dir.y = 0.0
			lateral_dir = dir.normalized().cross(Vector3.UP).normalized()

		# Apply brush width to arc target
		if lateral_dir != Vector3.ZERO:
			if build_draw_mode == DRAW_MODE_PATH:
				var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
				if pairs > 0:
					var lane_count := 1 + pairs * 2
					var center_index := float(lane_count - 1) / 2.0
					var lane_index := i % lane_count
					var factor := float(lane_index) - center_index
					t_stream += lateral_dir * (brush_lane_spacing / 1.5) * factor
			elif build_draw_mode == DRAW_MODE_CIRCLE:
				var pseudo_rand := fmod(float(active[i].get_instance_id()) * 0.6180339887, 2.0) - 1.0
				t_stream += lateral_dir * (pseudo_rand * circle_radius / 1.5)

		# 2) Calculate Blob Target
		var t_blob := mouse_world
		if i < _blob_offsets.size():
			t_blob += _blob_offsets[i] * blob_scale
		t_blob.y = mouse_world.y

		# 3) Blend based on brush size
		var final_target = t_stream.lerp(t_blob, blob_blend)
		active[i].set_target(final_target)

func _update_free_rats_follow_player() -> void:
	if mode != 1:
		return
	if grabbed_object == null:
		return
	if mouse_is_down_left or is_dragging_left:
		return

	var player_node: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player_node == null:
		return

	var active: Array[CharacterBody3D] = []
	for rat in rats:
		if rat.is_carrier:
			continue
		if rat.is_anchored:
			continue
		if rat.state != rat.State.FOLLOW:
			continue
		active.append(rat)

	var count := active.size()
	if count == 0:
		return

	if _blob_offsets.size() != rats.size():
		build_blob_offsets()

	for i in range(count):
		var target := player_node.global_position
		if i < _blob_offsets.size():
			target += _blob_offsets[i]
		target.y = player_node.global_position.y
		active[i].set_target(target)


func _arc_sample(path: Array, arc: Array, want: float) -> Vector3:
	var lo := 0
	var hi := arc.size() - 1
	while lo < hi - 1:
		var mid := (lo + hi) / 2
		if arc[mid] <= want:
			lo = mid
		else:
			hi = mid
	var seg: float = arc[hi] - arc[lo]
	if seg < 0.0001:
		return path[lo]
	var t: float = (want - arc[lo]) / seg
	return (path[lo] as Vector3).lerp(path[hi] as Vector3, t)


func build_blob_offsets() -> void:
	_blob_offsets.clear()
	var count := rats.size()
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i in range(count):
		var r := BLOB_RADIUS_BASE * sqrt(float(i + 1) / float(count)) + BLOB_SPREAD * float(i) * 0.04
		var a := golden_angle * float(i)
		_blob_offsets.append(Vector3(cos(a) * r, 0.0, sin(a) * r))


func _assign_neighbors() -> void:
	var count := rats.size()
	for i in range(count):
		var nb: Array = []
		var pos_i := rats[i].global_position
		for j in range(count):
			if i == j:
				continue
			if pos_i.distance_to(rats[j].global_position) < NEIGHBOR_RADIUS:
				nb.append(rats[j])
		rats[i].set_neighbors(nb)


func _has_build_in_progress() -> bool:
	for rat in rats:
		if rat.state == rat.State.TRAVEL_TO_BUILD or rat.state == rat.State.WAITING_FOR_FORMATION:
			return true
	return false


func _has_static_rats() -> bool:
	for rat in rats:
		if rat.state == rat.State.STATIC:
			return true
	return false


func _cancel_active_build_orders() -> void:
	for rat in rats:
		if rat.state == rat.State.TRAVEL_TO_BUILD or rat.state == rat.State.WAITING_FOR_FORMATION:
			rat.release_rat(true)


# ── Mouse → world raycast ─────────────────────────────────────────────────────

func _mouse_to_world() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO

	var mp := get_viewport().get_mouse_position()
	var ro := cam.project_ray_origin(mp)
	var rd := cam.project_ray_normal(mp)

	# Physics hit
	var ss := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ro, ro + rd * 1000.0)
	query.collision_mask = 0xFFFFFFFF
	var hit := ss.intersect_ray(query)
	if hit:
		return hit.position

	# Fallback plane at player Y
	var player_ref: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player_ref:
		var py: float = player_ref.global_position.y
		var denom := Vector3.UP.dot(rd)
		if abs(denom) > 0.0001:
			var tt := (py - Vector3.UP.dot(ro)) / denom
			if tt > 0.0:
				return ro + rd * tt

	return Vector3.ZERO


# ── Anchoring, formation, carrier ─────────────────────────────────────────────

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
	if not _has_build_in_progress():
		return
	if _build_force_timer <= 0.0:
		for rat in rats:
			if rat.state == rat.State.TRAVEL_TO_BUILD:
				rat.state = rat.State.WAITING_FOR_FORMATION
				rat.global_position = rat.build_target
				rat.velocity = Vector3.ZERO

	var any_traveling = false
	var any_waiting = false
	
	for rat in rats:
		if rat.state == rat.State.TRAVEL_TO_BUILD:
			any_traveling = true
			break
		elif rat.state == rat.State.WAITING_FOR_FORMATION:
			any_waiting = true
			
	if not any_traveling and any_waiting:
		for rat in rats:
			if rat.state == rat.State.WAITING_FOR_FORMATION:
				rat.activate_physics()
		_form_unified_mesh()
		_build_in_progress = false


func _form_unified_mesh() -> void:
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	var static_rats: Array = []
	for rat in rats:
		if carrier_rats.has(rat):
			continue
		if rat.state == rat.State.STATIC:
			static_rats.append(rat)
			rat.hide_visuals()
			rat.set_collision_layer_value(1, false)

	if static_rats.is_empty():
		return

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.30, 0.18)
	
	var height = 0.4
	var radius = 0.35
	var y_offset = -0.3

	var rat_positions = []
	for rat in static_rats:
		rat_positions.append(rat.global_position)
		
		var cyl = CSGCylinder3D.new()
		cyl.radius = radius
		cyl.height = height
		cyl.sides = 12
		cyl.global_position = rat.global_position + Vector3(0, y_offset, 0)
		cyl.material = mat
		unified_shape_combiner.add_child(cyl)

	var connection_threshold = 1.3
	var max_connections_per_rat = 4

	for i in range(rat_positions.size()):
		var pos_a = rat_positions[i]
		
		var neighbors = []
		for j in range(i + 1, rat_positions.size()):
			var pos_b = rat_positions[j]
			var dist = pos_a.distance_to(pos_b)
			if dist < connection_threshold:
				neighbors.append({"index": j, "dist": dist})
		
		neighbors.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		var connections_made = 0
		for nb in neighbors:
			if connections_made >= max_connections_per_rat:
				break
			
			var dist = nb["dist"]
			var pos_b = rat_positions[nb["index"]]
			
			var box = CSGBox3D.new()
			box.size = Vector3(radius * 2.0, height, dist)
			var center = (pos_a + pos_b) / 2.0
			box.global_position = center + Vector3(0, y_offset, 0)
			
			if dist > 0.001:
				var forward = (pos_b - pos_a).normalized()
				var up = Vector3.UP
				if abs(forward.y) > 0.99:
					up = Vector3.RIGHT
				box.look_at_from_position(box.global_position, box.global_position + forward, up)
			
			box.material = mat
			unified_shape_combiner.add_child(box)
			connections_made += 1


# ── Input handling ────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if wave_pending and event is InputEventMouseButton:
		var mb_wave := event as InputEventMouseButton
		if mb_wave.button_index == MOUSE_BUTTON_LEFT and mb_wave.pressed:
			_fire_wave_at_mouse(mb_wave.position)
			wave_pending = false
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		# Scroll wheel controls brush/arc width in both modes
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
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
		
		# ── BUILD mode: LMB = drawing structures ──
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mode == 1:
				if mb.pressed:
					mouse_is_down_left = true
					left_click_start_pos = mb.position
					is_dragging_left = false
					current_drawn_path.clear()
					current_build_y = -1000.0
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
			elif mode == 0:
				combat_lmb_down = mb.pressed
				get_viewport().set_input_as_handled()
			return
			
		# ── BUILD mode: RMB = object interaction (surround / grab / release) ──
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mode == 1:
				if mb.pressed:
					rmb_press_screen_pos = mb.position
					if grabbed_object != null:
						# Object already grabbed — start/resume dragging
						_rmb_dragging_object = true
						get_viewport().set_input_as_handled()
						return

					# No object currently grabbed — raycast to find one
					var camera_m: Camera3D = get_viewport().get_camera_3d()
					var ray_origin_m: Vector3 = camera_m.project_ray_origin(mb.position)
					var ray_dir_m: Vector3 = camera_m.project_ray_normal(mb.position)
					var space_state_m := camera_m.get_world_3d().direct_space_state
					var query_m := PhysicsRayQueryParameters3D.create(ray_origin_m, ray_origin_m + ray_dir_m * 1000.0)
					var hit_m := space_state_m.intersect_ray(query_m)

					if hit_m:
						var obj = hit_m.collider
						if obj is box or obj is turret or obj is hitscan_turret:
							_rmb_dragging_object = true
							if not obj.is_surrounded:
								_surround_object_with_rats(obj)
							grabbed_object = obj
							grabbed_object_last_pos = obj.global_position
							get_viewport().set_input_as_handled()
							return

					_rmb_dragging_object = false
				else:
					# RMB released - drop object and return carriers immediately
					_rmb_dragging_object = false
					if grabbed_object != null:
						_release_object_carriers(grabbed_object)
						grabbed_object = null
						grabbed_object_last_pos = Vector3.ZERO
				get_viewport().set_input_as_handled()
			elif mode == 0:
				combat_rmb_down = mb.pressed
				get_viewport().set_input_as_handled()
			return

		# Side Mouse Buttons: Rotate carried object
		if mb.button_index == MOUSE_BUTTON_XBUTTON1:
			_is_rotating_left = mb.pressed
			if _is_rotating_left and grabbed_object and not smooth_rotation_mode:
				grabbed_object.rotate_y(deg_to_rad(object_rotation_step))
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_XBUTTON2:
			_is_rotating_right = mb.pressed
			if _is_rotating_right and grabbed_object and not smooth_rotation_mode:
				grabbed_object.rotate_y(deg_to_rad(-object_rotation_step))
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
	if rat.has_method("set_wall_collision"):
		rat.set_wall_collision(rats_collide_with_walls)


func get_active_rat_count() -> int:
	var count := 0
	for rat in rats:
		if rat == null:
			continue
		var r := rat as Rat
		if r != null and r.is_fallen:
			continue
		count += 1
	return count


func activate_orbit() -> void:
	if orbit_active:
		deactivate_orbit()
		return

	wave_pending = false

	orbit_active = true
	orbit_timer = orbit_duration
	var count := rats.size()
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
	if orbit_active:
		deactivate_orbit()
	wave_pending = true


func _fire_wave_at_mouse(screen_pos: Vector2) -> void:
	wave_active = true
	wave_timer = wave_duration

	var player_node: Node3D = rats[0].player
	var player_pos: Vector3 = player_node.global_position

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
	# Release any grabbed object and its carrier rats first
	if grabbed_object != null:
		_release_object_carriers(grabbed_object)
		grabbed_object = null
		grabbed_object_last_pos = Vector3.ZERO
		_rmb_dragging_object = false

	active_build_positions.clear()
	built_positions.clear()
	carrier_rats.clear()
	carrier_rat_offsets.clear()
	
	# Destroy the unified mesh
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	for rat in rats:
		rat.release_rat(true)
	# Reset drawing state
	mouse_is_down_left = false
	is_dragging_left = false
	mouse_is_down_right = false
	_rmb_dragging_object = false
	is_drawing_line = false
	current_build_y = -1000.0
	current_drawn_path.clear()
	immediate_mesh.clear_surfaces()
	for rat in rats:
		rat.is_following_player = true
		rat.is_carrier = false

	_respawn_min_cap_near_player()


func _process_hover() -> void:
	if mode != 1:
		if _hovered_object:
			if _hovered_object.has_method("set_highlight"):
				_hovered_object.set_highlight(false)
			_hovered_object = null
		return

	var camera := get_viewport().get_camera_3d()
	if not camera: return
	
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collision_mask = 4 
	
	var hit := space_state.intersect_ray(query)
	var new_hover: Node3D = null
	
	if hit:
		var obj = hit.collider
		if obj.has_method("set_highlight"):
			new_hover = obj
			
	if new_hover != _hovered_object:
		if _hovered_object and _hovered_object.has_method("set_highlight"):
			_hovered_object.set_highlight(false)
		
		_hovered_object = new_hover
		
		if _hovered_object:
			_hovered_object.set_highlight(true)


func _get_mouse_ground_hit() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	return space_state.intersect_ray(query)


func _get_mouse_pos_at_y(y: float) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) < 0.0001:
		return Vector3.ZERO
	var t := (y - ray_origin.y) / ray_dir.y
	return ray_origin + ray_dir * t


func _process_build_drag() -> void:
	var hit := _get_mouse_ground_hit()

	var raw_pos: Vector3
	if hit:
		raw_pos = hit.position + hit.normal * build_surface_offset
		if current_build_y <= -500.0:
			current_build_y = raw_pos.y
		raw_pos.y = current_build_y
	elif current_build_y > -500.0:
		var fallback := _get_mouse_pos_at_y(current_build_y)
		if fallback == Vector3.ZERO:
			return
		raw_pos = fallback
	else:
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
	
	var offset := Vector3(0, 0.1, 0)

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for pos in current_drawn_path:
		immediate_mesh.surface_add_vertex(pos + offset)
	immediate_mesh.surface_add_vertex(end_pos + offset)
	immediate_mesh.surface_end()

	if not use_wide_brush:
		return

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

	var end_dir: Vector3 = end_pos - current_drawn_path[count - 1]
	end_dir.y = 0.0
	if end_dir.length() < 0.001:
		end_dir = Vector3.FORWARD
	else:
		end_dir = end_dir.normalized()
	var end_lateral := end_dir.cross(Vector3.UP).normalized()

	var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
	if pairs <= 0:
		return

	var lane_count := 1 + pairs * 2
	var center_index := float(lane_count - 1) / 2.0

	for lane_index in range(lane_count):
		if lane_index == int(center_index):
			continue

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
			var off := Vector3(float(ix) * spacing, 0.0, float(iz) * spacing)
			if off.x * off.x + off.z * off.z <= radius * radius + 0.001:
				positions.append(center + off)
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
			var key := Vector2i(int(round(p.x / spacing)), int(round(p.z / spacing)))
			if not used.has(key):
				used[key] = true
				positions.append(p)

	return positions


# ── Brush UI Preview ─────────────────────────────────────────────────────────

func _update_cursor_preview() -> void:
	# Ignore if we are actively drawing a path in BUILD mode
	if mode == 1 and mouse_is_down_left:
		return

	var player_node: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var hit: Dictionary = _get_mouse_ground_hit()
	var raw_pos: Vector3
	
	if hit:
		raw_pos = hit.position + hit.normal * build_surface_offset
		if mode == 1:
			if current_build_y <= -500.0:
				current_build_y = raw_pos.y
			raw_pos.y = current_build_y
		else:
			# In combat mode, follow ground Y or fallback to player Y
			if player_node:
				raw_pos.y = player_node.global_position.y
	elif mode == 1 and current_build_y > -500.0:
		var fallback := _get_mouse_pos_at_y(current_build_y)
		if fallback == Vector3.ZERO:
			immediate_mesh.clear_surfaces()
			return
		raw_pos = fallback
	elif mode == 0 and player_node:
		# Combat fallback
		var fallback := _get_mouse_pos_at_y(player_node.global_position.y)
		if fallback == Vector3.ZERO:
			immediate_mesh.clear_surfaces()
			return
		raw_pos = fallback
	else:
		immediate_mesh.clear_surfaces()
		return

	if build_draw_mode == DRAW_MODE_CIRCLE:
		current_circle_center = raw_pos
		var old_path = current_drawn_path.duplicate()
		current_drawn_path.clear()
		_update_circle_preview(!hit.is_empty() if mode == 1 else false)
		current_drawn_path = old_path
		
	elif build_draw_mode == DRAW_MODE_PATH:
		var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
		if pairs <= 0:
			immediate_mesh.clear_surfaces()
			return

		var lane_count := 1 + pairs * 2
		var width := float(lane_count - 1) * brush_lane_spacing
		
		# Determine lateral direction
		var lateral := Vector3.RIGHT
		if mode == 1 and current_drawn_path.size() >= 2:
			var dir: Vector3 = current_drawn_path[-1] - current_drawn_path[-2]
			dir.y = 0.0
			if dir.length() > 0.001:
				lateral = dir.normalized().cross(Vector3.UP).normalized()
				
		immediate_mesh.clear_surfaces()
		if line_material:
			line_material.albedo_color = Color.WHITE
		
		var offset := Vector3(0, 0.1, 0)
		immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		immediate_mesh.surface_add_vertex(raw_pos - lateral * (width / 2.0) + offset)
		immediate_mesh.surface_add_vertex(raw_pos + lateral * (width / 2.0) + offset)
		immediate_mesh.surface_end()


func _update_circle_preview(invalid_surface: bool = false) -> void:
	immediate_mesh.clear_surfaces()

	var center := current_circle_center
	var path_for_preview := current_drawn_path
	if path_for_preview.is_empty():
		path_for_preview = PackedVector3Array()
		path_for_preview.append(center)

	var fill_positions := _compute_circle_path_fill_positions(path_for_preview)
	var required := fill_positions.size()
	var total_rats := 0
	for rat in rats:
		if not rat.is_carrier:
			total_rats += 1
	var enough_rats := total_rats >= required

	if line_material:
		if invalid_surface:
			line_material.albedo_color = Color(1, 0, 0)
		else:
			line_material.albedo_color = Color.WHITE if enough_rats else Color(1, 0, 0)

	var segments := 32
	var offset := Vector3(0, 0.1, 0)
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(segments + 1):
		var t := float(i) / float(segments) * TAU
		var x := cos(t) * circle_radius
		var z := sin(t) * circle_radius
		immediate_mesh.surface_add_vertex(center + Vector3(x, 0, z) + offset)
	immediate_mesh.surface_end()

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

	built_positions.clear()
	if not _has_static_rats():
		for child in unified_shape_combiner.get_children():
			child.queue_free()
	_cancel_active_build_orders()

	var available_rats: Array = _get_available_follow_rats()

	var count: int = min(available_rats.size(), fill_positions.size())
	active_build_positions.clear()
	for i in range(count):
		var rat = available_rats[i]
		var pos = fill_positions[i]
		rat.build_at(pos)
		active_build_positions.append(pos)
	if count > 0:
		_build_force_timer = max(0.1, build_force_timeout)


func _distribute_rats_on_path() -> void:
	if current_drawn_path.size() < 2:
		return
		
	var path_length: float = 0.0
	var segs: Array[float] = []
	for i in range(1, current_drawn_path.size()):
		var segment_len = current_drawn_path[i-1].distance_to(current_drawn_path[i])
		path_length += segment_len
		segs.append(segment_len)
		
	built_positions.clear()
	if not _has_static_rats():
		for child in unified_shape_combiner.get_children():
			child.queue_free()

	_cancel_active_build_orders()
		
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
			var dir_single := (current_drawn_path[1] - current_drawn_path[0])
			dir_single.y = 0.0
			if dir_single.length() < 0.001:
				dir_single = Vector3.FORWARD
			else:
				dir_single = dir_single.normalized()
			var lateral_single := dir_single.cross(Vector3.UP).normalized() * brush_half_width
			single_pos = current_drawn_path[0]
		available_rats[0].build_at(single_pos)
		return
		
	var dist_between_rats = path_length / float(rat_count - 1)
	var current_dist_on_path: float = 0.0
	
	for i in range(rat_count):
		if i == 0:
			var start_pos := current_drawn_path[0]
			if use_wide_brush and rat_count > 2:
				var lane_idx := 0
				start_pos = current_drawn_path[0]
			available_rats[0].build_at(start_pos)
			continue
		elif i == rat_count - 1:
			var end_pos := current_drawn_path[-1]
			if use_wide_brush and rat_count > 2:
				end_pos = current_drawn_path[-1]
			available_rats[i].build_at(end_pos)
			continue
			
		var target_dist = i * dist_between_rats
		
		var accum: float = 0.0
		var segment_idx: int = 0
		var segment_start: float = 0.0
		
		for j in range(segs.size()):
			if accum + segs[j] >= target_dist:
				segment_idx = j
				segment_start = accum
				break
			accum += segs[j]
			
		var segment_t = (target_dist - segment_start) / max(0.0001, segs[segment_idx])
		var point_a: Vector3 = current_drawn_path[segment_idx]
		var point_b: Vector3 = current_drawn_path[segment_idx + 1]
		var interp_pos = point_a.lerp(point_b, segment_t)
		
		if use_wide_brush:
			var dir := point_b - point_a
			dir.y = 0.0
			if dir.length() < 0.001:
				dir = Vector3.FORWARD
			else:
				dir = dir.normalized()
			var lateral_dir := dir.cross(Vector3.UP).normalized()

			var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
			if pairs > 0:
				var lane_count := 1 + pairs * 2
				var center_index := float(lane_count - 1) / 2.0
				var lane_index := i % lane_count
				var factor := float(lane_index) - center_index
				interp_pos += lateral_dir * brush_lane_spacing * factor

		available_rats[i].build_at(interp_pos)
	if rat_count > 0:
		_build_force_timer = max(0.1, build_force_timeout)


func _send_horde_to_point() -> void:
	var hit := _get_mouse_ground_hit()
	if not hit:
		return
		
	var target_pos: Vector3 = hit.position
	target_pos.x = snapped(target_pos.x, 0.5)
	target_pos.y = hit.position.y
	target_pos.z = snapped(target_pos.z, 0.5)

	built_positions.clear()
	if not _has_static_rats():
		for child in unified_shape_combiner.get_children():
			child.queue_free()

	_cancel_active_build_orders()

	var available_rats: Array = []
	for rat in rats:
		if rat.state == rat.State.FOLLOW and not rat.is_carrier:
			available_rats.append(rat)
			
	var count = available_rats.size()
	if count == 0:
		return

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
	if count > 0:
		_build_force_timer = max(0.1, build_force_timeout)


func _surround_object_with_rats(obj: CharacterBody3D) -> void:
	var center: Vector3 = obj.global_position

	var available_rats: Array[CharacterBody3D] = _get_nearest_available_rats(center)

	var count: int = available_rats.size()
	if count == 0:
		return

	var obj_max_extent := 0.5
	var shape_owner_id := obj.shape_find_owner(0)
	if shape_owner_id != -1:
		var shape_owner := obj.shape_owner_get_owner(shape_owner_id) as CollisionShape3D
		if shape_owner and shape_owner.shape:
			var aabb := shape_owner.shape.get_debug_mesh().get_aabb()
			var scl := obj.global_transform.basis.get_scale()
			obj_max_extent = maxf(aabb.size.x * scl.x, aabb.size.z * scl.z) * 0.5

	# Rat count is driven by current brush thickness
	var total_count: int = rats.size()
	var desired_carriers: int = _get_brush_desired_carriers(total_count)
	var needed: int = clampi(desired_carriers, 1, count)
	
	if needed <= 0:
		return

	# Make radius just outside the object
	var ring_radius := obj_max_extent + 0.3

	obj.get("carrier_rats").clear()
	obj.set("carrier_available_max", count)
	obj.set("carrier_brush_desired", desired_carriers)

	for i in range(needed):
		var angle := (TAU / needed) * i
		var local_offset := Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)
		var world_pos := _carrier_offset_world_pos(obj.global_transform, local_offset)
		var r: CharacterBody3D = available_rats[i] # already sorted by proximity
		
		r.state = r.State.FOLLOW
		r.is_following_player = false
		r.follow_offset = Vector3.ZERO
		r.blob_target = world_pos
		r.set_target(world_pos)
		r.is_carrier = true
		obj.get("carrier_rats").append(r)
		carrier_rat_offsets[r] = local_offset

	obj.set("is_surrounded", false)

	if not obj.object_reset.is_connected(_on_object_reset):
		obj.object_reset.connect(_on_object_reset.bind(obj))


func _on_object_reset(obj: CharacterBody3D) -> void:
	_release_object_carriers(obj)
	if grabbed_object == obj:
		grabbed_object = null
		grabbed_object_last_pos = Vector3.ZERO
		_rmb_dragging_object = false


func _check_carrier_arrival() -> void:
	if grabbed_object == null or grabbed_object.get("is_surrounded"):
		return
	var snap_dist_sq := 5.5 * 5.5
	for r in grabbed_object.get("carrier_rats"):
		if r == null:
			continue
		var flat_pos := Vector2(r.global_position.x, r.global_position.z)
		var flat_target := Vector2(r.blob_target.x, r.blob_target.z)
		if flat_pos.distance_squared_to(flat_target) <= snap_dist_sq:
			r.global_position = Vector3(r.blob_target.x, r.global_position.y, r.blob_target.z)
			r.velocity = Vector3.ZERO

	var arrival_dist_sq := 0.05 * 0.05
	for r in grabbed_object.get("carrier_rats"):
		if r == null:
			continue
		var flat_pos := Vector2(r.global_position.x, r.global_position.z)
		var flat_target := Vector2(r.blob_target.x, r.blob_target.z)
		if flat_pos.distance_squared_to(flat_target) > arrival_dist_sq:
			return
	grabbed_object.set("is_surrounded", true)


func _process_object_drag() -> void:
	if grabbed_object == null:
		return

	if not grabbed_object.get("is_surrounded"):
		return

	var hit := _get_mouse_ground_hit()
	if not hit:
		return

	var current_pos: Vector3 = grabbed_object.global_position
	var target_pos: Vector3 = hit.position
	target_pos.y = current_pos.y

	var carrier_count: int = grabbed_object.get("carrier_rats").size()
	var carrier_max_val: Variant = grabbed_object.get("carrier_available_max")
	var carrier_max: int = 1
	if carrier_max_val != null:
		carrier_max = int(carrier_max_val)
	if carrier_max <= 0:
		carrier_max = max(1, carrier_count)
	var carrier_desired_val: Variant = grabbed_object.get("carrier_brush_desired")
	var carrier_desired: int = carrier_max
	if carrier_desired_val != null:
		carrier_desired = int(carrier_desired_val)
	if carrier_desired <= 0:
		carrier_desired = max(1, carrier_max)

	var speed_t: float = 0.0
	if carrier_desired > 1:
		speed_t = clampf(float(carrier_count - 1) / float(carrier_desired - 1), 0.0, 1.0)
	var curved_t: float = pow(speed_t, carrier_drag_speed_curve)
	var speed_mult: float = lerpf(carrier_drag_speed_min_mult, carrier_drag_speed_max_mult, curved_t)
	var lerp_factor: float = clampf(box_drag_lerp_factor * speed_mult, 0.0, 1.0)
	var new_pos: Vector3 = current_pos.lerp(target_pos, lerp_factor)
	grabbed_object.global_position = new_pos


func _get_brush_ratio(value: float, min_v: float, max_v: float) -> float:
	if max_v <= min_v:
		return 0.0
	return clampf((value - min_v) / (max_v - min_v), 0.0, 1.0)


func _get_brush_thickness_t() -> float:
	if build_draw_mode == DRAW_MODE_CIRCLE:
		return _get_brush_ratio(circle_radius, circle_radius_min, circle_radius_max)
	if use_wide_brush:
		return _get_brush_ratio(float(brush_lane_pairs), float(brush_lane_pairs_min), float(brush_lane_pairs_max))
	return _get_brush_ratio(brush_half_width, brush_half_width_min, brush_half_width_max)


func _get_brush_desired_carriers(total_count: int) -> int:
	if total_count <= 0:
		return 0
	if build_draw_mode == DRAW_MODE_PATH and use_wide_brush:
		var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
		var lane_count := 1 + pairs * 2
		return clampi(lane_count, 1, total_count)
	var t: float = _get_brush_thickness_t()
	var min_c: int = clampi(carrier_min_count, 1, total_count)
	var desired: int = int(round(lerpf(float(min_c), float(total_count), t)))
	return clampi(desired, 1, total_count)


func _get_nearest_available_rats(center: Vector3) -> Array[CharacterBody3D]:
	var nearby: Array[CharacterBody3D] = []
	var others: Array[CharacterBody3D] = []
	var radius_sq := carrier_pick_radius * carrier_pick_radius

	for rat in rats:
		if rat.is_carrier:
			continue
		if rat.is_anchored:
			continue
		if rat.state == rat.State.STATIC or rat.state == rat.State.WAITING_FOR_FORMATION:
			continue
		if rat.state == rat.State.TRAVEL_TO_BUILD:
			continue
		var dist_sq := rat.global_position.distance_squared_to(center)
		if dist_sq <= radius_sq:
			nearby.append(rat)
		else:
			others.append(rat)

	# Prefer rats already near the object; if not enough, allow other free rats.
	nearby.sort_custom(func(a, b): return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
	others.sort_custom(func(a, b): return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))

	var result: Array[CharacterBody3D] = []
	result.append_array(nearby)
	result.append_array(others)
	return result


func _update_carrier_rat_targets() -> void:
	if grabbed_object == null or not grabbed_object.get("is_surrounded"):
		return
	var obj_transform: Transform3D = grabbed_object.global_transform
	for r in grabbed_object.get("carrier_rats"):
		if r and carrier_rat_offsets.has(r):
			var target_pos: Vector3 = _carrier_offset_world_pos(obj_transform, carrier_rat_offsets[r] as Vector3)
			r.blob_target = target_pos
			r.set_target(target_pos)


func _carrier_offset_world_pos(obj_transform: Transform3D, local_offset: Vector3) -> Vector3:
	# Apply rotation only; local_offset is already in world units.
	var rot_basis := obj_transform.basis.orthonormalized()
	return obj_transform.origin + rot_basis * local_offset


func _release_object_carriers(obj: CharacterBody3D) -> void:
	if obj == null:
		return

	for r in obj.get("carrier_rats"):
		if r:
			r.is_carrier = false
			r.is_following_player = true
			r.release_rat()
			if carrier_rats.has(r):
				carrier_rats.erase(r)
			carrier_rat_offsets.erase(r)
	obj.get("carrier_rats").clear()
	obj.set("is_surrounded", false)


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
