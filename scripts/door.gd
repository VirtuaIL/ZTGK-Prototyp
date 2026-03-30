extends CharacterBody3D
class_name door

# The ID used by buttons to target this door
@export var doorId: int = 0

# How far (in local X units) the door slides when opened
@export var slide_distance: float = 9.0
@export var slide_axis: Vector3 = Vector3.RIGHT

# Duration of the slide animation in seconds
@export var slide_duration: float = 3.0

# If true, the door starts open and closes when triggered
@export var is_inverse: bool = false

var _closed_position: Vector3
var _open_position: Vector3
var _is_open: bool = false
var _current_tween: Tween


func _ready() -> void:
	add_to_group("doors")
	_closed_position = position
	var axis := slide_axis
	if axis.length() < 0.001:
		axis = Vector3.RIGHT
	var world_axis := global_transform.basis * axis.normalized()
	_open_position = position + world_axis * slide_distance
	
	if is_inverse:
		position = _open_position
		_is_open = true
	else:
		_is_open = false


func open() -> void:
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
