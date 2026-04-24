extends Node3D

const SoundWaveScene := preload("res://scenes/effects/sound_wave.tscn")

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

@export var rat_scene: PackedScene = preload("res://scenes/rat/rat.tscn")
@export var rat_count: int = 42
@export var min_cap: int = 42
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
var respawn_count: int = 60
var saved_rat_composition: Array[int] = []

func save_rat_composition() -> void:
	saved_rat_composition.clear()
	for rat in rats:
		if is_instance_valid(rat):
			saved_rat_composition.append(int(rat.get("rat_type")))
	respawn_count = saved_rat_composition.size()

var mode: int = 1 # Always BUILD-like unified mode

var buff_red_timer: float = 0.0
var buff_green_timer: float = 0.0
var buff_yellow_timer: float = 0.0
var buff_purple_timer: float = 0.0

var buff_mat_red: StandardMaterial3D
var buff_mat_green: StandardMaterial3D
var buff_mat_yellow: StandardMaterial3D
var buff_mat_purple: StandardMaterial3D

func get_current_buff_material():
	if buff_red_timer > 0.0: return buff_mat_red
	if buff_green_timer > 0.0: return buff_mat_green
	if buff_yellow_timer > 0.0: return buff_mat_yellow
	if buff_purple_timer > 0.0: return buff_mat_purple
	return null

var _cheese_msg_timer: float = 0.0
var _cheese_buff_label: Label = null

func _show_cheese_msg(msg: String, color: Color) -> void:
	if _cheese_buff_label:
		_cheese_buff_label.text = msg
		_cheese_buff_label.add_theme_color_override("font_color", color)
		_cheese_buff_label.visible = true
		_cheese_msg_timer = 3.0

func apply_cheese_buff(type: int) -> void:
	match type:
		0: 
			buff_red_timer = 5.0
			_show_cheese_msg("Agresywne szczury!", Color(0.9, 0.1, 0.1))
		1: 
			buff_green_timer = 5.0
			_show_cheese_msg("Śmierdzące szczury!", Color(0.1, 0.9, 0.1))
		2: 
			buff_yellow_timer = 5.0
			_show_cheese_msg("Nieśmiertelne szczury!", Color(0.9, 0.9, 0.1))
		3: 
			buff_purple_timer = 5.0
			_show_cheese_msg("Dezorientacja szczurów!", Color(0.6, 0.1, 0.9))

# Drawing & Blob
var built_positions: Dictionary = {}
var mouse_is_down_left: bool = false
var left_click_start_pos: Vector2 = Vector2(-1, -1)
var is_dragging_left: bool = false
var drag_threshold_squared: float = 100.0 # 10 pixels squared threshold

var mouse_is_down_right: bool = false
var combat_rmb_down: bool = false

var cached_mouse_world: Vector3 = Vector3.ZERO
var _mouse_cached_frame: int = -1

func get_mouse_world() -> Vector3:
	var f := Engine.get_frames_drawn()
	if _mouse_cached_frame != f:
		_mouse_cached_frame = f
		cached_mouse_world = _mouse_to_world()
	return cached_mouse_world

enum AttackMode { ROTATION, BLOB, PATH_DASH }
var current_attack_mode: AttackMode = AttackMode.PATH_DASH
var _combat_blob_offsets: Array[Vector3] = []
var blob_radius: float = 2.5
var _blob_damage_timer: float = 0.0
var blob_damage_interval: float = 0.5
var blob_damage_per_tick: float = 10.0
var _blob_drag_pos: Vector3 = Vector3.ZERO
var _stuck_enemies: Array[Node3D] = []

func _release_all_stuck_enemies() -> void:
	for e in _stuck_enemies:
		if is_instance_valid(e):
			e.set("is_stuck_in_blob", false)
	_stuck_enemies.clear()

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
var min_point_dist_squared: float = 0.05
@export var _pity_toggle: bool = false 
@export var _pity_timer: float = 5.0
var _pity_canvas: CanvasLayer = null
var _pity_label: Label = null

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
@export var path_dash_length_min: float = 8.0
@export var path_dash_length_max: float = 28.0

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
@export var allow_player_drag: bool = false
@export var wild_lifespan_override_default: float = -1.0
@export var wild_lifespan_overrides: Dictionary = {}
@export var wild_recruit_by_rats: bool = true
@export var wild_recruit_by_rats_range: float = 1.5
@export var object_rotation_step: float = 22.5
@export var combat_circle_radius: float = 1.8
@export var combat_circle_rotation_speed: float = 12.0

@export var rats_collide_with_walls: bool = true:
	set(value):
		rats_collide_with_walls = value
		for rat in rats:
			if rat.has_method("set_wall_collision"):
				rat.set_wall_collision(value)

var _hovered_object: Node3D = null

var line_mesh_instance: MeshInstance3D
var immediate_mesh: ImmediateMesh
var line_material: StandardMaterial3D

var unified_shape_combiner: CSGCombiner3D

# ── Blob offsets (sunflower pattern) ──────────────────────────────────────────
const BLOB_RADIUS_BASE: float = 2.6
const BLOB_SPREAD: float = 0.3
var _blob_offsets: Array[Vector3] = []

