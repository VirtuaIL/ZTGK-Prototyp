extends Node3D
class_name MainSpawner

enum SpawnKind {
	WILD_RAT,
	BASIC_ENEMY,
	FLAMETHROWER_ENEMY,
	BOMBER_ENEMY,
	SNIPER_ENEMY,
	MORTAR_ENEMY,
	CUSTOM_SCENE,
	RANDOM_MIX,
}

enum PositionMode {
	SELF_POSITION,
	CHILD_POINTS,
	LEVEL_RAT_SPAWNS,
	LEVEL_ENEMY_MARKERS,
}

@export_group("General")
@export var enabled: bool = true
@export var label: String = ""
@export_range(0, 99, 1) var level_id: int = 1
@export var start_delay: float = 5.0
@export var repeat: bool = false
@export var repeat_interval: float = 15.0
@export var max_triggers: int = 1
@export var reset_on_level_enter: bool = true

@export_group("Spawn")
@export var spawn_kind: SpawnKind = SpawnKind.WILD_RAT
@export var count_min: int = 1
@export var count_max: int = 3
@export var spawn_radius: float = 1.5

@export_group("Positions")
@export var position_mode: PositionMode = PositionMode.SELF_POSITION
@export var choose_random_point: bool = true
@export var avoid_closest_to_player: bool = false

@export_group("Wild Rat")
@export var wild_rat_prob_normal: float = 80.0
@export var wild_rat_prob_red: float = 10.0
@export var wild_rat_prob_green: float = 10.0

@export_group("Custom Scene")
@export var custom_scene: PackedScene

var _elapsed: float = 0.0
var _next_trigger_at: float = 0.0
var _trigger_count: int = 0
var _completed: bool = false
var _was_active_last_frame: bool = false


func _ready() -> void:
	add_to_group("main_spawners")
	reset_runtime()
	set_process(true)


func _process(delta: float) -> void:
	if not enabled:
		return

	var main := get_tree().current_scene
	if main == null or not main.is_node_ready():
		return

	var is_active := _is_active_for_main(main)
	if is_active and not _was_active_last_frame and reset_on_level_enter:
		reset_runtime()

	_was_active_last_frame = is_active
	if not is_active or _completed:
		return

	_elapsed += delta
	while _elapsed >= _next_trigger_at and not _completed:
		var _did_spawn := _spawn(main)
		# Consume the trigger even if it couldn't spawn anything (e.g. invalid setup or temporary shortage)
		_trigger_count += 1
		if repeat and (max_triggers <= 0 or _trigger_count < max_triggers):
			_next_trigger_at += maxf(0.01, repeat_interval)
		else:
			_completed = true


var _wave_enemy_scene: PackedScene = preload("res://scenes/enemies/enemy.tscn")
var _wave_flamethrower_scene: PackedScene = preload("res://scenes/enemies/flamethrower_enemy.tscn")
var _wave_bomber_scene: PackedScene = preload("res://scenes/enemies/bomber_enemy.tscn")
var _wave_mortar_scene: PackedScene = preload("res://scenes/enemies/mortar_enemy.tscn")
var _wave_sniper_scene: PackedScene = preload("res://scenes/enemies/sniper_enemy.tscn")

func _spawn(main: Node) -> bool:
	match spawn_kind:
		SpawnKind.WILD_RAT:
			return _spawn_wild_rats(main)
		_:
			return _spawn_scene(main)

func _spawn_wild_rats(main: Node) -> bool:
	var rat_manager = main.get("rat_manager")
	if rat_manager == null or rat_manager.rat_scene == null:
		return false

	var points := get_spawn_points(main)
	if points.is_empty():
		return false

	var count := randi_range(min(count_min, count_max), max(count_min, count_max))
	if count <= 0:
		return false

	var player = main.get("player")
	var target_level = get_target_level_id(main)

	for i in range(count):
		var rat = rat_manager.rat_scene.instantiate()
		if rat == null:
			continue
		var spawn_pos := _pick_spawner_point(points, choose_random_point, i) + _random_spawn_offset(spawn_radius, 0.2)
		rat.player = player
		if rat.has_method("set_rat_type"):
			rat.set_rat_type(_roll_wild_rat_type(
				wild_rat_prob_normal,
				wild_rat_prob_red,
				wild_rat_prob_green
			))
		rat_manager.add_child(rat)
		_assign_level_tag(rat, target_level)
		rat.global_position = spawn_pos
		if rat.has_method("set_wild"):
			rat.set_wild(true)
	return true


