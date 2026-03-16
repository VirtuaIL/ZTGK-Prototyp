extends Area3D

@export var add_amount: int = 5
@export var auto_restore: bool = true
@export var one_shot: bool = true

var _used: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _used and one_shot:
		return
	if not body.is_in_group("player"):
		return
	var rat_manager := get_tree().get_first_node_in_group("rat_manager")
	if rat_manager == null:
		return
	if rat_manager.has_method("increase_min_cap"):
		rat_manager.increase_min_cap(add_amount)
		if auto_restore and rat_manager.has_method("restore_to_min"):
			rat_manager.restore_to_min(false)
	if one_shot:
		_used = true
		queue_free()