# ── Combat draw (stream/arc) ──────────────────────────────────────────────────
const STREAM_SPACING: float = 0.7
const DRAW_SAMPLE_DIST: float = 0.2
const MOUSE_TRAIL_MAX: int = 500
var _mouse_trail: Array[Vector3] = []   # continuous mouse position history
var _mouse_trail_last: Vector3 = Vector3.ZERO
var _build_in_progress: bool = false
var _combat_circle_angle: float = 0.0
var _combat_offsets: Dictionary = {}
var _combat_offsets_ready: bool = false

const BRUSH_DIM_FACTOR: float = 0.6

@export var formation_batch_size: int = 8
var _formation_queue: Array[Rat] = []
var _formation_index: int = 0
var _formation_active: bool = false



# ── Sound Wave Effect ─────────────────────────────────────────────────────────
var _sound_wave: Node3D = null

# ── Neighbor throttle ─────────────────────────────────────────────────────────
@export var neighbor_radius: float = 1.5
@export var neighbor_max_count: int = 8
const NEIGHBOR_TICK: int = 3
var _neighbor_tick: int = 0
@export var heavy_cursor_follow_threshold: int = 80
@export var heavy_cursor_follow_interval: float = 0.05
var _cursor_follow_timer: float = 0.0

# Green gas emission budget (global) to avoid perf spikes
@export var gas_emit_per_second: float = 25.0
@export var gas_emit_budget_max: float = 20.0
var _gas_emit_budget: float = 0.0


# ── Structure Integrity ──
@export var structure_max_integrity: float = 100.0
var structure_integrity: float = structure_max_integrity
@export var structure_decay_on_laser: float = 25.0 # integrity loss per second
@export var structure_decay_on_projectile: float = 20.0 # integrity loss per hit
@export var structure_lifetime: float = 0.0 # seconds before wall crumbles (0 = never)
var _structure_timer: float = 0.0


func _ready() -> void:
	# Ensure GasDamageManager exists for optimized gas effects
	if get_tree().get_first_node_in_group("gas_damage_manager") == null:
		var gdm_script = load("res://scripts/systems/gas_damage_manager.gd")
		if gdm_script:
			var gdm = Node.new()
			gdm.set_script(gdm_script)
			gdm.name = "GasDamageManager"
			add_child(gdm)

	add_to_group("rat_manager")
	_clamp_caps()

	buff_mat_red = StandardMaterial3D.new()
	buff_mat_red.albedo_color = Color(0.9, 0.1, 0.1)
	buff_mat_green = StandardMaterial3D.new()
	buff_mat_green.albedo_color = Color(0.1, 0.9, 0.1)
	buff_mat_yellow = StandardMaterial3D.new()
	buff_mat_yellow.albedo_color = Color(0.9, 0.9, 0.1)
	buff_mat_purple = StandardMaterial3D.new()
	buff_mat_purple.albedo_color = Color(0.6, 0.1, 0.9)

	immediate_mesh = ImmediateMesh.new()
	line_mesh_instance = MeshInstance3D.new()
	
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

	_pity_canvas = CanvasLayer.new()
	_pity_canvas.layer = 100
	var control := Control.new()
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pity_canvas.add_child(control)
	
	_pity_label = Label.new()
	_pity_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pity_label.text = "5.0"
	_pity_label.add_theme_font_size_override("font_size", 64)
	_pity_label.add_theme_color_override("font_color", Color.RED)
	_pity_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_pity_label.add_theme_constant_override("outline_size", 8)
	_pity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pity_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pity_label.visible = false
	control.add_child(_pity_label)
	
	_cheese_buff_label = Label.new()
	_cheese_buff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cheese_buff_label.add_theme_font_size_override("font_size", 52)
	_cheese_buff_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_cheese_buff_label.add_theme_constant_override("outline_size", 8)
	_cheese_buff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cheese_buff_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cheese_buff_label.offset_top = 150 # Position it down from the top
	_cheese_buff_label.visible = false
	control.add_child(_cheese_buff_label)
	
	add_child(_pity_canvas)

	# ── Sound Wave ──
	if SoundWaveScene:
		_sound_wave = SoundWaveScene.instantiate()
		add_child(_sound_wave)

func setup_player(player: CharacterBody3D) -> void:
	_player = player
	if _player and not _player.is_in_group("player"):
		_player.add_to_group("player")
		
	if _player.has_signal("player_died") and not _player.player_died.is_connected(_on_player_died):
		_player.player_died.connect(_on_player_died)
		
	# Spawn initial rats using current-level rat spawn markers when available.
	# Falls back to player position inside _spawn_rats() when no markers exist.
	_spawn_rats(rat_count)
	respawn_count = max(respawn_count, rats.size())


func set_respawn_count(count: int) -> void:
	respawn_count = max(0, count)

func are_rats_hidden() -> bool:
	if combat_rmb_down:
		return false
	if build_draw_mode == DRAW_MODE_CIRCLE:
		return circle_radius >= 2.0
	elif build_draw_mode == DRAW_MODE_PATH:
		return brush_lane_pairs >= 2
	return false

