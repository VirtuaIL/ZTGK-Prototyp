extends Node
class_name button

# The ID of the door this button controls
@export var doorId: int = 0

# Track how many valid bodies are currently pressing the button.
# When it drops to 0 the door closes again.
var _bodies_on_button: int = 0


func _find_target_door() -> door:
	for d in get_tree().get_nodes_in_group("doors"):
		if d is door and d.doorId == doorId:
			return d
	return null


func _on_area_3d_body_entered(body: Node3D) -> void:
	# Only a box activates the button
	if not (body is box):
		return
	_bodies_on_button += 1
	if _bodies_on_button == 1:
		var target := _find_target_door()
		if target:
			target.open()


func _on_area_3d_body_exited(body: Node3D) -> void:
	if not (body is box):
		return
	_bodies_on_button = max(0, _bodies_on_button - 1)
	if _bodies_on_button == 0:
		var target := _find_target_door()
		if target:
			target.close()
