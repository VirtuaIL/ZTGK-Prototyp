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
@export var start_with_min: bool = true
@export var spawn_radius_min: float = 0.8
@export var spawn_radius_max: float = 2.2
@export var auto_respawn_if_empty: bool = true
@export var rat_spawn_bonus_amount: int = 10
@export var rat_spawn_bonus_radius: float = 2.5
@export var rat_spawn_one_shot: bool = true
@export var min_cap_respawn_cooldown: float = 0.75
@export var rat_auto_respawn_enabled: bool = false

var _player: CharacterBody3D = null
var _empty_respawn_triggered: bool = false
var _min_respawn_cooldown: float = 0.0
var _rat_spawn_used: Dictionary = {}

var mode: int = 1 # Always BUILD-like unified mode

# Drawing & Blob
var built_positions: Dictionary = {}
var mouse_is_down_left: bool = false
var left_click_start_pos: Vector2 = Vector2(-1, -1)
var is_dragging_left: bool = false
var drag_threshold_squared: float = 100.0 # 10 pixels squared threshold
var _drawing_attack_path: bool = false

var mouse_is_down_right: bool = false
var combat_rmb_down: bool = false

# LMB unified: true when LMB started on a movable object (drag mode), false = build mode
var _lmb_is_object_drag: bool = false

# Rats that are currently acting as box carriers
var carrier_rats: Dictionary = {}
# Per-carrier-rat offset from the box center (world-space XZ offset at the time of surrounding)
var carrier_rat_offsets: Dictionary = {}
var last_draw_pos: Vector3 = Vector3(-1000, -1000, -1000)
var is_drawing_line: bool = false
var current_build_y: float = -1000.0

var current_drawn_path: PackedVector3Array = []
var _current_drawn_path_length: float = 0.0
@export var attack_path_length_max: float = 25.0  # thinnest brush
@export var attack_path_length_min: float = 8.0   # widest brush
var min_point_dist_squared: float = 0.05
var _last_build_pos: Vector3 = Vector3.ZERO
var _has_last_build_pos: bool = false

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
@export var brush_lane_spacing: float = 0.5

@export var circle_radius: float = 0.5
@export var circle_radius_min: float = 0.25
@export var circle_radius_max: float = 4.0
@export var circle_radius_step: float = 0.25
@export var circle_fill_spacing: float = 0.8

var current_circle_center: Vector3 = Vector3.ZERO
var _build_force_timer: float = 0.0

var grabbed_object: CharacterBody3D = null
var grabbed_object_last_pos: Vector3 = Vector3.ZERO
var rmb_press_screen_pos: Vector2 = Vector2.ZERO

@export var box_drag_lerp_factor: float = 0.012
@export var box_drag_speed: float = 4.0
@export var box_drag_max_radius: float = 4.0
@export var carrier_min_count: int = 1
@export var carrier_drag_speed_min_mult: float = 0.08
@export var carrier_drag_speed_max_mult: float = 0.5
@export var carrier_drag_speed_curve: float = 2.2
@export var carrier_pick_radius: float = 6.0
@export var object_rotation_step: float = 22.5
@export var combat_circle_radius: float = 2.5
@export var combat_circle_rotation_speed: float = 7.0
@export var capstan_cursor_snap_radius: float = 6.0
@export var capstan_cursor_ring_radius: float = 8.0
@export var capstan_cursor_rotation_scale: float = 0.6
@export var capstan_rat_required_radius: float = 2.4
@export var cursor_trail_max_length: float = 9.0
@export var cursor_turn_reset_angle: float = 120.0
@export var cursor_turn_reset_distance: float = 1.0
@export var carry_player_enabled: bool = true
@export var carry_player_height_offset: float = 0.6
@export var cursor_hint_duration: float = 3.2

var _cursor_hint_layer: CanvasLayer = null
var _cursor_hint_label: Label = null
var _cursor_hint_timer: float = 0.0
var _cursor_info_layer: CanvasLayer = null
var _cursor_info_label: Label = null

@export var rats_collide_with_walls: bool = true:
	set(value):
		rats_collide_with_walls = value
		for rat in rats:
			if rat.has_method("set_wall_collision"):
				rat.set_wall_collision(value)

var _hovered_object: Node3D = null
var _cursor_capstan: Capstan = null
var _cursor_capstan_last_angle: float = 0.0
var _cursor_capstan_has_angle: bool = false
var _capstan_collision_exceptions: Dictionary = {}

var line_mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh
var line_material: StandardMaterial3D

var unified_shape_combiner: CSGCombiner3D

# ── Blob offsets (sunflower pattern) ──────────────────────────────────────────
const BLOB_RADIUS_BASE: float = 2.6
const BLOB_SPREAD: float = 0.3
var _blob_offsets: Array[Vector3] = []

# ── Dynamic formation ─────────────────────────────────────────────────────────
var _dyn_offsets: Dictionary = {}         # rat instance_id → Vector3 (normalized offset, max=1)
var _dyn_base_radius: float = 2.0        # base radius of formation when captured
@export var formation_scale: float = 1.0
@export var formation_scale_min: float = 0.3
@export var formation_scale_max: float = 5.0
@export var formation_scale_step: float = 0.1
const FORMATION_CAPTURE_INTERVAL: int = 3
var _formation_capture_tick: int = 0
var _dyn_last_targets: Dictionary = {}    # rat instance_id → Vector3 (last assigned target pos)
var _scroll_snap_cooldown: float = 0.0    # suppresses wall-deformation check after scroll snap

# ── Combat draw (stream/arc) ──────────────────────────────────────────────────
const STREAM_SPACING: float = 0.7
const DRAW_SAMPLE_DIST: float = 0.2
const MOUSE_TRAIL_MAX: int = 500
var _mouse_trail: Array[Vector3] = []   # continuous mouse position history
var _mouse_trail_last: Vector3 = Vector3.ZERO
var _mouse_trail_last_dir: Vector3 = Vector3.ZERO
var _build_in_progress: bool = false
var _combat_circle_angle: float = 0.0
var _combat_offsets: Dictionary = {}
var _combat_offsets_ready: bool = false
var _carried_player_base_y: float = 0.0
var _carried_player_base_set: bool = false
var _carry_player_active: bool = false

const BRUSH_DIM_FACTOR: float = 0.6

@export var formation_batch_size: int = 8
var _formation_queue: Array[Rat] = []
var _formation_index: int = 0
var _formation_active: bool = false



# ── Neighbor throttle ─────────────────────────────────────────────────────────
const NEIGHBOR_RADIUS: float = 1.1
const NEIGHBOR_TICK: int = 3
var _neighbor_tick: int = 0


# ── Structure Integrity ──
@export var structure_max_integrity: float = 100.0
var structure_integrity: float = structure_max_integrity
@export var structure_decay_on_laser: float = 25.0 # integrity loss per second
@export var structure_decay_on_projectile: float = 20.0 # integrity loss per hit
@export var structure_lifetime: float = 0.0 # seconds before wall crumbles (0 = never)
var _structure_timer: float = 0.0

@export var bridge_collapse_time: float = 2.5
var bridge_stress: float = 0.0
var _stress_update_timer: float = 0.0


func _ready() -> void:
	add_to_group("rat_manager")
	_clamp_caps()

	immediate_mesh = ImmediateMesh.new()
	line_mesh_instance = MeshInstance3D.new()
	_init_cursor_hint_ui()
	
	unified_shape_combiner = CSGCombiner3D.new()
	unified_shape_combiner.use_collision = true
	# Put structures on layer 9 (bit 9), not layer mask "9" (which includes floor).
	unified_shape_combiner.collision_layer = 1 << 8
	unified_shape_combiner.add_to_group("rat_structures")
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
	if _player and _player.has_method("set_rat_manager"):
		_player.set_rat_manager(self)
	if _player and _player.has_signal("player_died") and not _player.player_died.is_connected(_on_player_died):
		_player.player_died.connect(_on_player_died)
	if start_with_min and rats.is_empty():
		ensure_min_cap()

func _on_player_died() -> void:
	if grabbed_object == _player:
		grabbed_object.set_meta("is_being_dragged", false)
		_carry_player_active = false
		_carried_player_base_set = false
		_player.set("is_being_carried", false)
		_player.set("has_carried_target", false)
		_release_object_carriers(grabbed_object)
		grabbed_object = null
		grabbed_object_last_pos = Vector3.ZERO


func _clamp_caps() -> void:
	if min_cap < 0:
		min_cap = 0


func get_total_rat_count() -> int:
	var count := 0
	for rat in rats:
		if rat != null:
			count += 1
	return count


func get_min_cap() -> int:
	return min_cap


func increase_min_cap(amount: int) -> void:
	if amount <= 0:
		return
	min_cap = max(0, min_cap + amount)


func restore_to_min(require_empty: bool = false) -> void:
	if require_empty and get_active_rat_count() > 0:
		return
	_restore_to_min_near_spawn()

func reset_respawn_and_restore() -> void:
	_min_respawn_cooldown = 0.0
	_restore_to_min_near_spawn()