func _on_player_died() -> void:
	for wild in get_tree().get_nodes_in_group("wild_rats"):
		if is_instance_valid(wild):
			wild.queue_free()
	for item in get_tree().get_nodes_in_group("dropped_items"):
		if is_instance_valid(item):
			item.queue_free()

	for r in rats.duplicate():
		if is_instance_valid(r) and r.has_method("die"):
			r.die()
	rats.clear()
	_spawn_rats_near_player(respawn_count)


func _clamp_caps() -> void:
	pass


func get_total_rat_count() -> int:
	var count := 0
	for rat in rats:
		if rat != null:
			count += 1
	return count


func get_wild_lifespan_for_level(level_id: int) -> float:
	if wild_lifespan_overrides.has(level_id):
		return float(wild_lifespan_overrides[level_id])
	return wild_lifespan_override_default


func get_min_cap() -> int:
	return 0


func increase_min_cap(_amount: int) -> void:
	pass


func restore_to_min(_require_empty: bool = false) -> void:
	pass


func ensure_min_cap() -> void:
	pass


func _spawn_rats(count: int) -> void:
	if count <= 0:
		return
	if rat_scene == null:
		push_error("rat_scene is not set in RatManager.")
		return

	var parent_node := get_parent()
	if parent_node == null:
		parent_node = self

	var base_pos := global_position
	if _player:
		base_pos = _player.global_position
	var spawn_nodes: Array[Node3D] = []
	var current_scene := get_tree().current_scene
	var spawns: Array = []
	if current_scene != null and current_scene.has_method("get_current_level_rat_spawns"):
		spawns = current_scene.get_current_level_rat_spawns()
	else:
		spawns = get_tree().get_nodes_in_group("rat_spawn")
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
		
		# If this spawn matches our saved respawn state, restore the saved types
		if count == respawn_count and i < saved_rat_composition.size():
			if saved_rat_composition[i] > 0 and rat.has_method("set_rat_type"):
				rat.set_rat_type(saved_rat_composition[i])
				
		parent_node.add_child(rat)
		if _player:
			rat.add_collision_exception_with(_player)
			_player.add_collision_exception_with(rat)
		register_rat(rat)

	build_blob_offsets()


func _get_nearest_spawn_pos() -> Vector3:
	var base_pos := global_position
	if _player:
		base_pos = _player.global_position
	var spawns: Array = []
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_current_level_rat_spawns"):
		spawns = current_scene.get_current_level_rat_spawns()
	else:
		spawns = get_tree().get_nodes_in_group("rat_spawn")
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
		
		# If this spawn matches our saved respawn state, restore the saved types
		if count == respawn_count and i < saved_rat_composition.size():
			if saved_rat_composition[i] > 0 and rat.has_method("set_rat_type"):
				rat.set_rat_type(saved_rat_composition[i])
				
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
	pass


func _restore_to_min_near_player() -> void:
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
		var angle := randf() * TAU
		var radius := randf_range(spawn_radius_min, spawn_radius_max)
		var pos := _player.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		r.force_respawn_at_position(pos)
		needed -= 1

	if needed > 0:
		_spawn_rats_at_center(needed, _player.global_position)


func _check_rat_spawn_bonus() -> void:
	# Rat spawns are currently disabled; respawn happens near the player.
	return


func _process(delta: float) -> void:
	if _build_force_timer > 0.0:
		_build_force_timer = max(0.0, _build_force_timer - delta)
	if _min_respawn_cooldown > 0.0:
		_min_respawn_cooldown = max(0.0, _min_respawn_cooldown - delta)
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

	if buff_red_timer > 0.0: buff_red_timer -= delta
	if buff_green_timer > 0.0: buff_green_timer -= delta
	if buff_yellow_timer > 0.0: buff_yellow_timer -= delta
	if buff_purple_timer > 0.0: buff_purple_timer -= delta
	if gas_emit_per_second > 0.0:
		_gas_emit_budget = min(gas_emit_budget_max, _gas_emit_budget + gas_emit_per_second * delta)

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
	_update_sound_wave()
	_process_hover()
	if structure_lifetime > 0.0 and _has_static_rats():
		_structure_timer += delta
		if _structure_timer >= structure_lifetime:
			recall_all_rats()
			structure_integrity = structure_max_integrity
			_structure_timer = 0.0

	# ── Neighbor throttle ──
	_neighbor_tick += 1
	if _neighbor_tick >= NEIGHBOR_TICK:
		_neighbor_tick = 0
		_assign_neighbors()

	# ── Cursor Preview ──
	_update_cursor_preview()
	_check_empty_respawn()
	_check_rat_spawn_bonus()
	_process_damage(delta)

	# Reset game if all rats die (with pity timer)
	if get_total_rat_count() <= 0 and _player != null:
		if _pity_toggle == true:
			_pity_timer -= delta
			if _pity_label:
				_pity_label.visible = true
				_pity_label.text = "Znajdź nowe szczury\n%.1f" % maxf(0.0, _pity_timer)
			if _pity_timer <= 0.0:
				if _player.has_method("die"):
					_player.die()
	else:
		_pity_timer = 5.0
		if _pity_label:
			_pity_label.visible = false
		
	if _cheese_msg_timer > 0.0:
		_cheese_msg_timer -= delta
		if _cheese_msg_timer <= 0.0 and _cheese_buff_label:
			_cheese_buff_label.visible = false
		if _pity_label:
			_pity_label.visible = false


