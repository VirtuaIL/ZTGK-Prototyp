extends Area3D

@export var require_empty: bool = true


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	for child in get_children():
		if child is CollisionShape3D:
			child.scale *= 0.5


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
		
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, body.global_position)
	query.collision_mask = 8 # Walls
	var hit = space_state.intersect_ray(query)
	if hit:
		return
		
	var rat_manager := get_tree().get_first_node_in_group("rat_manager")
	if rat_manager == null:
		return
	if rat_manager.has_method("restore_to_min"):
		rat_manager.restore_to_min(require_empty)