func _spawn_scene(main: Node) -> bool:
	var points := get_spawn_points(main)
	if points.is_empty():
		return false

	var count := randi_range(min(count_min, count_max), max(count_min, count_max))
	if count <= 0:
		return false

	var target_level = get_target_level_id(main)

	for i in range(count):
		var scene: PackedScene = null
		if spawn_kind == SpawnKind.RANDOM_MIX:
			var r := randf()
			if r <= 0.15 and _wave_sniper_scene:
				scene = _wave_sniper_scene
			elif r <= 0.30 and _wave_bomber_scene:
				scene = _wave_bomber_scene
			elif r <= 0.55 and _wave_flamethrower_scene:
				scene = _wave_flamethrower_scene
			elif r <= 0.65 and _wave_mortar_scene:
				scene = _wave_mortar_scene
			else:
				scene = _wave_enemy_scene
		else:
			scene = _get_scene_for_spawner_kind(spawn_kind, custom_scene)
			
		if scene == null:
			continue
			
		var node := scene.instantiate()
		if node == null:
			continue
		main.add_child(node)
		if node is Node3D:
			var node3d := node as Node3D
			node3d.global_position = _pick_spawner_point(points, choose_random_point, i) + _random_spawn_offset(spawn_radius, 0.0)
			_assign_level_tag(node3d, target_level)
			
		# Automatically attach death signal if main.gd still manages scripted enemy tracking (it can just queue free and check level completion there)
		if node.has_signal("enemy_died"):
			if main.has_method("_on_scripted_enemy_died"):
				node.enemy_died.connect(Callable(main, "_on_scripted_enemy_died").bind(node), CONNECT_ONE_SHOT)
	return true


func _get_scene_for_spawner_kind(spawn_kind_id: int, custom: PackedScene) -> PackedScene:
	match spawn_kind_id:
		SpawnKind.BASIC_ENEMY:
			return _wave_enemy_scene
		SpawnKind.FLAMETHROWER_ENEMY:
			return _wave_flamethrower_scene
		SpawnKind.BOMBER_ENEMY:
			return _wave_bomber_scene
		SpawnKind.SNIPER_ENEMY:
			return _wave_sniper_scene
		SpawnKind.MORTAR_ENEMY:
			return _wave_mortar_scene
		SpawnKind.CUSTOM_SCENE:
			return custom
		_:
			return null


func _pick_spawner_point(points: Array[Vector3], choose_random: bool, index: int) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if choose_random:
		return points[randi() % points.size()]
	return points[index % points.size()]


func _random_spawn_offset(radius: float, y_offset: float) -> Vector3:
	var angle := randf() * TAU
	var dist := randf_range(0.0, maxf(0.0, radius))
	return Vector3(cos(angle) * dist, y_offset, sin(angle) * dist)


func _roll_wild_rat_type(prob_normal: float, prob_red: float, prob_green: float) -> int:
	var total_prob := maxf(0.0, prob_normal) + maxf(0.0, prob_red) + maxf(0.0, prob_green)
	if total_prob <= 0.0:
		return 0
	var roll := randf_range(0.0, total_prob)
	if roll < prob_red:
		return 1
	if roll < prob_red + prob_green:
		return 2
	return 0


func _assign_level_tag(node: Node, level_id: int) -> void:
	if node == null or level_id <= 0:
		return
	node.set_meta("level_id", level_id)


func reset_runtime() -> void:
	_elapsed = 0.0
	_next_trigger_at = maxf(0.0, start_delay)
	_trigger_count = 0
	_completed = false


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