func reset_after_level_load() -> void:
	# Reset cursor/build state so preview aligns immediately
	_mouse_trail.clear()
	_mouse_trail_last = Vector3.ZERO
	_mouse_trail_last_dir = Vector3.ZERO
	current_build_y = -1000.0
	current_drawn_path.clear()
	_has_last_build_pos = false
	if immediate_mesh:
		immediate_mesh.clear_surfaces()
	_min_respawn_cooldown = 0.0
	# Revive any fallen rats at the nearest spawn
	var center := _get_nearest_spawn_pos()
	for r in rats:
		var rat := r as Rat
		if rat and rat.is_fallen:
			var angle := randf() * TAU
			var radius := randf_range(spawn_radius_min, spawn_radius_max)
			var pos := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			rat.force_respawn_at_position(pos)
	ensure_min_cap()


func ensure_min_cap() -> void:
	_clamp_caps()
	var target := min_cap
	if target <= 0:
		return
	var active := get_active_rat_count()
	if active >= target:
		return
	_restore_to_min_near_spawn()


func _spawn_rats(count: int) -> void:
	if count <= 0:
		return
	if rat_scene == null:
		push_error("rat_scene is not set in RatManager.")
		return

	var parent_node := get_parent()
	if parent_node == null:
		parent_node = self

	var base_pos := _get_horde_center()
	var spawns := get_tree().get_nodes_in_group("rat_spawn")
	var spawn_nodes: Array[Node3D] = []
	for s in spawns:
		var n := s as Node3D
		if n != null:
			spawn_nodes.append(n)
	if spawn_nodes.size() > 1:
		spawn_nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(base_pos) < b.global_position.distance_squared_to(base_pos)
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


func _get_nearest_spawn_pos(ref_pos: Vector3 = Vector3.INF) -> Vector3:
	var base_pos := ref_pos
	if base_pos == Vector3.INF:
		base_pos = _get_horde_center()
	var spawns := get_tree().get_nodes_in_group("rat_spawn")
	var nearest: Node3D = null
	var best_dist := INF
	for s in spawns:
		var n := s as Node3D
		if n == null:
			continue
		var d := n.global_position.distance_squared_to(base_pos)
		if d < best_dist:
			best_dist = d
			nearest = n
	if nearest:
		return nearest.global_position
	return base_pos

func _get_start_spawn_pos() -> Vector3:
	var start_spawns := get_tree().get_nodes_in_group("rat_spawn_start")
	if start_spawns.is_empty():
		return _get_nearest_spawn_pos()
	var ref_pos := _player.global_position if _player != null else _get_horde_center()
	var best: Node3D = null
	var best_dist := INF
	for s in start_spawns:
		var n := s as Node3D
		if n == null:
			continue
		var d := n.global_position.distance_squared_to(ref_pos)
		if d < best_dist:
			best_dist = d
			best = n
	if best:
		return best.global_position
	return _get_nearest_spawn_pos()

func _get_spawn_in_activation_range() -> Node3D:
	var center := _get_horde_center()
	var spawns := get_tree().get_nodes_in_group("rat_spawn")
	var best: Node3D = null
	var best_dist := INF
	for s in spawns:
		var n := s as Node3D
		if n == null:
			continue
		var radius := 0.0
		if n.has_method("get_activation_radius"):
			radius = n.get_activation_radius()
		if radius <= 0.0:
			continue
		var dx := center.x - n.global_position.x
		var dz := center.z - n.global_position.z
		var d2 := dx * dx + dz * dz
		if d2 <= radius * radius and d2 < best_dist:
			best_dist = d2
			best = n
	return best

func _get_horde_center() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for rat in rats:
		var r := rat as Rat
		if r == null:
			continue
		if r.is_fallen:
			continue
		sum += r.global_position
		count += 1
	if count > 0:
		return sum / float(count)
	if _player:
		return _player.global_position
	return global_position


func _spawn_rats_at_center(count: int, center: Vector3) -> void:
	if count <= 0:
		return
	if rat_scene == null:
		push_error("rat_scene is not set in RatManager.")
		return

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
	if active <= 0:
		if not auto_respawn_if_empty:
			return
		if _min_respawn_cooldown <= 0.0:
			_restore_to_min_at_center(_get_start_spawn_pos())
			_min_respawn_cooldown = max(0.05, min_cap_respawn_cooldown)
		return
	if active < min_cap and _min_respawn_cooldown <= 0.0:
		var spawn := _get_spawn_in_activation_range()
		if spawn == null:
			return
		_restore_to_min_at_center(spawn.global_position)
		_min_respawn_cooldown = max(0.05, min_cap_respawn_cooldown)


func _restore_to_min_near_spawn() -> void:
	var center := _get_nearest_spawn_pos()
	_restore_to_min_at_center(center)

func _restore_to_min_at_center(center: Vector3) -> void:
	_clamp_caps()
	var target := min_cap
	if target <= 0:
		return
	var active := get_active_rat_count()
	if active >= target:
		return
	var needed := target - active

	# Revive fallen rats first
	var fallen := _get_fallen_rats()
	for r in fallen:
		if needed <= 0:
			break
		var angle := randf() * TAU
		var radius := randf_range(spawn_radius_min, spawn_radius_max)
		var pos := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		r.force_respawn_at_position(pos)
		needed -= 1

	# Spawn new rats if still under cap
	if needed > 0:
		_spawn_rats_at_center(needed, center)


func _check_rat_spawn_bonus() -> void:
	# Rat spawns are currently disabled; respawn happens near the player.
	return


func _process(delta: float) -> void:
	if _build_force_timer > 0.0:
		_build_force_timer = max(0.0, _build_force_timer - delta)
	if _min_respawn_cooldown > 0.0:
		_min_respawn_cooldown = max(0.0, _min_respawn_cooldown - delta)
	if _scroll_snap_cooldown > 0.0:
		_scroll_snap_cooldown = max(0.0, _scroll_snap_cooldown - delta)
	_update_cursor_hint(delta)
	_update_cursor_info()
	_process_formation_queue()
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

	# ── RMB held: combat attack circle ──
	if combat_rmb_down:
		_update_combat_attack_circle(delta)

	# ── LMB: build drag or object drag ──
	if mouse_is_down_left:
		if _lmb_is_object_drag:
			# Object dragging via LMB
			if grabbed_object:
				_process_object_drag(delta)
		else:
			# Build drawing
			if not is_dragging_left:
				var current_mouse_pos := get_viewport().get_mouse_position()
				if left_click_start_pos.distance_squared_to(current_mouse_pos) > drag_threshold_squared:
					is_dragging_left = true
			if is_dragging_left:
				_process_build_drag()

	_check_formation_sync()
	_check_carrier_arrival()
	_check_travel_anchoring()
	_update_carrier_rat_targets()
	_update_free_rats_follow_cursor(delta)
	_process_hover()
	if structure_lifetime > 0.0 and _has_static_rats():
		_structure_timer += delta
		if _structure_timer >= structure_lifetime:
			recall_all_rats()
			structure_integrity = structure_max_integrity
			_structure_timer = 0.0

	if _stress_update_timer > 0.0:
		_stress_update_timer -= delta
		var shake := 0.05 * (bridge_stress / bridge_collapse_time)
		unified_shape_combiner.position = Vector3(
			randf_range(-shake, shake),
			0.0,
			randf_range(-shake, shake)
		)
	elif bridge_stress > 0.0:
		bridge_stress = maxf(0.0, bridge_stress - delta * 0.5)
		if bridge_stress <= 0.0:
			unified_shape_combiner.position = Vector3.ZERO
		else:
			var shake := 0.05 * (bridge_stress / bridge_collapse_time)
			unified_shape_combiner.position = Vector3(
				randf_range(-shake, shake),
				0.0,
				randf_range(-shake, shake)
			)

	# ── Neighbor throttle ──
	_neighbor_tick += 1
	if _neighbor_tick >= NEIGHBOR_TICK:
		_neighbor_tick = 0
		_assign_neighbors()

	# ── Cursor Preview ──
	_update_cursor_preview()
	_check_empty_respawn()
	_check_rat_spawn_bonus()
	_update_carried_player()


func _update_edge_avoidance() -> void:
	for rat in rats:
		rat.edge_avoidance_enabled = true

func _update_carried_player() -> void:
	if not carry_player_enabled:
		return
	if _player == null:
		return
	if grabbed_object == _player:
		return
	if not _carry_player_active:
		return
	if not _carried_player_base_set:
		_carried_player_base_y = _player.global_position.y
		_carried_player_base_set = true
	var center := _get_horde_center()
	var target := Vector3(center.x, _carried_player_base_y + carry_player_height_offset, center.z)
	_player.set("carried_target_pos", target)
	_player.set("has_carried_target", true)
	# Keep player from drifting due to physics
	if _player.has_method("set_velocity"):
		_player.set_velocity(Vector3.ZERO)
	elif "velocity" in _player:
		_player.velocity = Vector3.ZERO


# ── COMBAT: arc/stream follow ──────────────────────────────────────────────────

