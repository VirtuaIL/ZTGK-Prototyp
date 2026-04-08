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
	if main == null or not main.has_method("trigger_spawner"):
		return

	var is_active := _is_active_for_main(main)
	if is_active and not _was_active_last_frame and reset_on_level_enter:
		reset_runtime()

	_was_active_last_frame = is_active
	if not is_active or _completed:
		return

	_elapsed += delta
	while _elapsed >= _next_trigger_at and not _completed:
		var did_spawn := bool(main.call("trigger_spawner", self))
		if not did_spawn:
			_completed = true
			break

		_trigger_count += 1
		if repeat and (max_triggers <= 0 or _trigger_count < max_triggers):
			_next_trigger_at += maxf(0.01, repeat_interval)
		else:
			_completed = true


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
