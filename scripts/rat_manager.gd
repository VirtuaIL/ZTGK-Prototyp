extends Node3D

signal rat_count_changed(active: int, total: int)

# ── Tuning ────────────────────────────────────────────────────────────────────
const BLOB_RADIUS_BASE: float = 1.8 # radius of innermost ring
const BLOB_SPREAD: float = 0.22 # how much radius grows per rat index
const STREAM_SPACING: float = 0.42 # distance between rats along drawn path
const DRAW_SAMPLE_DIST: float = 0.2 # min mouse travel before new path sample
const NEIGHBOR_RADIUS: float = 1.1 # radius for separation lookup
const NEIGHBOR_TICK: int = 3 # recompute neighbors every N frames

# ── State ─────────────────────────────────────────────────────────────────────
enum Mode {BLOB, DRAW}
var current_mode: Mode = Mode.BLOB

var rats: Array[CharacterBody3D] = []
var dead_rats: Array[CharacterBody3D] = []
var player_ref: CharacterBody3D

# Blob
var _blob_offsets: Array[Vector3] = [] # pre-baked offsets relative to player

# Draw
var _lmb_held: bool = false
var _drawn_path: Array[Vector3] = []
var _last_sample: Vector3 = Vector3.ZERO

# Neighbor throttle
var _neighbor_tick: int = 0


func _ready() -> void:
	# Player might not exist yet — defer one frame
	call_deferred("_find_player")


func _find_player() -> void:
	player_ref = get_tree().get_first_node_in_group("player")


func register_rat(rat: CharacterBody3D) -> void:
	if rats.has(rat):
		return
	rats.append(rat)
	rat.add_to_group("rats")
	if not rat.fallen_into_abyss.is_connected(_on_rat_fallen):
		rat.fallen_into_abyss.connect(_on_rat_fallen)
	rat_count_changed.emit(rats.size() - dead_rats.size(), rats.size())


# Called once by main.gd after all rats are spawned
func build_blob_offsets() -> void:
	_blob_offsets.clear()
	var count := rats.size()
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for i in range(count):
		var r := BLOB_RADIUS_BASE * sqrt(float(i + 1) / float(count)) + BLOB_SPREAD * float(i) * 0.04
		var a := golden_angle * float(i)
		_blob_offsets.append(Vector3(cos(a) * r, 0.0, sin(a) * r))


# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if player_ref == null:
		player_ref = get_tree().get_first_node_in_group("player")
		return

	_handle_draw_input()

	if current_mode == Mode.DRAW and _drawn_path.size() >= 2:
		_update_draw()
	else:
		_update_blob()

	# Throttle neighbor computation — every NEIGHBOR_TICK frames
	_neighbor_tick += 1
	if _neighbor_tick >= NEIGHBOR_TICK:
		_neighbor_tick = 0
		_assign_neighbors()


func _handle_draw_input() -> void:
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if lmb and not _lmb_held:
		_lmb_held = true
		_drawn_path.clear()
		_last_sample = player_ref.global_position
		_drawn_path.append(_last_sample)
		current_mode = Mode.DRAW

	elif not lmb and _lmb_held:
		_lmb_held = false
		current_mode = Mode.BLOB
		_drawn_path.clear()

	if _lmb_held:
		var wp := _mouse_to_world()
		if wp != Vector3.ZERO and wp.distance_to(_last_sample) >= DRAW_SAMPLE_DIST:
			_drawn_path.append(wp)
			_last_sample = wp
			if _drawn_path.size() > 500:
				_drawn_path.pop_front()


# ── BLOB ──────────────────────────────────────────────────────────────────────

func _update_blob() -> void:
	if _blob_offsets.size() != rats.size():
		build_blob_offsets()

	var base := player_ref.global_position
	for i in range(rats.size()):
		var rat := rats[i]
		if dead_rats.has(rat):
			continue
		var t := base + _blob_offsets[i]
		t.y = base.y
		rat.set_target(t)


# ── DRAW / STREAM ─────────────────────────────────────────────────────────────

func _update_draw() -> void:
	# Arc-length parameterization
	var arc: Array[float] = [0.0]
	for i in range(1, _drawn_path.size()):
		arc.append(arc[i - 1] + _drawn_path[i].distance_to(_drawn_path[i - 1]))
	var total: float = arc[-1]

	var active: Array[CharacterBody3D] = []
	for rat in rats:
		if not dead_rats.has(rat):
			active.append(rat)

	var count := active.size()
	for i in range(count):
		var dist_back := float(i) * STREAM_SPACING
		var arc_pos := total - dist_back

		var target: Vector3
		if arc_pos <= 0.0:
			# Beyond start of path — use blob offset
			if i < _blob_offsets.size():
				target = player_ref.global_position + _blob_offsets[i]
			else:
				target = player_ref.global_position
		else:
			target = _arc_sample(_drawn_path, arc, arc_pos)

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


# ── Neighbors ────────────────────────────────────────────────────────────────

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


# ── Death / Respawn ───────────────────────────────────────────────────────────

func _on_rat_fallen(rat: CharacterBody3D) -> void:
	if dead_rats.has(rat):
		return
	dead_rats.append(rat)
	rat.visible = false
	rat.set_physics_process(false)
	rat.process_mode = Node.PROCESS_MODE_DISABLED
	rat_count_changed.emit(rats.size() - dead_rats.size(), rats.size())
	get_tree().create_timer(5.0).timeout.connect(_respawn_rat.bind(rat))


func _respawn_rat(rat: CharacterBody3D) -> void:
	dead_rats.erase(rat)
	rat.visible = true
	rat.set_physics_process(true)
	rat.process_mode = Node.PROCESS_MODE_INHERIT
	var a := randf() * TAU
	rat.respawn_at(player_ref.global_position + Vector3(cos(a) * 2.0, 1.5, sin(a) * 2.0))
	rat_count_changed.emit(rats.size() - dead_rats.size(), rats.size())


# ── Raycast mouse → world ─────────────────────────────────────────────────────

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
	var py := player_ref.global_position.y
	var denom := Vector3.UP.dot(rd)
	if abs(denom) > 0.0001:
		var tt := (py - Vector3.UP.dot(ro)) / denom
		if tt > 0.0:
			return ro + rd * tt

	return Vector3.ZERO