func _get_active_follow_rats() -> Array[CharacterBody3D]:
	var active: Array[CharacterBody3D] = []
	for rat in rats:
		if not rat.is_carrier and rat.state == rat.State.FOLLOW:
			active.append(rat)
	return active


func _update_mouse_trail(mouse_world: Vector3) -> void:
	if _mouse_trail.is_empty():
		_mouse_trail.append(mouse_world)
		_mouse_trail_last = mouse_world
		_mouse_trail_last_dir = Vector3.ZERO
	elif mouse_world.distance_to(_mouse_trail_last) >= DRAW_SAMPLE_DIST:
		var move := mouse_world - _mouse_trail_last
		move.y = 0.0
		var dist := move.length()
		if dist > 0.001 and _mouse_trail.size() >= 2:
			var new_dir := move / dist
			if _mouse_trail_last_dir != Vector3.ZERO and dist >= cursor_turn_reset_distance:
				var dot := clampf(_mouse_trail_last_dir.dot(new_dir), -1.0, 1.0)
				var angle := rad_to_deg(acos(dot))
				if angle >= cursor_turn_reset_angle:
					_mouse_trail.clear()
					_mouse_trail.append(mouse_world)
					_mouse_trail_last = mouse_world
					_mouse_trail_last_dir = new_dir
					return
			_mouse_trail_last_dir = new_dir
		_mouse_trail.append(mouse_world)
		_mouse_trail_last = mouse_world
		_trim_mouse_trail_max_length()
		if _mouse_trail.size() > MOUSE_TRAIL_MAX:
			_mouse_trail.pop_front()

func _trim_mouse_trail_max_length() -> void:
	if cursor_trail_max_length <= 0.0:
		return
	if _mouse_trail.size() < 2:
		return
	var total := 0.0
	for i in range(1, _mouse_trail.size()):
		total += _mouse_trail[i].distance_to(_mouse_trail[i - 1])
	while total > cursor_trail_max_length and _mouse_trail.size() > 2:
		total -= _mouse_trail[1].distance_to(_mouse_trail[0])
		_mouse_trail.remove_at(0)


func _brush_color(base: Color) -> Color:
	if combat_rmb_down:
		return Color(base.r * BRUSH_DIM_FACTOR, base.g * BRUSH_DIM_FACTOR, base.b * BRUSH_DIM_FACTOR, base.a)
	return base


func _capture_combat_offsets(mouse_world: Vector3) -> void:
	_combat_offsets.clear()
	_combat_offsets_ready = false

	var active := _get_active_follow_rats()
	var count := active.size()
	if count == 0:
		return

	var effect_radius := combat_circle_radius
	var brush_ring_spacing := brush_lane_spacing * 1.6
	var lane_count := 1
	var center_index := 0.0
	if build_draw_mode == DRAW_MODE_CIRCLE:
		effect_radius = maxf(combat_circle_radius, circle_radius * 1.2)
	elif build_draw_mode == DRAW_MODE_PATH and use_wide_brush:
		var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
		lane_count = 1 + pairs * 2
		center_index = float(lane_count - 1) / 2.0
		effect_radius = maxf(combat_circle_radius, float(lane_count - 1) * brush_ring_spacing * 0.6)

	var angle_step := TAU / float(count)
	for i in range(count):
		var rat := active[i]
		var offset := rat.global_position - mouse_world
		offset.y = 0.0
		if offset.length() < 0.25:
			var angle := angle_step * float(i)
			var radius := effect_radius
			if build_draw_mode == DRAW_MODE_PATH and use_wide_brush and lane_count > 1:
				var lane_index := i % lane_count
				var factor := float(lane_index) - center_index
				radius = maxf(0.8, effect_radius + factor * brush_ring_spacing)
			offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_combat_offsets[rat.get_instance_id()] = offset

	_combat_offsets_ready = true


func _update_combat_attack_circle(delta: float) -> void:
	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		return

	_update_mouse_trail(mouse_world)

	var active := _get_active_follow_rats()
	var count := active.size()
	if count == 0:
		return

	_combat_circle_angle += combat_circle_rotation_speed * delta
	if _combat_offsets_ready:
		for rat in active:
			var id := rat.get_instance_id()
			if _combat_offsets.has(id):
				var base_offset: Vector3 = _combat_offsets[id]
				var rotated := base_offset.rotated(Vector3.UP, _combat_circle_angle)
				var target := mouse_world + rotated
				target.y = mouse_world.y
				rat.set_target(target)
		return

	var effect_radius := combat_circle_radius
	var brush_ring_spacing := brush_lane_spacing * 1.6
	var lane_count := 1
	var center_index := 0.0
	if build_draw_mode == DRAW_MODE_CIRCLE:
		effect_radius = maxf(combat_circle_radius, circle_radius * 1.2)
	elif build_draw_mode == DRAW_MODE_PATH and use_wide_brush:
		var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
		lane_count = 1 + pairs * 2
		center_index = float(lane_count - 1) / 2.0
		effect_radius = maxf(combat_circle_radius, float(lane_count - 1) * brush_ring_spacing * 0.6)
	var angle_step := TAU / float(count)
	for i in range(count):
		var angle := _combat_circle_angle + angle_step * float(i)
		var radius := effect_radius
		if build_draw_mode == DRAW_MODE_PATH and use_wide_brush and lane_count > 1:
			var lane_index := i % lane_count
			var factor := float(lane_index) - center_index
			radius = maxf(0.8, effect_radius + factor * brush_ring_spacing)
		var target := mouse_world + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		target.y = mouse_world.y
		active[i].set_target(target)


func _update_cursor_follow(delta: float) -> void:
	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		_set_cursor_following(_get_active_follow_rats(), false)
		return

	_update_mouse_trail(mouse_world)

	var active := _get_active_follow_rats()
	var count := active.size()
	if count == 0:
		return
	_set_cursor_following(active, true)
	var base_y := mouse_world.y
	if count > 0:
		var sum_y := 0.0
		for rat in active:
			sum_y += rat.global_position.y
		base_y = sum_y / float(count)

	# Formation is no longer re-captured every few frames.
	# Shape only changes when rats collide with walls (see _check_wall_deformation).

	# ── Initialize offsets for rats that don't have one yet ──
	for rat in active:
		var id := rat.get_instance_id()
		if not _dyn_offsets.has(id):
			var offset := rat.global_position - mouse_world
			offset.y = 0.0
			var effective := _dyn_base_radius * formation_scale
			if effective > 0.1:
				_dyn_offsets[id] = offset / effective
			else:
				_dyn_offsets[id] = Vector3.ZERO

	# ── Clean up offsets for rats that no longer exist or are permanently gone ──
	# Keep offsets for ATTACK_PATH rats so they return to their formation
	var all_alive_ids: Dictionary = {}
	for rat in rats:
		if rat == null:
			continue
		var r := rat as Rat
		if r != null and r.is_fallen:
			continue
		# Skip rats that are permanently consumed (static/building)
		if r != null and (r.state == r.State.STATIC or r.state == r.State.TRAVEL_TO_BUILD or r.state == r.State.WAITING_FOR_FORMATION):
			continue
		all_alive_ids[rat.get_instance_id()] = true
	var to_remove: Array = []
	for key in _dyn_offsets:
		if not all_alive_ids.has(key):
			to_remove.append(key)
	for key in to_remove:
		_dyn_offsets.erase(key)

	# ── Set targets using dynamic formation offsets ──
	var effective_scale := formation_scale * _dyn_base_radius
	for rat in active:
		var id: int = rat.get_instance_id()
		var off := Vector3.ZERO
		if _dyn_offsets.has(id):
			off = Vector3(_dyn_offsets[id])
		var target := mouse_world + off * effective_scale
		target.y = base_y
		rat.set_target(target)
		_dyn_last_targets[id] = target

	# ── Re-capture formation only when rats are blocked by walls ──
	_check_wall_deformation()

func _update_free_rats_follow_cursor(delta: float) -> void:
	# Skip when build drag is handling rats
	if mouse_is_down_left and not _lmb_is_object_drag:
		_set_cursor_following(_get_active_follow_rats(), false)
		_clear_cursor_capstan()
		return
	if _update_capstan_cursor(delta):
		return
	_update_cursor_follow(delta)