func _process_damage(_delta: float) -> void:
	if not combat_rmb_down or current_attack_mode != AttackMode.ROTATION:
		return

	var enemies: Array = []
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_nodes_in_current_level"):
		enemies.append_array(current_scene.get_nodes_in_current_level("enemies"))
		enemies.append_array(current_scene.get_nodes_in_current_level("bosses"))
	else:
		enemies = get_tree().get_nodes_in_group("enemies")
		enemies += get_tree().get_nodes_in_group("bosses")
	if enemies.is_empty() or rats.is_empty():
		return

	# Use the grid from _assign_neighbors if possible, but that's throttled.
	# For better responsiveness, we can do a simpler spatial check or just use the throttled one.
	# Let's build a quick grid here for this frame, or just iterate enemies if they are few.
	# Usually enemies < 50, rats > 100. Iterating enemies and checking nearby rats is faster.
	
	var cell_size: float = 1.5
	var grid := {}
	for rat in rats:
		if not is_instance_valid(rat) or rat.is_fallen:
			continue
		if rat.is_carrier or rat.state != rat.State.FOLLOW:
			continue
		var pos := rat.global_position
		var key := Vector2i(int(floor(pos.x / cell_size)), int(floor(pos.z / cell_size)))
		if not grid.has(key): grid[key] = []
		grid[key].append(rat)
		
	var dmg_mult = 1.0
	var dmg_color = Color.WHITE
	if buff_red_timer > 0.0:
		dmg_mult = 2.0
		dmg_color = Color(0.9, 0.1, 0.1)

	for enemy: Node3D in enemies:
		if not is_instance_valid(enemy): continue
		var e_pos := enemy.global_position
		var ex := int(floor(e_pos.x / cell_size))
		var ez := int(floor(e_pos.z / cell_size))
		
		# Check 3x3 cells around enemy
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var key := Vector2i(ex + dx, ez + dz)
				if grid.has(key):
					for rat in grid[key]:
						var dist_sq = e_pos.distance_squared_to(rat.global_position)
						if dist_sq < rat.hit_range * rat.hit_range:
							if rat.attack_cooldown <= 0.0:
								enemy.take_damage(rat.damage_per_hit * dmg_mult, rat.get_instance_id(), rat.global_position, dmg_color)
								rat.attack_cooldown = 0.5 # Passive damage cooldown per rat per enemy (effectively)


func _update_edge_avoidance() -> void:
	for rat in rats:
		var r := rat as Rat
		if r:
			# Rats traveling to build or already placed don't need edge avoidance
			# (it's already skipped in _should_block_edge), but FOLLOW rats
			# must keep it ON even while the player is drawing, so they don't
			# push each other off the edge.
			if r.state == Rat.State.TRAVEL_TO_BUILD or r.state == Rat.State.WAITING_FOR_FORMATION or r.state == Rat.State.STATIC:
				r.edge_avoidance_enabled = false
			else:
				r.edge_avoidance_enabled = true


# ── COMBAT: arc/stream follow ──────────────────────────────────────────────────

func _get_active_follow_rats() -> Array[CharacterBody3D]:
	var active: Array[CharacterBody3D] = []
	for rat in rats:
		if is_instance_valid(rat) and not rat.is_carrier and rat.state == rat.State.FOLLOW:
			active.append(rat)
	return active


func _update_mouse_trail(mouse_world: Vector3) -> void:
	if _mouse_trail.is_empty():
		_mouse_trail.append(mouse_world)
		_mouse_trail_last = mouse_world
	elif mouse_world.distance_to(_mouse_trail_last) >= DRAW_SAMPLE_DIST:
		_mouse_trail.append(mouse_world)
		_mouse_trail_last = mouse_world
		if _mouse_trail.size() > MOUSE_TRAIL_MAX:
			_mouse_trail.pop_front()


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

	_combat_blob_offsets.clear()
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i in range(count):
		var r := 0.2 + 1.2 * sqrt(float(i + 1) / float(count))
		var a := golden_angle * float(i)
		_combat_blob_offsets.append(Vector3(cos(a) * r, 0.0, sin(a) * r))

	_blob_drag_pos = mouse_world
	_combat_offsets_ready = true


