@tool
extends Node3D
class_name HeatGrateController

enum ControlMode { TIMER, PROGRESS }
enum PatternMode { STRING, INDICES }

@export_category("Behavior Settings")
@export var mode: ControlMode = ControlMode.TIMER
@export var step_time: float = 1.0
@export var trapId: int = -1
@export var pattern_mode: PatternMode = PatternMode.STRING
@export var patterns: Array[String] = []
@export var patterns_indices: Array[PackedInt32Array] = []
@export var paint_enabled: bool = false
@export var paint_pattern_index: int = 0

@export_category("Grid Generation")
@export var grate_scene: PackedScene
@export var grid_columns: int = 5
@export var grid_rows: int = 5
@export var grid_spacing: Vector2 = Vector2(2.2, 2.2)

@export var generate_grid: bool = false:
	set(val):
		if val and Engine.is_editor_hint():
			_generate_grid()

var grates: Array[HeatGrate] = []

var _timer: float = 0.0
var _current_pattern_index: int = 0
var _is_ready: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	add_to_group("progress_targets")
	
	for child in get_children():
		if child is HeatGrate:
			grates.append(child)
			
	_is_ready = true
	if _get_pattern_count() > 0:
		_apply_pattern(_current_pattern_index)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if mode == ControlMode.TIMER:
		if _get_pattern_count() <= 1:
			return
		_timer += delta
		if _timer >= step_time:
			_timer -= step_time
			_current_pattern_index = (_current_pattern_index + 1) % _get_pattern_count()
			_apply_pattern(_current_pattern_index)

func set_progress(weight: float) -> void:
	if Engine.is_editor_hint() or not _is_ready:
		return
	if mode != ControlMode.PROGRESS or _get_pattern_count() == 0:
		return
		
	var idx = clampi(int(weight * _get_pattern_count()), 0, _get_pattern_count() - 1)
	
	if idx != _current_pattern_index:
		_current_pattern_index = idx
		_apply_pattern(idx)

func _apply_pattern(idx: int) -> void:
	if idx < 0 or idx >= _get_pattern_count():
		return
	if pattern_mode == PatternMode.INDICES:
		var target_grates := grates
		if Engine.is_editor_hint():
			target_grates = get_grates_editor()
		for g in target_grates:
			if g:
				g.is_active = false
		if idx >= patterns_indices.size():
			return
		var list := patterns_indices[idx]
		for i in list:
			if i >= 0 and i < target_grates.size():
				var grate := target_grates[i]
				if grate:
					grate.is_active = true
	else:
		if idx >= patterns.size():
			return
		var p = patterns[idx]
		for g in grates:
			if g != null:
				g.is_active = false
		for i in range(min(p.length(), grates.size())):
			var grate = grates[i]
			if grate != null:
				grate.is_active = (p[i] == "1")

func _get_pattern_count() -> int:
	return patterns_indices.size() if pattern_mode == PatternMode.INDICES else patterns.size()

func _generate_grid() -> void:
	if grate_scene == null:
		push_warning("Wybierz scenę kratki (grate_scene) aby wygenerować grid!")
		return
		
	var existing = []
	for child in get_children():
		if child is HeatGrate:
			existing.append(child)
			
	for child in existing:
		remove_child(child)
		child.queue_free()

	for r in range(grid_rows):
		for c in range(grid_columns):
			var grate = grate_scene.instantiate() as HeatGrate
			add_child(grate)
			
			var offset_x = (c - (grid_columns - 1) * 0.5) * grid_spacing.x
			var offset_z = (r - (grid_rows - 1) * 0.5) * grid_spacing.y
			grate.position = Vector3(offset_x, 0, offset_z)
			
			if get_tree() and get_tree().edited_scene_root:
				grate.owner = get_tree().edited_scene_root

	print("HeatGrateController: Wygenerowano grid ", grid_columns, "x", grid_rows)

func get_grates_editor() -> Array[HeatGrate]:
	var list: Array[HeatGrate] = []
	for child in get_children():
		if child is HeatGrate:
			list.append(child)
	return list

func is_index_active(pattern_idx: int, grate_idx: int) -> bool:
	if pattern_idx < 0 or pattern_idx >= patterns_indices.size():
		return false
	for i in patterns_indices[pattern_idx]:
		if i == grate_idx:
			return true
	return false

func set_pattern_index_active(pattern_idx: int, grate_idx: int, active: bool) -> void:
	if pattern_idx < 0:
		return
	while patterns_indices.size() <= pattern_idx:
		patterns_indices.append(PackedInt32Array())
	var arr := patterns_indices[pattern_idx]
	var exists := false
	for i in arr:
		if i == grate_idx:
			exists = true
			break
	var new_arr := PackedInt32Array()
	for i in arr:
		if i != grate_idx:
			new_arr.append(i)
	if active and not exists:
		new_arr.append(grate_idx)
	patterns_indices[pattern_idx] = new_arr
	
	if pattern_mode == PatternMode.INDICES:
		_apply_pattern(pattern_idx)