func _update_capstan_cursor(delta: float) -> bool:
	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		_clear_cursor_capstan()
		return false

	var nearest: Capstan = null
	var nearest_dist_sq := capstan_cursor_snap_radius * capstan_cursor_snap_radius
	for node in get_tree().get_nodes_in_group("capstan"):
		var cap := node as Capstan
		if cap == null:
			continue
		var d_sq := _flat_distance_squared(mouse_world, cap.global_position)
		if d_sq <= nearest_dist_sq:
			nearest = cap
			nearest_dist_sq = d_sq

	if nearest == null:
		_clear_cursor_capstan()
		return false

	if _cursor_capstan != nearest:
		_cursor_capstan = nearest
		_cursor_capstan_has_angle = false

	# Require at least one rat near the capstan to allow rotation
	if not _has_rat_near_capstan(_cursor_capstan):
		_clear_cursor_capstan()
		return false

	# Rotate capstan based on mouse movement around it (flat angle)
	var to_mouse := mouse_world - _cursor_capstan.global_position
	to_mouse.y = 0.0
	if to_mouse.length() > 0.001:
		var angle := atan2(to_mouse.x, to_mouse.z)
		if _cursor_capstan_has_angle:
			var diff := wrapf(angle - _cursor_capstan_last_angle, -PI, PI)
			_cursor_capstan.apply_cursor_rotation(diff * capstan_cursor_rotation_scale, delta)
		_cursor_capstan_last_angle = angle
		_cursor_capstan_has_angle = true

	# Snap free FOLLOW rats to a ring around the capstan
	var active := _get_active_follow_rats()
	if active.size() > 0:
		_set_cursor_following(active, true)
		_set_capstan_collision(active, _cursor_capstan, true)
	return false


func _snap_rats_to_capstan(active: Array[CharacterBody3D], center: Vector3) -> void:
	var count := active.size()
	if count == 0:
		return
	var angle_step := TAU / float(count)
	for i in range(count):
		var angle := angle_step * float(i)
		var target := center + Vector3(cos(angle) * capstan_cursor_ring_radius, 0.0, sin(angle) * capstan_cursor_ring_radius)
		target.y = center.y
		active[i].set_target(target)


func _clear_cursor_capstan() -> void:
	_clear_capstan_collision_exceptions()
	_cursor_capstan = null
	_cursor_capstan_has_angle = false


func _set_capstan_collision(active: Array[CharacterBody3D], capstan: Capstan, enabled: bool) -> void:
	if capstan == null:
		return
	for rat in active:
		if rat == null:
			continue
		if enabled:
			rat.add_collision_exception_with(capstan)
			capstan.add_collision_exception_with(rat)
			_capstan_collision_exceptions[rat] = capstan
		else:
			if _capstan_collision_exceptions.has(rat):
				var prev := _capstan_collision_exceptions[rat] as Node
				if prev:
					rat.remove_collision_exception_with(prev)
					prev.remove_collision_exception_with(rat)
				_capstan_collision_exceptions.erase(rat)


func _clear_capstan_collision_exceptions() -> void:
	for rat in _capstan_collision_exceptions.keys():
		var capstan := _capstan_collision_exceptions[rat] as Node
		if rat and capstan:
			rat.remove_collision_exception_with(capstan)
			capstan.remove_collision_exception_with(rat)
	_capstan_collision_exceptions.clear()


func _set_cursor_following(active: Array[CharacterBody3D], enabled: bool) -> void:
	for rat in active:
		if rat:
			rat.set_cursor_following(enabled)


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


func _flat_distance_squared(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


func _has_rat_near_capstan(capstan: Capstan) -> bool:
	if capstan == null:
		return false
	var r_sq := capstan_rat_required_radius * capstan_rat_required_radius
	for rat in rats:
		if rat == null:
			continue
		if _flat_distance_squared(rat.global_position, capstan.global_position) <= r_sq:
			return true
	return false


func build_blob_offsets() -> void:
	_blob_offsets.clear()
	var count := rats.size()
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i in range(count):
		var r := BLOB_RADIUS_BASE * sqrt(float(i + 1) / float(count)) + BLOB_SPREAD * float(i) * 0.04
		var a := golden_angle * float(i)
		_blob_offsets.append(Vector3(cos(a) * r, 0.0, sin(a) * r))


func _capture_dynamic_formation() -> void:
	var active := _get_active_follow_rats()
	if active.is_empty():
		return

	# Compute center of active follow rats
	var center := Vector3.ZERO
	for rat in active:
		center += rat.global_position
	center /= float(active.size())

	# Compute offsets from center and find max distance
	var max_dist := 0.0
	var raw_offsets: Dictionary = {}
	for rat in active:
		var offset := rat.global_position - center
		offset.y = 0.0
		raw_offsets[rat.get_instance_id()] = offset
		var d := offset.length()
		if d > max_dist:
			max_dist = d

	# Normalize so the furthest rat has offset magnitude = 1.0
	if max_dist < 0.1:
		max_dist = 0.1
	# Divide by formation_scale so base radius is the unscaled size.
	# This prevents scale from compounding when recapture happens.
	if formation_scale > 0.01:
		_dyn_base_radius = max_dist / formation_scale
	else:
		_dyn_base_radius = max_dist

	_dyn_offsets.clear()
	for key in raw_offsets:
		var raw_off: Vector3 = raw_offsets[key]
		_dyn_offsets[key] = raw_off / max_dist


func _check_wall_deformation() -> void:
	# Skip right after a scroll-snap so zeroed velocity doesn't falsely trigger
	if _scroll_snap_cooldown > 0.0:
		return
	# Skip while any rat is attacking — recapture with partial rats would break formation
	for rat in rats:
		if rat != null and rat.state == rat.State.ATTACK_PATH:
			return
	var active := _get_active_follow_rats()
	if active.is_empty():
		return

	var any_blocked := false
	for rat in active:
		var id := rat.get_instance_id()
		if not _dyn_last_targets.has(id):
			continue
		var target: Vector3 = _dyn_last_targets[id]
		var actual := rat.global_position
		# Compare in the XZ plane
		var diff := Vector2(target.x - actual.x, target.z - actual.z).length()
		# If rat is far from target (blocked by wall) and nearly stopped (truly blocked)
		var vel_len := Vector2(rat.velocity.x, rat.velocity.z).length()
		if diff > 0.3 and vel_len < 0.3:
			any_blocked = true
			break

	if any_blocked:
		_capture_dynamic_formation()


func _snap_formation_to_scale(old_scale: float) -> void:
	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		return
	var active := _get_active_follow_rats()
	if active.is_empty():
		return
	var old_effective := old_scale * _dyn_base_radius
	var new_effective := formation_scale * _dyn_base_radius
	# Compute a consistent base_y (average of all active rats) to avoid Y oscillation
	var base_y := mouse_world.y
	if active.size() > 0:
		var sum_y := 0.0
		for rat in active:
			sum_y += rat.global_position.y
		base_y = sum_y / float(active.size())
	for rat in active:
		var id := rat.get_instance_id()
		var off := Vector3.ZERO
		if _dyn_offsets.has(id):
			off = Vector3(_dyn_offsets[id])
		# Shift rat position by the delta the target moved
		var delta_pos := off * (new_effective - old_effective)
		rat.global_position.x += delta_pos.x
		rat.global_position.z += delta_pos.z
		# Set new target at the shifted position
		var target := mouse_world + off * new_effective
		target.y = base_y
		rat.set_target(target)
		# Kill ALL momentum so rats stop immediately (knob feel)
		rat._spring_velocity = Vector3.ZERO
		rat.velocity.x = 0.0
		rat.velocity.z = 0.0
		_dyn_last_targets[id] = target
	# Suppress wall-deformation check so zeroed velocity doesn't falsely trigger
	_scroll_snap_cooldown = 0.5


func _init_default_formation() -> void:
	_dyn_offsets.clear()
	_dyn_last_targets.clear()
	_dyn_base_radius = 2.0
	_formation_capture_tick = 0


func _get_formation_max_extent() -> float:
	if _dyn_offsets.is_empty():
		return 0.0
	var max_d := 0.0
	for key in _dyn_offsets:
		var off: Vector3 = _dyn_offsets[key]
		var d: float = off.length()
		if d > max_d:
			max_d = d
	return max_d * formation_scale * _dyn_base_radius


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
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
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
				if not is_instance_valid(rat) or not rat.is_inside_tree():
					continue
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
		_start_formation_activation()


func _start_formation_activation() -> void:
	if _formation_active:
		return
	_formation_queue.clear()
	for rat in rats:
		if rat.state == rat.State.WAITING_FOR_FORMATION:
			_formation_queue.append(rat)
	_formation_index = 0
	_formation_active = true


func _process_formation_queue() -> void:
	if not _formation_active:
		return
	var total := _formation_queue.size()
	if total == 0:
		_formation_active = false
		return
	var end_idx: int = min(_formation_index + formation_batch_size, total)
	for i in range(_formation_index, end_idx):
		var rat: Rat = _formation_queue[i]
		if is_instance_valid(rat):
			rat.activate_physics()
	_formation_index = end_idx
	if _formation_index >= total:
		_formation_active = false
		_formation_queue.clear()
		_form_unified_mesh()
		structure_integrity = structure_max_integrity
		_structure_timer = 0.0
		_build_in_progress = false


func _form_unified_mesh() -> void:
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	var static_rats: Array[Rat] = []
	for rat in rats:
		if not is_instance_valid(rat) or not rat.is_inside_tree():
			continue
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
	
	var radius = 0.35

	var rat_positions = []
	var rat_on_floor = []
	var space_state = get_world_3d().direct_space_state

	for rat in static_rats:
		var pos = rat.global_position
		rat_positions.append(pos)
		
		# Raycast downwards to check if the rat is resting on the floor
		var query = PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -1.5, 0))
		query.collision_mask = 1 # Floor
		var hit = space_state.intersect_ray(query)
		var on_floor = false
		if not hit.is_empty():
			var floor_dist: float = pos.y - (hit.position as Vector3).y
			on_floor = floor_dist <= 0.4
		rat_on_floor.append(on_floor)

	var connection_threshold = 1.3
	var max_connections_per_rat = 4
	var num_rats = rat_positions.size()
	
	# Build adjacency list for graph
	var adj = []
	for i in range(num_rats):
		adj.append([])
		
	var all_neighbors = []
	for i in range(num_rats):
		var pos_a = rat_positions[i]
		var neighbors = []
		for j in range(num_rats):
			if i == j: continue
			var pos_b = rat_positions[j]
			var y_diff = abs(pos_a.y - pos_b.y)
			if y_diff > 0.6:
				continue
			var dist = pos_a.distance_to(pos_b)
			if dist < connection_threshold:
				neighbors.append({"index": j, "dist": dist})
		neighbors.sort_custom(func(a, b): return a["dist"] < b["dist"])
		
		var connected_to_i = []
		var connections_made = 0
		for nb in neighbors:
			if connections_made >= max_connections_per_rat:
				break
			var j = nb["index"]
			connected_to_i.append({"index": j, "dist": nb["dist"]})
			adj[i].append(j)
			connections_made += 1
		all_neighbors.append(connected_to_i)
	
	# Find connected components (islands of rats)
	var component_id = []
	for i in range(num_rats):
		component_id.append(-1)
		
	var current_comp = 0
	for i in range(num_rats):
		if component_id[i] == -1:
			var queue = [i]
			component_id[i] = current_comp
			while not queue.is_empty():
				var curr = queue.pop_front()
				for neighbor in adj[curr]:
					if component_id[neighbor] == -1:
						component_id[neighbor] = current_comp
						queue.append(neighbor)
			current_comp += 1
			
	# Determine if a component spans a chasm (any rat in component not on floor)
	var component_is_bridge = []
	for i in range(current_comp):
		component_is_bridge.append(false)
		
	for i in range(num_rats):
		if not rat_on_floor[i]:
			var cid = component_id[i]
			component_is_bridge[cid] = true
	
	# Generate cylinders
	for i in range(num_rats):
		var is_bridge = component_is_bridge[component_id[i]]
		# Bridge: height 0.4, offset -0.3. Barricade: height 1.2, offset 0.6
		var current_height = 0.4 if is_bridge else 1.2
		var current_y_offset = -0.3 if is_bridge else 0.6
		
		var cyl = CSGCylinder3D.new()
		cyl.radius = radius
		cyl.height = current_height
		cyl.sides = 12
		cyl.material = mat
		unified_shape_combiner.add_child(cyl)
		cyl.global_position = rat_positions[i] + Vector3(0, current_y_offset, 0)

	# Generate boxes for connections
	for i in range(num_rats):
		var pos_a = rat_positions[i]
		var is_bridge_a = component_is_bridge[component_id[i]]
		
		for nb in all_neighbors[i]:
			var j = nb["index"]
			if i > j: 
				continue # avoid double drawing edges (undirected graph equivalent)
				
			var pos_b = rat_positions[j]
			var dist = nb["dist"]
			
			var is_bridge_b = component_is_bridge[component_id[j]]
			var connection_is_bridge = is_bridge_a or is_bridge_b
			var current_height = 0.4 if connection_is_bridge else 1.2
			var current_y_offset = -0.3 if connection_is_bridge else 0.6
			
			var box = CSGBox3D.new()
			box.size = Vector3(radius * 2.0, current_height, dist)
			var center = (pos_a + pos_b) / 2.0
			unified_shape_combiner.add_child(box)
			box.global_position = center + Vector3(0, current_y_offset, 0)
			
			if dist > 0.001:
				var forward = (pos_b - pos_a).normalized()
				var up = Vector3.UP
				if abs(forward.y) > 0.99:
					up = Vector3.RIGHT
				box.look_at_from_position(box.global_position, box.global_position + forward, up)
			
			box.material = mat


