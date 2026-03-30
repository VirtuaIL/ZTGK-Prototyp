extends CharacterBody3D
class_name door

# The ID used by buttons to target this door
@export var doorId: int = 0

# How far (in local X units) the door slides when opened
@export var slide_distance: float = 9.0
@export var slide_axis: Vector3 = Vector3.RIGHT

# Duration of the slide animation in seconds
@export var slide_duration: float = 3.0

# How many buttons must be pressed at the same time to open
@export var required_press_count: int = 1

# If true, the door starts open and closes when triggered
@export var is_inverse: bool = false

@export_category("Vertical Grate Settings")
# Zaznacz, jeśli to krata pionowa ruszająca się w górę/w dół (ignoruje slide_axis)
@export var is_vertical_grate: bool = false
# True = jedzie w górę podczas kręcenia kołowrotkiem (np. postawiona w podłodze)
# False = jedzie w dół podczas kręcenia kołowrotkiem (np. postawiona w powietrzu)
@export var moves_up: bool = true

var _closed_position: Vector3
var _open_position: Vector3
var _is_open: bool = false
var _current_tween: Tween
var _press_count: int = 0
var _press_sources: Dictionary = {}


func _ready() -> void:
	add_to_group("doors")
	_closed_position = position
	var axis := slide_axis
	
	if is_vertical_grate:
		axis = Vector3.UP if moves_up else Vector3.DOWN
	elif axis.length() < 0.001:
		axis = Vector3.RIGHT
		
	var world_axis := global_transform.basis * axis.normalized()
	_open_position = position + world_axis * slide_distance
	
	if is_inverse:
		position = _open_position
		_is_open = true
	else:
		_is_open = false


func press(source: Object = null) -> void:
	if source != null:
		_press_sources[source] = true
	else:
		_press_count += 1
	_update_press_state()


func release(source: Object = null) -> void:
	if source != null:
		_press_sources.erase(source)
	else:
		_press_count = maxi(0, _press_count - 1)
	_update_press_state()


func _update_press_state() -> void:
	var required: int = maxi(1, required_press_count)
	var count := _press_sources.size() if _press_sources.size() > 0 else _press_count
	if count >= required:
		open()
	else:
		close()

func reset_presses() -> void:
	_press_sources.clear()
	_press_count = 0
	_is_open = false
	_animate_to(_closed_position)


func open() -> void:
	var required: int = maxi(1, required_press_count)
	var count := _press_sources.size() if _press_sources.size() > 0 else _press_count
	if count < required:
		return
	if is_inverse:
		if not _is_open: return
		_is_open = false
		_animate_to(_closed_position)
	else:
		if _is_open: return
		_is_open = true
		_animate_to(_open_position)


func close() -> void:
	if is_inverse:
		if _is_open: return
		_is_open = true
		_animate_to(_open_position)
	else:
		if not _is_open: return
		_is_open = false
		_animate_to(_closed_position)


func _animate_to(target_pos: Vector3) -> void:
	if _current_tween:
		_current_tween.kill()
	var tween := create_tween()
	_current_tween = tween
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", target_pos, slide_duration)


func set_progress(weight: float) -> void:
	if _current_tween:
		_current_tween.kill()
		_current_tween = null
	var target = _closed_position.lerp(_open_position, clamp(weight, 0.0, 1.0))
	if is_inverse:
		target = _open_position.lerp(_closed_position, clamp(weight, 0.0, 1.0))
	position = target
