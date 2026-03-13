extends Node
class_name button

# The ID of the door this button controls
@export var doorId: int = 0

# How far the button sinks when pressed (in local Y units)
@export var press_depth: float = 0.1

# Duration of the press animation
@export var press_duration: float = 0.1

# Track how many valid bodies are currently pressing the button.
# When it drops to 0 the door closes again.
var _bodies_on_button: int = 0
var _rest_y: float = 0.0
var _visual: button = null


func _ready() -> void:
	# Assume the script's parent is the visual/physics node to animate
	var p := self
	if p is button:
		_visual = p as button
		_rest_y = _visual.position.y
	
	# Set Area3D mask to detect Player (Layer 2) and Movable Objects (Layer 3)
	var area = get_node_or_null("Area3D")
	if area:
		area.collision_mask = 6 # 2 (Player) + 4 (Movable Objects)


func _find_target_door() -> door:
	for d in get_tree().get_nodes_in_group("doors"):
		if d is door and d.doorId == doorId:
			return d
	return null


func _set_pressed(pressed: bool) -> void:
	if _visual == null:
		return
	var target_y := _rest_y - press_depth if pressed else _rest_y
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_visual, "position:y", target_y, press_duration)


func _on_area_3d_body_entered(body: Node3D) -> void:
	# Activated by boxes, players, or turrets
	if not (body is box or body is player or body is turret or body is hitscan_turret):
		return
	_bodies_on_button += 1
	if _bodies_on_button == 1:
		_set_pressed(true)
		var target := _find_target_door()
		if target:
			target.open()


func _on_area_3d_body_exited(body: Node3D) -> void:
	if not (body is box or body is player or body is turret or body is hitscan_turret):
		return
	_bodies_on_button = max(0, _bodies_on_button - 1)
	if _bodies_on_button == 0:
		_set_pressed(false)
		var target := _find_target_door()
		if target:
			target.close()