# ── Input handling ────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if wave_pending and event is InputEventMouseButton:
		var mb_wave := event as InputEventMouseButton
		if mb_wave.button_index == MOUSE_BUTTON_RIGHT and mb_wave.pressed:
			_fire_wave_at_mouse(mb_wave.position)
			wave_pending = false
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		# ── Scroll: rotate object if grabbed, change formation scale or brush size ──
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if grabbed_object != null:
				# Rotate grabbed object
				var rot_dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				grabbed_object.rotate_y(deg_to_rad(object_rotation_step * rot_dir))
			elif mouse_is_down_left and not _drawing_attack_path:
				# MMB held (building) → change brush size
				if build_draw_mode == DRAW_MODE_PATH:
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
					_update_circle_preview()
			else:
				# Idle or LMB attack → change formation scale
				var old_scale := formation_scale
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					formation_scale += formation_scale_step
				else:
					formation_scale -= formation_scale_step
				formation_scale = clampf(formation_scale, formation_scale_min, formation_scale_max)
				# Immediately apply new spacing and kill momentum (knob feel)
				_snap_formation_to_scale(old_scale)

			get_viewport().set_input_as_handled()
			return

		# ── MMB: recall all rats ──
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				recall_all_rats()
			get_viewport().set_input_as_handled()
			return

		# ── LMB: attack draw ──
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drawing_attack_path = true
				mouse_is_down_left = true
				left_click_start_pos = mb.position
				is_dragging_left = false
				_lmb_is_object_drag = false
				current_drawn_path.clear()
				_current_drawn_path_length = 0.0
				current_build_y = -1000.0
				_has_last_build_pos = false
			else:
				# Released → send attack wave
				if is_dragging_left and _drawing_attack_path:
					_send_attack_wave()

				mouse_is_down_left = false
				_lmb_is_object_drag = false
				current_build_y = -1000.0
				is_drawing_line = false
				current_drawn_path.clear()
				_current_drawn_path_length = 0.0
				_has_last_build_pos = false
				immediate_mesh.clear_surfaces()
			get_viewport().set_input_as_handled()
			return

		# ── RMB: raycast for object → drag ──
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				# Raycast to check if we clicked on a movable object
				var camera_m: Camera3D = get_viewport().get_camera_3d()
				var ray_origin_m: Vector3 = camera_m.project_ray_origin(mb.position)
				var ray_dir_m: Vector3 = camera_m.project_ray_normal(mb.position)
				var space_state_m := camera_m.get_world_3d().direct_space_state
				var query_m := PhysicsRayQueryParameters3D.create(ray_origin_m, ray_origin_m + ray_dir_m * 1000.0)
				var hit_m := space_state_m.intersect_ray(query_m)

				var handled := false
				if hit_m:
					var obj = hit_m.collider
					if obj is box or obj is turret or obj is hitscan_turret or obj == _player:
						var available := get_available_rat_count()
						if obj != _player and available <= 0:
							_show_cursor_hint("Brak wolnych szczurów do przenoszenia")
							get_viewport().set_input_as_handled()
							return
						if obj == _player and not _player_has_enough_rats_to_move():
							_show_cursor_hint("Brak aktywnego obiektu do przenoszenia —\nPPM dziala tylko na obiekty do przeniesienia.\nNajedz kursorem na skrzynke, wiezyczke lub gracza.")
							get_viewport().set_input_as_handled()
							return
						mouse_is_down_left = true
						left_click_start_pos = mb.position
						is_dragging_left = false
						_lmb_is_object_drag = true
						if not obj.is_surrounded:
							_surround_object_with_rats(obj)
						grabbed_object = obj
						if grabbed_object:
							grabbed_object.set_meta("is_being_dragged", true)
							if grabbed_object == _player and carry_player_enabled:
								_carry_player_active = true
								_carried_player_base_set = false
								_player.set("carried_by_rats", true)
								_player.set("is_being_carried", true)
								grabbed_object.set("is_surrounded", true)
						grabbed_object_last_pos = obj.global_position
						handled = true
				if not handled:
					_show_cursor_hint("Brak aktywnego obiektu do przenoszenia —\nPPM dziala tylko na obiekty do przeniesienia.\nNajedz kursorem na skrzynke, wiezyczke lub gracza.")
				get_viewport().set_input_as_handled()
				return
			else:
				# RMB released
				if _lmb_is_object_drag:
					# Release grabbed object
					if grabbed_object != null:
						grabbed_object.set_meta("is_being_dragged", false)
						if grabbed_object == _player:
							_carry_player_active = false
							if _player:
								_player.set("is_being_carried", false)
								_player.set("has_carried_target", false)
						_release_object_carriers(grabbed_object)
						grabbed_object = null
						grabbed_object_last_pos = Vector3.ZERO

				mouse_is_down_left = false
				_lmb_is_object_drag = false
			get_viewport().set_input_as_handled()
			return

	# Wave targeting input (Combat Mode)
	if not wave_pending:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_fire_wave_at_mouse(mb.position)
			wave_pending = false
			get_viewport().set_input_as_handled()


