extends CharacterBody3D
class_name door

# The ID used by buttons to target this door
@export var doorId: int = 0

# How far (in local X units) the door slides when opened
@export var slide_distance: float = 3.0

# Duration of the slide animation in seconds
@export var slide_duration: float = 0.6

var _closed_position: Vector3
var _open_position: Vector3
var _is_open: bool = false


func _ready() -> void:
	add_to_group("doors")
	_closed_position = position
	_open_position = position + global_transform.basis.x * slide_distance


func open() -> void:
	if _is_open:
		return
	_is_open = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", _open_position, slide_duration)


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", _closed_position, slide_duration)