func _update_combat_attack_circle(delta: float) -> void:
	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		return

	_update_mouse_trail(mouse_world)

	if current_attack_mode == AttackMode.PATH_DASH:
		if combat_rmb_down:
			if current_drawn_path.size() > 0:
				var capped_mouse_world := _get_capped_path_dash_point(mouse_world)
				var last_pos := current_drawn_path[-1]
				if capped_mouse_world.distance_squared_to(last_pos) > min_point_dist_squared:
					current_drawn_path.append(capped_mouse_world)
				_update_drawn_line(capped_mouse_world)
		return

	var active := _get_active_follow_rats()
	var count := active.size()
	if count == 0:
		return

	if current_attack_mode == AttackMode.BLOB:
		_blob_drag_pos = _blob_drag_pos.lerp(mouse_world, delta * 0.625)
		
		_blob_damage_timer -= delta
		var tick_damage = false
		if _blob_damage_timer <= 0.0:
			tick_damage = true
			_blob_damage_timer = blob_damage_interval
			
		var actual_blob_center = Vector3.ZERO
		if count > 0:
			for rat in active:
				actual_blob_center += rat.global_position
			actual_blob_center /= count
			
		for i in range(count):
			var t := _blob_drag_pos
			if i < _combat_blob_offsets.size():
				t += _combat_blob_offsets[i]
			t.y = mouse_world.y
			active[i].set_target(t)
			
		var enemies: Array = []
		var current_scene := get_tree().current_scene
		if current_scene != null and current_scene.has_method("get_nodes_in_current_level"):
			enemies.append_array(current_scene.get_nodes_in_current_level("enemies"))
			enemies.append_array(current_scene.get_nodes_in_current_level("bosses"))
		else:
			enemies = get_tree().get_nodes_in_group("enemies")
			enemies += get_tree().get_nodes_in_group("bosses")
		
		# We already know count > 0 from the start
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.has_method("take_damage") and not enemy.get("_is_dead"):
				var dist = enemy.global_position.distance_to(actual_blob_center)
				var is_already_stuck = _stuck_enemies.has(enemy)
				if is_already_stuck or dist <= blob_radius:
					if not is_already_stuck:
						_stuck_enemies.append(enemy)
					enemy.set("is_stuck_in_blob", true)
					enemy.set("blob_center", actual_blob_center)
					if tick_damage:
						enemy.take_damage(blob_damage_per_tick)
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


func _update_cursor_follow(_delta: float) -> void:
	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		return

	_update_mouse_trail(mouse_world)

	var active := _get_active_follow_rats()
	var count := active.size()
	if count == 0:
		return

	# Need at least 2 points for arc distribution
	if _mouse_trail.size() < 2:
		if _blob_offsets.size() != count:
			build_blob_offsets()
			
		var blob_scale_local := 1.0
		var use_path_logic: bool = (build_draw_mode == DRAW_MODE_PATH and use_wide_brush) or (current_attack_mode == AttackMode.PATH_DASH)
		if use_path_logic:
			var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
			blob_scale_local = float(1 + pairs * 2) / 2.5
		else:
			blob_scale_local = maxf(1.0, circle_radius / 0.5)
			
		for i in range(count):
			var t_blob := mouse_world
			if i < _blob_offsets.size():
				t_blob += _blob_offsets[i] * blob_scale_local
			t_blob.y = mouse_world.y
			active[i].set_target(t_blob)
		return

	# Arc-length parameterization of the trail
	var arc := PackedFloat32Array()
	arc.resize(_mouse_trail.size())
	arc[0] = 0.0
	for i in range(1, _mouse_trail.size()):
		arc[i] = arc[i - 1] + _mouse_trail[i].distance_to(_mouse_trail[i - 1])
	var total: float = arc[-1]

	# Calculate how much to resemble a blob based on brush size
	var blob_blend := 0.0
	var blob_scale := 1.0
	var use_path_logic_b: bool = (build_draw_mode == DRAW_MODE_PATH and use_wide_brush) or (current_attack_mode == AttackMode.PATH_DASH)
	if use_path_logic_b:
		blob_blend = clampf(float(brush_lane_pairs - brush_lane_pairs_min) / maxf(1.0, float(brush_lane_pairs_max - brush_lane_pairs_min)), 0.0, 1.0)
		var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
		blob_scale = float(1 + pairs * 2) / 2.5
	else:
		blob_blend = clampf((circle_radius - circle_radius_min) / max(0.1, circle_radius_max - circle_radius_min), 0.0, 1.0)
		blob_scale = circle_radius / 0.5

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
			# Optimized: search once
			var lo := arc.bsearch(arc_pos) - 1
			lo = clampi(lo, 0, arc.size() - 2)
			var hi := lo + 1
			
			var seg: float = arc[hi] - arc[lo]
			if seg < 0.0001:
				t_stream = _mouse_trail[lo]
			else:
				var t: float = (arc_pos - arc[lo]) / seg
				t_stream = (_mouse_trail[lo] as Vector3).lerp(_mouse_trail[hi] as Vector3, t)

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

func _update_free_rats_follow_cursor(delta: float) -> void:
	# Skip when RMB attack or LMB building is handling rats
	if combat_rmb_down:
		return
	if mouse_is_down_left and not _lmb_is_object_drag:
		return
	# Throttle heavy cursor-follow updates when many rats are active
	if rats.size() >= heavy_cursor_follow_threshold:
		_cursor_follow_timer -= delta
		if _cursor_follow_timer > 0.0:
			return
		_cursor_follow_timer = heavy_cursor_follow_interval
	else:
		_cursor_follow_timer = 0.0
	_update_cursor_follow(delta)