func register_rat(rat: CharacterBody3D) -> void:
	rats.append(rat)
	if rat.has_method("set_wall_collision"):
		rat.set_wall_collision(rats_collide_with_walls)
	if rat.has_method("set_auto_respawn_enabled"):
		rat.set_auto_respawn_enabled(rat_auto_respawn_enabled)

func _init_cursor_hint_ui() -> void:
	_cursor_hint_layer = CanvasLayer.new()
	_cursor_hint_label = Label.new()
	_cursor_hint_label.visible = false
	_cursor_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_hint_label.add_theme_color_override("font_color", Color(1, 0.85, 0.75))
	_cursor_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_cursor_hint_label.add_theme_constant_override("outline_size", 4)
	_cursor_hint_label.add_theme_font_size_override("font_size", 18)
	_cursor_hint_layer.add_child(_cursor_hint_label)
	add_child(_cursor_hint_layer)

	_cursor_info_layer = CanvasLayer.new()
	_cursor_info_label = Label.new()
	_cursor_info_label.visible = false
	_cursor_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_info_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_cursor_info_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_cursor_info_label.add_theme_constant_override("outline_size", 4)
	_cursor_info_label.add_theme_font_size_override("font_size", 15)
	_cursor_info_layer.add_child(_cursor_info_label)
	add_child(_cursor_info_layer)

func _show_cursor_hint(text: String) -> void:
	if _cursor_hint_label == null:
		return
	_cursor_hint_label.text = text
	_cursor_hint_label.visible = true
	_cursor_hint_timer = max(0.1, cursor_hint_duration)
	var mp := get_viewport().get_mouse_position()
	_cursor_hint_label.position = mp + Vector2(14, 18)

func _update_cursor_hint(delta: float) -> void:
	if _cursor_hint_label == null:
		return
	if _cursor_hint_timer > 0.0:
		_cursor_hint_timer = max(0.0, _cursor_hint_timer - delta)
		var mp := get_viewport().get_mouse_position()
		_cursor_hint_label.position = mp + Vector2(14, 18)
		if _cursor_hint_timer <= 0.0:
			_cursor_hint_label.visible = false

func _update_cursor_info() -> void:
	if _cursor_info_label == null:
		return
	var text := ""
	var available := get_available_rat_count()
	var hovered := _get_hovered_movable()
	if hovered != null:
		if hovered == _player:
			var required_player := _get_required_carriers_for_object(hovered)
			text = "Przenoszenie: potrzebne %d | masz %d" % [required_player, available]
		else:
			text = "Przenoszenie: dostepne %d szczurów" % available
	else:
		if build_draw_mode == DRAW_MODE_CIRCLE:
			var hit: Dictionary = _get_mouse_ground_hit()
			if not hit.is_empty():
				var path_for_preview := current_drawn_path
				if path_for_preview.is_empty():
					path_for_preview = PackedVector3Array()
					path_for_preview.append(current_circle_center)
				var required_build := _compute_circle_path_fill_positions(path_for_preview).size()
				if required_build > 0:
					text = "Budowa: potrzebne %d | masz %d" % [required_build, available]
		elif build_draw_mode == DRAW_MODE_PATH:
			text = "Budowa: uzyje do %d szczurów" % available

	if text == "":
		_cursor_info_label.visible = false
		return
	_cursor_info_label.text = text
	_cursor_info_label.visible = true
	var mp := get_viewport().get_mouse_position()
	_cursor_info_label.position = mp + Vector2(16, -30)

func _get_hovered_movable() -> CharacterBody3D:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var ray_origin := cam.project_ray_origin(mp)
	var ray_dir := cam.project_ray_normal(mp)
	var space_state := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	var hit := space_state.intersect_ray(query)
	if hit:
		var obj = hit.collider
		if obj is box or obj is turret or obj is hitscan_turret or obj == _player:
			return obj
	return null

func _get_required_carriers_for_object(obj: CharacterBody3D) -> int:
	if obj == _player:
		return max(1, _get_player_movement_rat_requirement())
	return max(0, get_available_rat_count())


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


func get_available_rat_count() -> int:
	var available := _get_available_follow_rats()
	return available.size()


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


func receive_laser(delta: float) -> void:
	if not _has_static_rats():
		return
	structure_integrity -= structure_decay_on_laser * delta
	if structure_integrity <= 0:
		recall_all_rats()
		structure_integrity = structure_max_integrity


func add_bridge_stress(amount: float) -> void:
	if not _has_static_rats():
		return
	bridge_stress += amount
	_stress_update_timer = 0.1
	if bridge_stress >= bridge_collapse_time:
		recall_all_rats()


func on_projectile_hit() -> void:
	if not _has_static_rats():
		return
	structure_integrity -= structure_decay_on_projectile
	if structure_integrity <= 0:
		recall_all_rats()
		structure_integrity = structure_max_integrity


func recall_all_rats() -> void:
	# Release any grabbed object and its carrier rats first
	if grabbed_object != null:
		grabbed_object.set_meta("is_being_dragged", false)
		if grabbed_object == _player:
			_carry_player_active = false
			if _player:
				_player.set("is_being_carried", false)
				_player.set("has_carried_target", false)
		_release_object_carriers(grabbed_object)
		grabbed_object = null
		grabbed_object_last_pos = Vector3.ZERO
		_lmb_is_object_drag = false

	active_build_positions.clear()
	built_positions.clear()
	carrier_rats.clear()
	carrier_rat_offsets.clear()
	
	# Destroy the unified mesh
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	_gather_rats_to_horde_center()
	# Reset drawing state
	mouse_is_down_left = false
	is_dragging_left = false
	mouse_is_down_right = false
	_lmb_is_object_drag = false
	is_drawing_line = false
	current_build_y = -1000.0
	current_drawn_path.clear()
	_has_last_build_pos = false
	immediate_mesh.clear_surfaces()
	_formation_queue.clear()
	_formation_active = false
	_formation_index = 0
	for rat in rats:
		rat.is_following_player = true
		rat.is_carrier = false
	_structure_timer = 0.0
	bridge_stress = 0.0
	unified_shape_combiner.position = Vector3.ZERO
	_init_default_formation()

	# Respawn only at rat_spawn now.


func hard_recall_all_rats() -> void:
	# Release any grabbed object and its carrier rats first
	if grabbed_object != null:
		grabbed_object.set_meta("is_being_dragged", false)
		if grabbed_object == _player:
			_carry_player_active = false
			if _player:
				_player.set("is_being_carried", false)
				_player.set("has_carried_target", false)
		_release_object_carriers(grabbed_object)
		grabbed_object = null
		grabbed_object_last_pos = Vector3.ZERO
		_lmb_is_object_drag = false

	active_build_positions.clear()
	built_positions.clear()
	carrier_rats.clear()
	carrier_rat_offsets.clear()
	
	# Destroy the unified mesh
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	_gather_rats_to_horde_center()
	# Reset drawing state
	mouse_is_down_left = false
	is_dragging_left = false
	mouse_is_down_right = false
	_lmb_is_object_drag = false
	is_drawing_line = false
	current_build_y = -1000.0
	current_drawn_path.clear()
	_current_drawn_path_length = 0.0
	_has_last_build_pos = false
	immediate_mesh.clear_surfaces()
	_formation_queue.clear()
	_formation_active = false
	_formation_index = 0
	for rat in rats:
		rat.is_following_player = true
		rat.is_carrier = false
	_structure_timer = 0.0
	bridge_stress = 0.0
	unified_shape_combiner.position = Vector3.ZERO
	_init_default_formation()

func _gather_rats_to_horde_center() -> void:
	var center := _get_recall_center()

	var move_list: Array[Rat] = []
	for rat in rats:
		var r := rat as Rat
		if r == null:
			continue
		if r.is_fallen:
			continue
		if r.state != r.State.FOLLOW or r.is_carrier:
			r.is_carrier = false
			r.release_rat(false)
		move_list.append(r)

	if move_list.is_empty():
		return

	var count := move_list.size()
	var ring_radius := 0.6
	if count > 10:
		ring_radius = 1.0
	if count > 24:
		ring_radius = 1.4
	var angle_step := TAU / float(count)

	for i in range(count):
		var angle := angle_step * float(i)
		var target := center + Vector3(cos(angle) * ring_radius, 0.2, sin(angle) * ring_radius)
		var r := move_list[i]
		r.global_position = target
		if "velocity" in r:
			r.velocity = Vector3.ZERO

func _get_recall_center() -> Vector3:
	var hit := _get_mouse_ground_hit()
	if hit:
		return hit.position

	var follow_rats := _get_active_follow_rats()
	if not follow_rats.is_empty():
		var sum := Vector3.ZERO
		for fr in follow_rats:
			sum += fr.global_position
		return sum / float(follow_rats.size())

	return _get_horde_center()


