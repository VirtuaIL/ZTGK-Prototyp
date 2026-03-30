extends Node
class_name button

# The ID of the door this button controls
@export var doorId: int = 0

# How far the button sinks when pressed (in local Y units)
@export var press_depth: float = 0.1

# Duration of the press animation
@export var press_duration: float = 0.1
@export var latch_open: bool = true

# Track how many valid bodies are currently pressing the button.
# When it drops to 0 the door closes again.
var _bodies_on_button: int = 0
var _rest_y: float = 0.0
var _visual: button = null
var _latched: bool = false
var _ready_for_input: bool = false


func _ready() -> void:
	add_to_group("buttons")
	# Assume the script's parent is the visual/physics node to animate
	var p := self
	if p is button:
		_visual = p as button
		_rest_y = _visual.position.y
	
	# Set Area3D mask to detect Player (Layer 2) and Movable Objects (Layer 3)
	var area = get_node_or_null("Area3D")
	if area:
		area.collision_mask = 6 # 2 (Player) + 4 (Movable Objects)
	_ready_for_input = false
	call_deferred("_enable_button_input")

func _enable_button_input() -> void:
	_ready_for_input = true

#changed from Array[Door] to array[Node] to accomodate different entity types being triggered
func _get_target_doors() -> Array[Node]:
	var result: Array[Node] = []
	var level_root := _get_level_root()
	var objects := get_tree().get_nodes_in_group("doors") + get_tree().get_nodes_in_group("bosses")
	print(objects)
	for d in (objects):
		if level_root and not level_root.is_ancestor_of(d):
			continue
		if ((d is Node) || (d is bossTurret)) and d.doorId == doorId:
			result.append(d)
	print(result)
	return result

func _get_level_root() -> Node:
	var n: Node = self
	while n and n.get_parent():
		var p := n.get_parent()
		if p and p.name == "levels":
			return n
		n = p
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
	if not _ready_for_input:
		return
	# Activated by boxes, players, or turrets
	if not (body is box or body is player or body is turret or body is hitscan_turret):
		return
	_bodies_on_button += 1
	if _bodies_on_button == 1:
		_set_pressed(true)
		for target in _get_target_doors():
			if target.has_method("press"):
				target.press(self)
			else:
				target.open()
		if latch_open:
			_latched = true


func _on_area_3d_body_exited(body: Node3D) -> void:
	if not _ready_for_input:
		return
	if not (body is box or body is player or body is turret or body is hitscan_turret):
		return
	_bodies_on_button = max(0, _bodies_on_button - 1)
	if _bodies_on_button == 0:
		if _latched:
			return
		_set_pressed(false)
		for target in _get_target_doors():
			if target.has_method("release"):
				target.release(self)
			else:
				target.close()

func reset_button_state() -> void:
	_bodies_on_button = 0
	_latched = false
	_set_pressed(false)