func _update_sound_wave() -> void:
	if _sound_wave == null or not is_instance_valid(_sound_wave):
		return
	if _player == null:
		return
	if not _sound_wave.has_method("update_wave"):
		return

	# Compute centroid of active follow rats
	var centroid := Vector3.ZERO
	var count := 0
	for rat in rats:
		if not is_instance_valid(rat):
			continue
		if rat.is_fallen:
			continue
		if "state" in rat and rat.state != rat.State.FOLLOW:
			continue
		centroid += rat.global_position
		count += 1

	if count == 0:
		_sound_wave.visible = false
		return

	centroid /= float(count)

	var start_pos := _player.global_position + Vector3(0.0, 0.4, 0.0)
	_sound_wave.update_wave(start_pos, centroid)



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
	var grid := {}
	var effective_radius := maxf(0.2, neighbor_radius)
	var cell_size: float = effective_radius
	var radius_sq := effective_radius * effective_radius

	# Bucket rats into spatial grid
	for i in range(count):
		var rat = rats[i]
		if not is_instance_valid(rat):
			continue
		var pos: Vector3 = rat.global_position
		var key := Vector2i(int(floor(pos.x / cell_size)), int(floor(pos.z / cell_size)))
		if grid.has(key):
			grid[key].append(rat)
		else:
			grid[key] = [rat]

	# Query grid for neighbors
	for i in range(count):
		var rat = rats[i]
		if not is_instance_valid(rat):
			continue
			
		# Minor optimization: skip for rats not in FOLLOW state
		if "state" in rat and rat.state != rat.State.FOLLOW:
			if rat.has_method("set_neighbors"):
				rat.set_neighbors([])
			continue

		var pos: Vector3 = rat.global_position
		var nb: Array = []
		var nb_distances: Array[float] = []
		var cx := int(floor(pos.x / cell_size))
		var cz := int(floor(pos.z / cell_size))

		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var ck := Vector2i(cx + dx, cz + dz)
				if grid.has(ck):
					for other in grid[ck]:
						if other != rat and is_instance_valid(other):
							var dist_sq := pos.distance_squared_to(other.global_position)
							if dist_sq < radius_sq:
								nb.append(other)
								nb_distances.append(dist_sq)

		if neighbor_max_count > 0 and nb.size() > neighbor_max_count:
			# Use a more efficient way to sort pairs in GDScript
			var pairs = []
			for idx in range(nb.size()):
				pairs.append([nb_distances[idx], nb[idx]])
			pairs.sort() # Sorts by first element (distance)
			
			nb = []
			for j in range(neighbor_max_count):
				nb.append(pairs[j][1])
								
		if rat.has_method("set_neighbors"):
			rat.set_neighbors(nb)


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
			
			var conn_box = CSGBox3D.new()
			conn_box.size = Vector3(radius * 2.0, current_height, dist)
			var center = (pos_a + pos_b) / 2.0
			unified_shape_combiner.add_child(conn_box)
			conn_box.global_position = center + Vector3(0, current_y_offset, 0)
			
			if dist > 0.001:
				var forward = (pos_b - pos_a).normalized()
				var up = Vector3.UP
				if abs(forward.y) > 0.99:
					up = Vector3.RIGHT
				conn_box.look_at_from_position(conn_box.global_position, conn_box.global_position + forward, up)
			
			conn_box.material = mat


