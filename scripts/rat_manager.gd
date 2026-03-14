# rat_manager.gd — rozszerzony o nowe moce i combos
extends Node3D

signal orbit_started()
signal orbit_ended()
signal wave_started()
signal wave_ended()
signal direct_started()
signal circle_started()

var rats: Array[CharacterBody3D] = []

# Orbit (krąg)
var orbit_active: bool = false
var orbit_duration: float = 10.0
var orbit_timer: float = 0.0

# Wave (fala)
var wave_active: bool = false
var wave_duration: float = 1.0
var wave_timer: float = 0.0
# var wave_pending: bool = false   # czeka na klik z kierunkiem

# Direct (bezpośredni atak) — czeka na klik z punktem
# var direct_pending: bool = false

# Combo stany
var fast_wave_active: bool = false
var moving_circle_active: bool = false

# Drawing (rysowanie szczurami) — tylko tryb puzzle
var built_positions: Dictionary = {}
var _draw_mouse_down: bool = false
var last_draw_pos: Vector3 = Vector3(-1000, -1000, -1000)
var is_drawing_line: bool = false
var current_build_y: float = -1000.0

func _ready() -> void:
	add_to_group("rat_manager")

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

	if _draw_mouse_down:
		_process_build_drag()

func _unhandled_input(_event: InputEvent) -> void:
	pass 

func register_rat(rat: CharacterBody3D) -> void:
	rats.append(rat)

# ═══════════════════════════════════════════════
#  MOCE
# ═══════════════════════════════════════════════

func on_ability_activated(ability_id: String, mouse_pos: Vector2) -> void:
	match ability_id:
		"wave":
			_fire_wave_at_mouse(mouse_pos)
		"direct":
			_fire_direct_at_mouse(mouse_pos)
		"circle":
			_start_circle()

func on_combo_activated(combo_id: String, mouse_pos: Vector2) -> void:
	match combo_id:
		"fast_wave":
			_fire_wave_at_mouse(mouse_pos, 2.0)
		"moving_circle":
			activate_orbit()
			# opcjonalnie: przesuń krąg w kierunku myszy
		"charging_circle":
			_start_circle()
			_fire_direct_at_mouse(mouse_pos)

# ─── Fala [LL] ───────────────────────────────
func _start_wave() -> void:
	if orbit_active:
		deactivate_orbit()
	# wave_pending = true   # czeka na klik kierunku

func _fire_wave_at_mouse(screen_pos: Vector2, speed_mult: float = 1.0) -> void:
	wave_active = true
	wave_timer = wave_duration

	var player_node: Node3D = rats[0].player
	var player_pos: Vector3 = player_node.global_position
	var forward := _screen_to_ground_dir(screen_pos, player_pos)

	var count := rats.size()
	for i in range(count):
		var spread: float = deg_to_rad(remap(i, 0, count, -30.0, 30.0))
		var dir: Vector3 = forward.rotated(Vector3.UP, spread)
		var delay: float = randf_range(0.0, 0.15)
		rats[i].set_wave(dir, delay, speed_mult)
	wave_started.emit()

# ─── Direct [PP] ─────────────────────────────
func _start_direct() -> void:
	if orbit_active:
		deactivate_orbit()
	# direct_pending = true   # czeka na klik punktu docelowego

func _fire_direct_at_mouse(screen_pos: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var target_pos := ray_origin
	if abs(ray_dir.y) > 0.001:
		var t: float = -ray_origin.y / ray_dir.y
		target_pos = ray_origin + ray_dir * t

	var count := rats.size()
	for i in range(count):
		var delay: float = i * 0.12   # jeden po drugim
		rats[i].set_direct_attack(target_pos, delay)
	direct_started.emit()

# ─── Krąg [LP] ───────────────────────────────
func _start_circle() -> void:
	if orbit_active:
		deactivate_orbit()
		return
	activate_orbit()

func activate_orbit() -> void:
	orbit_active = true
	orbit_timer = orbit_duration
	var count := rats.size()
	var radius: float = maxf(1.5, count * 0.3)
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

# ─── Combo: Szybka Fala [LL + PP] ────────────
func _start_fast_wave() -> void:
	# wave_pending = true
	fast_wave_active = true

func _fire_fast_wave_at_mouse(screen_pos: Vector2) -> void:
	fast_wave_active = false
	_fire_wave_at_mouse(screen_pos, 2.0)   # 2x szybkość

# ─── Combo: Ruchomy Krąg [LL + LP] ───────────
func _start_moving_circle() -> void:
	activate_orbit()
	moving_circle_active = true
	# wave_pending = true   # poczekaj na kierunek ruchu

# (ruch kręgu można obsłużyć osobno w rat.gd przez nowy stan)

# ─── Combo: ??? [PP + LP] ────────────────────
func _start_unknown_combo() -> void:
	# TODO: do zaprojektowania
	pass

# ═══════════════════════════════════════════════
#  RYSOWANIE (tylko tryb puzzle)
# ═══════════════════════════════════════════════

func set_draw_mouse_down(pressed: bool) -> void:
	_draw_mouse_down = pressed
	if not pressed:
		current_build_y = -1000.0
		is_drawing_line = false

func recall_all_rats() -> void:
	built_positions.clear()
	for rat in rats:
		rat.release_rat()
	_draw_mouse_down = false
	is_drawing_line = false
	current_build_y = -1000.0

func _get_build_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir    := camera.project_ray_normal(mouse_pos)

	# Najpierw spróbuj raycast na istniejącą geometrię
	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * 1000.0
	)
	query.collision_mask = 0xFFFFFFFF   # wszystkie warstwy
	var hit := space_state.intersect_ray(query)
	if hit:
		return hit.position + hit.normal * 0.05

	# Fallback — rzut na płaszczyznę Y=current_build_y lub Y=0
	var plane_y := current_build_y if current_build_y > -500.0 else 0.0
	if abs(ray_dir.y) > 0.001:
		var t: float = (plane_y - ray_origin.y) / ray_dir.y
		if t > 0.0:
			return ray_origin + ray_dir * t

	return Vector3.ZERO

func _process_build_drag() -> void:
	var build_pos := _get_build_position()
	if build_pos == Vector3.ZERO:
		return

	if current_build_y <= -500.0:
		current_build_y = build_pos.y

	if is_drawing_line:
		var dist := last_draw_pos.distance_to(build_pos)
		var steps := maxi(1, ceili(dist / 0.5))   # co 0.5 jednostki jeden szczur
		for i in range(1, steps + 1):
			var inter_pos := last_draw_pos.lerp(build_pos, float(i) / steps)
			_try_build_at(inter_pos)
	else:
		is_drawing_line = true
		_try_build_at(build_pos)

	last_draw_pos = build_pos

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

# ═══════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════

func _screen_to_ground_dir(screen_pos: Vector2, origin: Vector3) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var forward := Vector3(0, 0, 1)
	if abs(ray_dir.y) > 0.001:
		var t: float = -ray_origin.y / ray_dir.y
		var ground_hit := ray_origin + ray_dir * t
		forward = (ground_hit - origin)
		forward.y = 0.0
	if forward.length() < 0.1:
		forward = Vector3(0, 0, 1)
	return forward.normalized()