func _process_hover() -> void:

	var camera := get_viewport().get_camera_3d()
	if not camera: return
	
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collision_mask = 4 | 2
	
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
	query.collision_mask = 1
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
	if current_build_y <= -500.0:
		if hit:
			raw_pos = hit.position + hit.normal * build_surface_offset
			current_build_y = raw_pos.y
		else:
			return
	else:
		var fallback := _get_mouse_pos_at_y(current_build_y)
		if fallback == Vector3.ZERO:
			if _has_last_build_pos:
				raw_pos = _last_build_pos
			else:
				return
		else:
			raw_pos = fallback

	_last_build_pos = raw_pos
	_has_last_build_pos = true

	var effective_draw_mode := build_draw_mode
	if _drawing_attack_path:
		effective_draw_mode = DRAW_MODE_PATH

	if effective_draw_mode == DRAW_MODE_PATH:
		if current_drawn_path.is_empty():
			current_drawn_path.append(raw_pos)
		else:
			var last_recorded_pos = current_drawn_path[current_drawn_path.size() - 1]
			var dist = last_recorded_pos.distance_to(raw_pos)
			if dist * dist > min_point_dist_squared:
				if _drawing_attack_path and _current_drawn_path_length + dist > _get_effective_attack_path_length():
					pass
				else:
					current_drawn_path.append(raw_pos)
					if _drawing_attack_path:
						_current_drawn_path_length += dist
		
		_update_drawn_line(raw_pos)
	elif effective_draw_mode == DRAW_MODE_CIRCLE:
		if current_drawn_path.is_empty():
			current_drawn_path.append(raw_pos)
		else:
			var last_recorded_pos_circle = current_drawn_path[current_drawn_path.size() - 1]
			if last_recorded_pos_circle.distance_squared_to(raw_pos) > min_point_dist_squared:
				current_drawn_path.append(raw_pos)

		current_circle_center = raw_pos
		_update_circle_preview()


func _get_attack_line_color() -> Color:
	# No available rats → red
	var available := _get_available_follow_rats()
	if available.size() == 0:
		return Color(1.0, 0.15, 0.1)

	var max_len := _get_effective_attack_path_length()
	if max_len <= 0.01:
		return Color(1.0, 0.15, 0.1)

	var fill := clampf(_current_drawn_path_length / max_len, 0.0, 1.0)

	# 0.0 → white,  0.7 → orange,  1.0 → red
	if fill < 0.7:
		return Color.WHITE
	else:
		var t := clampf((fill - 0.7) / 0.3, 0.0, 1.0)
		# white → orange at t=0..0.5, orange → red at t=0.5..1.0
		if t < 0.5:
			var sub_t := t / 0.5
			return Color.WHITE.lerp(Color(1.0, 0.6, 0.1), sub_t)
		else:
			var sub_t := (t - 0.5) / 0.5
			return Color(1.0, 0.6, 0.1).lerp(Color(1.0, 0.15, 0.1), sub_t)


func _update_drawn_line(end_pos: Vector3, invalid_surface: bool = false) -> void:
	immediate_mesh.clear_surfaces()
	
	if current_drawn_path.size() == 0:
		return

	if line_material:
		var base: Color
		if invalid_surface:
			base = Color(1, 0, 0)
		elif _drawing_attack_path:
			base = _get_attack_line_color()
		else:
			base = Color.WHITE
		line_material.albedo_color = _brush_color(base)
	
	var offset := Vector3(0, 0.1, 0)

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for pos in current_drawn_path:
		immediate_mesh.surface_add_vertex(pos + offset)
	immediate_mesh.surface_add_vertex(end_pos + offset)
	immediate_mesh.surface_end()

	# ── Attack path: draw formation markers along the path ──
	if _drawing_attack_path:
		var max_len := _get_effective_attack_path_length()
		var at_limit := max_len > 0.01 and _current_drawn_path_length >= max_len - 0.1

		# Draw end-cap X mark when at limit
		if at_limit and current_drawn_path.size() >= 2:
			var tip := current_drawn_path[current_drawn_path.size() - 1] + offset
			var prev := current_drawn_path[current_drawn_path.size() - 2]
			var fwd := (current_drawn_path[current_drawn_path.size() - 1] - prev)
			fwd.y = 0.0
			if fwd.length() > 0.001:
				fwd = fwd.normalized()
			else:
				fwd = Vector3.FORWARD
			var lat := fwd.cross(Vector3.UP).normalized()
			var mark_size := 0.4
			immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			immediate_mesh.surface_add_vertex(tip + lat * mark_size + fwd * mark_size)
			immediate_mesh.surface_add_vertex(tip - lat * mark_size - fwd * mark_size)
			immediate_mesh.surface_add_vertex(tip - lat * mark_size + fwd * mark_size)
			immediate_mesh.surface_add_vertex(tip + lat * mark_size - fwd * mark_size)
			immediate_mesh.surface_end()

		# Draw formation markers at regular intervals along the path
		if not _dyn_offsets.is_empty() and current_drawn_path.size() >= 2:
			var eff_scale := formation_scale * _dyn_base_radius
			var marker_sz := 0.1
			var marker_interval := 2.0  # units between marker sets

			# Build arc-length table for the path
			var arc_lengths: Array[float] = [0.0]
			var path_count := current_drawn_path.size()
			for pi in range(1, path_count):
				arc_lengths.append(arc_lengths[pi - 1] + current_drawn_path[pi].distance_to(current_drawn_path[pi - 1]))
			var total_arc: float = arc_lengths[path_count - 1]

			# Determine sample distances along the path
			var sample_dists: Array[float] = []
			var d := 0.0
			while d <= total_arc + 0.01:
				sample_dists.append(minf(d, total_arc))
				d += marker_interval
			# Always include the tip
			if sample_dists.is_empty() or sample_dists[sample_dists.size() - 1] < total_arc - 0.1:
				sample_dists.append(total_arc)

			for sd in sample_dists:
				# Find position on path at arc distance sd
				var seg_idx := 0
				for si in range(1, path_count):
					if arc_lengths[si] >= sd:
						seg_idx = si - 1
						break
				var seg_len: float = arc_lengths[seg_idx + 1] - arc_lengths[seg_idx]
				var t := 0.0
				if seg_len > 0.001:
					t = (sd - arc_lengths[seg_idx]) / seg_len
				var sample_pos: Vector3 = current_drawn_path[seg_idx].lerp(current_drawn_path[seg_idx + 1], t)

				# Compute path direction at this point
				var path_fwd: Vector3
				if seg_idx + 1 < path_count:
					path_fwd = current_drawn_path[seg_idx + 1] - current_drawn_path[seg_idx]
				else:
					path_fwd = current_drawn_path[path_count - 1] - current_drawn_path[path_count - 2]
				path_fwd.y = 0.0
				if path_fwd.length() < 0.001:
					path_fwd = Vector3.FORWARD
				else:
					path_fwd = path_fwd.normalized()

				# Rotation angle from FORWARD to path direction
				var rot_angle := atan2(path_fwd.x, path_fwd.z)

				# Draw formation markers at this sample point
				for key in _dyn_offsets:
					var dyn_off: Vector3 = _dyn_offsets[key]
					var rotated := Vector3(dyn_off.x, 0.0, dyn_off.z).rotated(Vector3.UP, rot_angle) * eff_scale
					var mpos := sample_pos + rotated + offset
					immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
					immediate_mesh.surface_add_vertex(mpos + Vector3(-marker_sz, 0, 0))
					immediate_mesh.surface_add_vertex(mpos + Vector3(marker_sz, 0, 0))
					immediate_mesh.surface_add_vertex(mpos + Vector3(0, 0, -marker_sz))
					immediate_mesh.surface_add_vertex(mpos + Vector3(0, 0, marker_sz))
					immediate_mesh.surface_end()
		return

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

	var width := 0.0
	if build_draw_mode == DRAW_MODE_CIRCLE:
		width = circle_radius * 1.5
	else:
		var pairs_val := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
		width = float(pairs_val * 2) * brush_lane_spacing

	var lane_count := 1
	if width > 0.05:
		lane_count = int(width / brush_lane_spacing) + 1
		if lane_count % 2 == 0:
			lane_count += 1
	
	var center_index := float(lane_count - 1) / 2.0

	for lane_index in range(lane_count):
		if lane_index == int(center_index):
			continue

		var factor := float(lane_index) - center_index
		var spacing_to_use := brush_lane_spacing
		if lane_count > 1:
			spacing_to_use = width / float(lane_count - 1)
		
		var lateral_offset_scale := factor * spacing_to_use

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
		if rat == null:
			continue
		if rat.is_fallen:
			continue
		if (rat.state == rat.State.FOLLOW or rat.state == rat.State.ATTACK_PATH) and not rat.is_carrier:
			available_rats.append(rat)
	return available_rats


