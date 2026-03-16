extends Area3D

@export var require_empty: bool = true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	var rat_manager := get_tree().get_first_node_in_group("rat_manager")
	if rat_manager == null:
		return
	if rat_manager.has_method("restore_to_min"):
		rat_manager.restore_to_min(require_empty)