# ── Input handling ────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1 or event.keycode == KEY_2 or event.keycode == KEY_3:
			current_attack_mode = AttackMode.PATH_DASH
			get_viewport().set_input_as_handled()
			return


	if wave_pending and event is InputEventMouseButton:
		var mb_wave := event as InputEventMouseButton
		if mb_wave.button_index == MOUSE_BUTTON_RIGHT and mb_wave.pressed:
			_fire_wave_at_mouse(mb_wave.position)
			wave_pending = false
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		
		# ── Scroll: rotate object if grabbed, otherwise change brush size ──
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if grabbed_object != null:
				# Rotate grabbed object
				var rot_dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				grabbed_object.rotate_y(deg_to_rad(object_rotation_step * rot_dir))
			else:
				# Change brush size
				var modify_lanes: bool = (build_draw_mode == DRAW_MODE_PATH and use_wide_brush) or current_attack_mode == AttackMode.PATH_DASH
				if modify_lanes:
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
					if mouse_is_down_left and not _lmb_is_object_drag:
						_update_circle_preview()

			get_viewport().set_input_as_handled()
			return

		# ── LMB: combat attack (Swarm Strike) ──
		if mb.button_index == MOUSE_BUTTON_LEFT:
			combat_rmb_down = mb.pressed
			if combat_rmb_down:
				var mouse_world := _mouse_to_world()
				if mouse_world != Vector3.ZERO:
					if current_attack_mode == AttackMode.PATH_DASH:
						current_drawn_path.clear()
						current_drawn_path.append(mouse_world)
						_has_last_build_pos = true
						_last_build_pos = mouse_world
						current_build_y = mouse_world.y
						is_dragging_left = true
					else:
						_capture_combat_offsets(mouse_world)
			else:
				if current_attack_mode == AttackMode.PATH_DASH and current_drawn_path.size() > 1:
					_trigger_path_dash()
				_combat_offsets_ready = false
				_combat_offsets.clear()
				_release_all_stuck_enemies()
				is_dragging_left = false
				current_drawn_path.clear()
				immediate_mesh.clear_surfaces()
			get_viewport().set_input_as_handled()
			return

		# ── RMB: raycast for object → drag, otherwise → do nothing ──
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				mouse_is_down_left = true
				left_click_start_pos = mb.position
				is_dragging_left = false
				_lmb_is_object_drag = false

				# Raycast to check if we clicked on a movable object
				var camera_m: Camera3D = get_viewport().get_camera_3d()
				var ray_origin_m: Vector3 = camera_m.project_ray_origin(mb.position)
				var ray_dir_m: Vector3 = camera_m.project_ray_normal(mb.position)
				var space_state_m := camera_m.get_world_3d().direct_space_state
				var query_m := PhysicsRayQueryParameters3D.create(ray_origin_m, ray_origin_m + ray_dir_m * 1000.0)
				query_m.collision_mask = 6
				var hit_m := space_state_m.intersect_ray(query_m)

				if hit_m:
					var obj = hit_m.collider
					var is_player_target : bool= obj != null and obj.is_in_group("player")
					var is_draggable : bool= obj is box or obj is turret or obj is hitscan_turret or is_player_target
					if is_draggable and (allow_player_drag or not is_player_target):
						# Start object drag mode
						_lmb_is_object_drag = true
						if not obj.is_surrounded:
							_surround_object_with_rats(obj)
						grabbed_object = obj
						if grabbed_object:
							grabbed_object.set_meta("is_being_dragged", true)
						grabbed_object_last_pos = obj.global_position
						get_viewport().set_input_as_handled()
						return

				# No object hit — abort building, building mechanic has been disabled
				mouse_is_down_left = false
				current_drawn_path.clear()
				current_build_y = -1000.0
				_has_last_build_pos = false
			else:
				# RMB released
				if _lmb_is_object_drag:
					# Release grabbed object
					if grabbed_object != null:
						grabbed_object.set_meta("is_being_dragged", false)
						_release_object_carriers(grabbed_object)
						grabbed_object = null
						grabbed_object_last_pos = Vector3.ZERO
				else:
					# Finalize build disabled, pass
					pass

				mouse_is_down_left = false
				_lmb_is_object_drag = false
				current_build_y = -1000.0
				is_drawing_line = false
				current_drawn_path.clear()
				_has_last_build_pos = false
				immediate_mesh.clear_surfaces()
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


func request_gas_emit() -> bool:
	if _gas_emit_budget <= 0.0:
		return false
	_gas_emit_budget -= 1.0
	return true


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


func _trigger_path_dash() -> void:
	if current_drawn_path.size() < 2:
		return
		
	var active := _get_active_follow_rats()
	var count := active.size()
	if count == 0:
		return

	var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
	var lane_count := 1 + pairs * 2
	var center_index := float(lane_count - 1) / 2.0
	
	for i in range(count):
		var rat = active[i]
		var lane_index := i % lane_count
		var factor := float(lane_index) - center_index
		var base_offset := brush_lane_spacing * factor
		var rand_offset := randf_range(-0.15, 0.15)
		
		if rat.has_method("start_path_dash"):
			rat.start_path_dash(current_drawn_path.duplicate(), base_offset + rand_offset)


func _get_path_dash_brush_t() -> float:
	return _get_brush_ratio(float(brush_lane_pairs), float(brush_lane_pairs_min), float(brush_lane_pairs_max))


func _get_path_dash_max_length() -> float:
	return lerpf(path_dash_length_max, path_dash_length_min, _get_path_dash_brush_t())


func _get_current_drawn_path_length() -> float:
	if current_drawn_path.size() < 2:
		return 0.0

	var length := 0.0
	for i in range(1, current_drawn_path.size()):
		length += current_drawn_path[i - 1].distance_to(current_drawn_path[i])
	return length


func _get_capped_path_dash_point(candidate: Vector3) -> Vector3:
	if current_drawn_path.is_empty():
		return candidate

	var last_pos: Vector3 = current_drawn_path[-1]
	var remaining := _get_path_dash_max_length() - _get_current_drawn_path_length()
	if remaining <= 0.0:
		return last_pos

	var segment_len := last_pos.distance_to(candidate)
	if segment_len <= remaining:
		return candidate
	return last_pos.move_toward(candidate, remaining)


func _get_path_dash_preview_lateral(center: Vector3) -> Vector3:
	var dir := Vector3.ZERO
	if combat_rmb_down and current_drawn_path.size() >= 1:
		dir = center - current_drawn_path[-1]
	elif current_drawn_path.size() >= 2:
		dir = current_drawn_path[-1] - current_drawn_path[-2]

	dir.y = 0.0
	if dir.length() <= 0.001:
		return Vector3.RIGHT
	return dir.normalized().cross(Vector3.UP).normalized()


func _draw_path_dash_brush_marker(center: Vector3, lateral: Vector3) -> void:
	var pairs := clampi(brush_lane_pairs, brush_lane_pairs_min, brush_lane_pairs_max)
	var lane_count := 1 + pairs * 2
	var half_width := maxf(0.25, float(max(1, lane_count - 1)) * brush_lane_spacing * 0.5)
	var offset := Vector3(0, 0.1, 0)

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(center - lateral * half_width + offset)
	immediate_mesh.surface_add_vertex(center + lateral * half_width + offset)
	immediate_mesh.surface_end()

