extends CharacterBody3D
class_name door

# The ID used by buttons to target this door
@export var doorId: int = 0

# How far (in local X units) the door slides when opened
@export var slide_distance: float = 9.0

# Duration of the slide animation in seconds
@export var slide_duration: float = 1.8

# If true, the door starts open and closes when triggered
@export var is_inverse: bool = false

var _closed_position: Vector3
var _open_position: Vector3
var _is_open: bool = false


func _ready() -> void:
	add_to_group("doors")
	_closed_position = position
	_open_position = position + global_transform.basis.x * slide_distance
	
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


## Called by Capstan every frame to smoothly position the door between
## closed (0.0) and open (1.0).  Bypasses the tween animation.
func set_open_progress(progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	if is_inverse:
		# inverse door: fully open at progress 0, closes as progress grows
		position = _open_position.lerp(_closed_position, progress)
	else:
		position = _closed_position.lerp(_open_position, progress)


func _animate_to(target_pos: Vector3) -> void:
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", target_pos, slide_duration)
