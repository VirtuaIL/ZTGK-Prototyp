extends Node3D
class_name WaveSpawner

## Samodzielny węzeł zarządzający falami wrogów.
## Działa niezależnie od MainSpawner — zastępuje wiele spawnerów jednym węzłem z listą fal.
## Następna fala rusza dopiero gdy wszyscy z poprzedniej zostaną wybici.

enum PositionMode {
	SELF_POSITION,       ## Pozycja tego węzła
	CHILD_POINTS,        ## Pozycje dzieci (Marker3D / Node3D)
	LEVEL_RAT_SPAWNS,    ## Markery rat_spawn z poziomu
	LEVEL_ENEMY_MARKERS, ## Markery spawn_markers z poziomu
}

# ── General ───────────────────────────────────────────────────────────────────
@export_group("General")
@export var enabled: bool = true
@export var label: String = ""
@export_range(0, 99, 1) var level_id: int = 1
## Opóźnienie przed pierwszą falą (sek.)
@export var start_delay: float = 5.0
@export var reset_on_level_enter: bool = true

# ── Waves ─────────────────────────────────────────────────────────────────────
@export_group("Waves")
## Lista fal wrogów — przetwarzane sekwencyjnie
@export var waves: Array[WaveDefinition] = []
## Czy po ostatniej fali zacząć od nowa
@export var loop_waves: bool = false
## Przerwa po wyczyszczeniu fali przed następną (sek.)
@export var delay_between_waves: float = 5.0

# ── Positions ─────────────────────────────────────────────────────────────────
@export_group("Positions")
@export var position_mode: PositionMode = PositionMode.SELF_POSITION
@export var choose_random_point: bool = true
@export var avoid_closest_to_player: bool = false
@export var spawn_radius: float = 1.5

# ── Wild Rat (gdy WaveGroup ma spawn_kind == WILD_RAT) ────────────────────────
@export_group("Wild Rat")
@export var wild_rat_prob_normal: float = 80.0
@export var wild_rat_prob_red: float = 10.0
@export var wild_rat_prob_green: float = 10.0

# ── Runtime ───────────────────────────────────────────────────────────────────
var _completed: bool = false
var _current_wave_index: int = 0
var _wave_timer: float = 0.0
var _wave_waiting_for_clear: bool = false
var _wave_alive_enemies: Array = []
var _was_active_last_frame: bool = false


func is_completed() -> bool:
	return _completed


func get_current_wave_index() -> int:
	return _current_wave_index


func get_total_wave_count() -> int:
	return waves.size()


func get_waves_remaining() -> int:
	if _completed:
		return 0
	return max(0, waves.size() - _current_wave_index)


func _ready() -> void:
	add_to_group("wave_spawners")
	reset_runtime()
	set_process(true)


func _process(delta: float) -> void:
	if not enabled:
		return

	var main := get_tree().current_scene
	if main == null:
		return

	var is_active := _is_active_for_main(main)
	if is_active and not _was_active_last_frame and reset_on_level_enter:
		reset_runtime()

	_was_active_last_frame = is_active
	if not is_active or _completed:
		return

	if waves.is_empty():
		_completed = true
		return

	if _current_wave_index >= waves.size():
		_completed = true
		return

	# ── Czekaj na wyczyszczenie bieżącej fali ──
	if _wave_waiting_for_clear:
		_cleanup_wave_enemies()
		if _wave_alive_enemies.is_empty():
			# Fala wyczyszczona — przejdź do następnej
			_wave_waiting_for_clear = false
			_current_wave_index += 1
			if _current_wave_index >= waves.size():
				if loop_waves:
					_current_wave_index = 0
				else:
					_completed = true
					return
			_wave_timer = 0.0
		return

	# ── Opóźnienie przed spawnem fali ──
	var required_delay: float
	if _current_wave_index == 0:
		required_delay = start_delay
	else:
		required_delay = delay_between_waves

	_wave_timer += delta
	if _wave_timer < required_delay:
		return

	# ── Spawn fali ──
	_spawn_current_wave(main)
	_wave_waiting_for_clear = true


func _spawn_current_wave(main: Node) -> void:
	if _current_wave_index >= waves.size():
		return
	var wave: WaveDefinition = waves[_current_wave_index]
	_wave_alive_enemies.clear()

	if not main.has_method("spawn_wave_group"):
		push_warning("WaveSpawner: main scene missing spawn_wave_group() method")
		return

	for group in wave.groups:
		var spawned: Array = main.call("spawn_wave_group", self, group)
		for node in spawned:
			if is_instance_valid(node):
				_wave_alive_enemies.append(node)


func _cleanup_wave_enemies() -> void:
	var alive: Array = []
	for enemy in _wave_alive_enemies:
		if _is_enemy_alive(enemy):
			alive.append(enemy)
	_wave_alive_enemies = alive


func _is_enemy_alive(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if not node.is_inside_tree():
		return false
	if node.has_method("is_dead") and node.is_dead():
		return false
	return true


func reset_runtime() -> void:
	_completed = false
	_current_wave_index = 0
	_wave_timer = 0.0
	_wave_waiting_for_clear = false
	_wave_alive_enemies.clear()


func get_target_level_id(main: Node) -> int:
	if level_id > 0:
		return level_id
	return int(main.get("current_level_id"))


func get_spawn_points(main: Node) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var resolved_level_id := get_target_level_id(main)

	match position_mode:
		PositionMode.SELF_POSITION:
			points.append(global_position)
		PositionMode.CHILD_POINTS:
			for child in get_children():
				var node3d := child as Node3D
				if node3d != null:
					points.append(node3d.global_position)
			if points.is_empty():
				points.append(global_position)
		PositionMode.LEVEL_RAT_SPAWNS:
			if main.has_method("get_level_rat_spawns"):
				var rat_markers: Array = main.call("get_level_rat_spawns", resolved_level_id)
				for marker in rat_markers:
					var node3d := marker as Node3D
					if node3d != null:
						points.append(node3d.global_position)
		PositionMode.LEVEL_ENEMY_MARKERS:
			if main.has_method("get_level_spawn_markers"):
				var enemy_markers: Array = main.call("get_level_spawn_markers", resolved_level_id)
				for marker in enemy_markers:
					var node3d := marker as Node3D
					if node3d != null:
						points.append(node3d.global_position)

	var player_node = main.get("player") as Node3D
	if avoid_closest_to_player and player_node != null and points.size() > 1:
		var closest_idx := 0
		var closest_dist := INF
		for i in range(points.size()):
			var point: Vector3 = points[i]
			var dist: float = player_node.global_position.distance_squared_to(point)
			if dist < closest_dist:
				closest_dist = dist
				closest_idx = i
		points.remove_at(closest_idx)

	return points


func _is_active_for_main(main: Node) -> bool:
	var active_level := int(main.get("current_level_id"))
	var target_level := get_target_level_id(main)
	return target_level <= 0 or target_level == active_level