func receive_laser(delta: float) -> void:
	if not _has_static_rats():
		return
	structure_integrity -= structure_decay_on_laser * delta
	if structure_integrity <= 0:
		recall_all_rats()
		structure_integrity = structure_max_integrity


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
		
	for rat in rats:
		rat.release_rat(true)
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

	# Respawn only at rat_spawn now.


func hard_recall_all_rats() -> void:
	# Release any grabbed object and its carrier rats first
	if grabbed_object != null:
		grabbed_object.set_meta("is_being_dragged", false)
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
		
	for rat in rats:
		if rat.has_method("hard_recall_to_player"):
			rat.hard_recall_to_player()

func soft_reset_all_rats() -> void:
	if grabbed_object != null:
		grabbed_object.set_meta("is_being_dragged", false)
		_release_object_carriers(grabbed_object)
		grabbed_object = null
		grabbed_object_last_pos = Vector3.ZERO
		_lmb_is_object_drag = false

	active_build_positions.clear()
	built_positions.clear()
	carrier_rats.clear()
	carrier_rat_offsets.clear()
	
	for child in unified_shape_combiner.get_children():
		child.queue_free()
		
	for rat in rats:
		if rat.has_method("soft_reset_state"):
			rat.soft_reset_state()
		else:
			rat.release_rat(true)
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


func _process_hover() -> void:

	var camera := get_viewport().get_camera_3d()
	if not camera: return
	
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 1000.0)
	query.collision_mask = 6 
	
	var hit := space_state.intersect_ray(query)
	var new_hover: Node3D = null
	
	if hit:
		var obj = hit.collider
		if obj.has_method("set_highlight") and not obj.is_in_group("player"):
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
		var base := Color(1, 0, 0) if invalid_surface else Color.WHITE
		line_material.albedo_color = _brush_color(base)
	
	var offset := Vector3(0, 0.1, 0)

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for pos in current_drawn_path:
		immediate_mesh.surface_add_vertex(pos + offset)
	immediate_mesh.surface_add_vertex(end_pos + offset)
	immediate_mesh.surface_end()

	if not use_wide_brush and current_attack_mode != AttackMode.PATH_DASH:
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
	if current_attack_mode == AttackMode.PATH_DASH:
		_draw_path_dash_brush_marker(end_pos, end_lateral)

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
		if is_instance_valid(rat) and rat.state == rat.State.FOLLOW and not rat.is_carrier:
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
	if combat_rmb_down and current_attack_mode == AttackMode.PATH_DASH:
		return

	# Use _mouse_to_world() for preview — it raycasts against ALL collision
	# layers and falls back to player-Y plane, so it never desyncs like
	# _get_mouse_ground_hit() (floor-only) + current_build_y did.
	var raw_pos: Vector3 = _mouse_to_world()
	if raw_pos == Vector3.ZERO:
		immediate_mesh.clear_surfaces()
		return

	if current_attack_mode == AttackMode.PATH_DASH:
		immediate_mesh.clear_surfaces()
		if line_material:
			line_material.albedo_color = _brush_color(Color.WHITE)
		_draw_path_dash_brush_marker(raw_pos, _get_path_dash_preview_lateral(raw_pos))
		return

	if build_draw_mode == DRAW_MODE_CIRCLE:
		current_circle_center = raw_pos
		var old_path = current_drawn_path.duplicate()
		current_drawn_path.clear()
		_update_circle_preview(false)
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
		if current_drawn_path.size() >= 2:
			var dir: Vector3 = current_drawn_path[-1] - current_drawn_path[-2]
			dir.y = 0.0
			if dir.length() > 0.001:
				lateral = dir.normalized().cross(Vector3.UP).normalized()
				
		immediate_mesh.clear_surfaces()
		if line_material:
			line_material.albedo_color = _brush_color(Color.WHITE)
		
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

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(max_buildable):
		var p := fill_positions[i] + offset
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
			
	var required_to_start: int = max(1, int(ceil(total_count / 2.0)))
	
	if arrived_count >= required_to_start:
		grabbed_object.set("is_surrounded", true)


func _process_object_drag(delta: float) -> void:
	if grabbed_object == null:
		return

	if not grabbed_object.get("is_surrounded"):
		return

	var current_pos: Vector3 = grabbed_object.global_position
	var target_pos: Vector3
	
	var hit := _get_mouse_ground_hit()
	if hit:
		target_pos = hit.position
		target_pos.y = current_pos.y
	else:
		var fallback := _get_mouse_pos_at_y(current_pos.y)
		if fallback == Vector3.ZERO:
			return
		target_pos = fallback

	var effective_radius: float = box_drag_max_radius
	var effective_speed: float = max(0.0, box_drag_speed)
	
	if grabbed_object.is_in_group("player"):
		effective_speed *= 2.5
		effective_radius *= 1.5

	var to_cursor := target_pos - current_pos
	if to_cursor.length() > effective_radius:
		target_pos = current_pos + to_cursor.normalized() * effective_radius

	var step: float = effective_speed * delta
	grabbed_object.global_position = current_pos.move_toward(target_pos, step)


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