func _is_pos_too_close_to_player(pos: Vector3) -> bool:
	if _player == null:
		return false
	if abs(pos.y - _player.global_position.y) > 2.0:
		return false
	var dist_sq = Vector2(pos.x, pos.z).distance_squared_to(Vector2(_player.global_position.x, _player.global_position.z))
	return dist_sq < (0.9 * 0.9)


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
				var p := center + off
				if not _is_pos_too_close_to_player(p):
					positions.append(p)
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
	# Ignore if we are actively drawing a path
	if mouse_is_down_left and not _lmb_is_object_drag:
		return

	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		immediate_mesh.clear_surfaces()
		return

	immediate_mesh.clear_surfaces()
	if line_material:
		line_material.albedo_color = _brush_color(Color(0.8, 0.85, 1.0, 0.7))

	if _dyn_offsets.is_empty():
		return

	var offset := Vector3(0, 0.1, 0)
	var effective_scale := formation_scale * _dyn_base_radius
	var mark_size := 0.12

	# Draw small cross markers at each rat's formation position
	for key in _dyn_offsets:
		var dyn_off: Vector3 = _dyn_offsets[key]
		var pos := mouse_world + dyn_off * effective_scale + offset
		immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		immediate_mesh.surface_add_vertex(pos + Vector3(-mark_size, 0, 0))
		immediate_mesh.surface_add_vertex(pos + Vector3(mark_size, 0, 0))
		immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, -mark_size))
		immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, mark_size))
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
	var available_rats := _get_available_follow_rats()
	var total_rats := available_rats.size()
	var enough_rats := total_rats >= required

	if line_material:
		if invalid_surface:
			line_material.albedo_color = _brush_color(Color(1, 0, 0))
		else:
			line_material.albedo_color = _brush_color(Color.WHITE if enough_rats else Color(1, 0, 0))

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
		
	var target_positions: Array[Vector3] = []
	
	if rat_count == 1:
		var single_pos := current_drawn_path[0]
		target_positions.append(single_pos)
	else:
		var dist_between_rats = path_length / float(rat_count - 1)
		for i in range(rat_count):
			if i == 0:
				var start_pos := current_drawn_path[0]
				if use_wide_brush and rat_count > 2:
					start_pos = current_drawn_path[0]
				target_positions.append(start_pos)
				continue
			elif i == rat_count - 1:
				var end_pos := current_drawn_path[-1]
				if use_wide_brush and rat_count > 2:
					end_pos = current_drawn_path[-1]
				target_positions.append(end_pos)
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
			
			if true: # removed use_wide_brush restriction
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
	
			target_positions.append(interp_pos)

	var valid_positions: Array[Vector3] = []
	for p in target_positions:
		if not _is_pos_too_close_to_player(p):
			valid_positions.append(p)
			
	var assign_count = min(available_rats.size(), valid_positions.size())
	for i in range(assign_count):
		available_rats[i].build_at(valid_positions[i])
		
	if assign_count > 0:
		_build_force_timer = max(0.1, build_force_timeout)


func _send_attack_wave() -> void:
	if current_drawn_path.size() < 2:
		return

	var available_rats: Array = []
	for rat in rats:
		if rat.state == rat.State.FOLLOW and not rat.is_carrier:
			available_rats.append(rat)

	if available_rats.size() == 0:
		return

	var effective_scale := formation_scale * _dyn_base_radius

	# Compute reference lateral direction from path start
	var ref_dir: Vector3 = current_drawn_path[1] - current_drawn_path[0]
	ref_dir.y = 0.0
	if ref_dir.length() < 0.001:
		ref_dir = Vector3.FORWARD
	else:
		ref_dir = ref_dir.normalized()
	var ref_lateral := ref_dir.cross(Vector3.UP).normalized()

	for rat in available_rats:
		var rat_id: int = rat.get_instance_id()
		var formation_off := Vector3.ZERO
		if _dyn_offsets.has(rat_id):
			var dyn_off: Vector3 = _dyn_offsets[rat_id]
			formation_off = dyn_off * effective_scale

		var rat_path := PackedVector3Array()

		for i in range(current_drawn_path.size()):
			var p = current_drawn_path[i]
			if formation_off.length() > 0.01:
				var dir: Vector3
				if i == 0:
					dir = current_drawn_path[1] - current_drawn_path[0]
				elif i == current_drawn_path.size() - 1:
					dir = current_drawn_path[i] - current_drawn_path[i-1]
				else:
					var in_dir = current_drawn_path[i] - current_drawn_path[i-1]
					var out_dir = current_drawn_path[i+1] - current_drawn_path[i]
					in_dir.y = 0.0
					out_dir.y = 0.0
					if in_dir.length() > 0.001 and out_dir.length() > 0.001:
						dir = (in_dir.normalized() + out_dir.normalized())
					else:
						dir = Vector3.FORWARD
				dir.y = 0.0
				if dir.length() < 0.001:
					dir = Vector3.FORWARD
				else:
					dir = dir.normalized()
				var lateral_dir := dir.cross(Vector3.UP).normalized()
				# Use full 2D formation offset rotated to path orientation
				var lat_component := formation_off.dot(ref_lateral)
				var fwd_component := formation_off.dot(ref_dir)
				p += lateral_dir * lat_component + dir * fwd_component
			rat_path.append(p)

		rat.set_attack_path(rat_path)


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

	# All available rats participate in carrying
	var needed: int = count
	
	if needed <= 0:
		return

	# Make radius just outside the object
	var ring_radius := obj_max_extent + 0.3

	obj.get("carrier_rats").clear()
	obj.set("carrier_available_max", count)
	obj.set("carrier_brush_desired", count)

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
		grabbed_object.set_meta("is_being_dragged", false)
		grabbed_object = null
		grabbed_object_last_pos = Vector3.ZERO
		_lmb_is_object_drag = false


func _check_carrier_arrival() -> void:
	if grabbed_object == null or grabbed_object.get("is_surrounded"):
		return
	
	var carriers = grabbed_object.get("carrier_rats")
	if carriers == null or carriers.is_empty():
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
	var arrived_count := 0
	var total_count := 0
	for r in carriers:
		if r == null:
			continue
		total_count += 1
		var flat_pos := Vector2(r.global_position.x, r.global_position.z)
		var flat_target := Vector2(r.blob_target.x, r.blob_target.z)
		if flat_pos.distance_squared_to(flat_target) <= arrival_dist_sq:
			arrived_count += 1
			
	var required_to_start: int = max(1, total_count / 2)
	
	if arrived_count >= required_to_start:
		grabbed_object.set("is_surrounded", true)


func _process_object_drag(delta: float) -> void:
	if grabbed_object == null:
		return

	if not grabbed_object.get("is_surrounded"):
		return

	var current_pos: Vector3 = grabbed_object.global_position
	var target_pos := _get_mouse_pos_at_y(current_pos.y)
	if target_pos == Vector3.ZERO:
		return

	var to_cursor := target_pos - current_pos
	if to_cursor.length() > box_drag_max_radius:
		target_pos = current_pos + to_cursor.normalized() * box_drag_max_radius

	var step: float = max(0.0, box_drag_speed) * delta
	grabbed_object.global_position = current_pos.move_toward(target_pos, step)


func _get_brush_ratio(value: float, min_v: float, max_v: float) -> float:
	if max_v <= min_v:
		return 0.0
	return clampf((value - min_v) / (max_v - min_v), 0.0, 1.0)


func _get_brush_thickness_t() -> float:
	return _get_brush_ratio(formation_scale, formation_scale_min, formation_scale_max)


func _get_effective_attack_path_length() -> float:
	var t := _get_brush_thickness_t()
	return lerpf(attack_path_length_max, attack_path_length_min, t)


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

func _get_carrier_arrival_ratio() -> float:
	if grabbed_object == null:
		return 0.0
	var carriers = grabbed_object.get("carrier_rats")
	if carriers == null or carriers.is_empty():
		return 0.0
	var arrival_dist_sq := 0.2 * 0.2
	var arrived := 0
	var total := 0
	for r in carriers:
		if r == null:
			continue
		total += 1
		var flat_pos := Vector2(r.global_position.x, r.global_position.z)
		var flat_target := Vector2(r.blob_target.x, r.blob_target.z)
		if flat_pos.distance_squared_to(flat_target) <= arrival_dist_sq:
			arrived += 1
	if total <= 0:
		return 0.0
	return clampf(float(arrived) / float(total), 0.0, 1.0)


func _get_nearest_available_rats(center: Vector3) -> Array[CharacterBody3D]:
	var nearby: Array[CharacterBody3D] = []
	var others: Array[CharacterBody3D] = []
	var radius_sq := carrier_pick_radius * carrier_pick_radius

	for rat in rats:
		if rat == null:
			continue
		if rat.is_fallen:
			continue
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


func _get_player_movement_rat_requirement() -> int:
	if _player == null:
		return 0
	if _player.has_method("get_required_available_rats_for_movement"):
		return maxi(0, int(_player.get_required_available_rats_for_movement()))
	if "required_available_rats_for_movement" in _player:
		return maxi(0, int(_player.get("required_available_rats_for_movement")))
	return 0



func _player_has_enough_rats_to_move() -> bool:
	var required := _get_player_movement_rat_requirement()
	if required <= 0:
		return true
	return get_available_rat_count() >= required


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
