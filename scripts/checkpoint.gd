extends Area3D

@export var level_id: int = 0

var _is_active: bool = false
var _pending_player: Node3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if _is_active:
		return
	if _pending_player == null or not is_instance_valid(_pending_player):
		_pending_player = null
		return
	_try_activate(_pending_player)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_pending_player = body
	_try_activate(body)


func _on_body_exited(body: Node3D) -> void:
	if body == _pending_player:
		_pending_player = null


func _try_activate(body: Node3D) -> void:
	if _is_active:
		return

	var current_scene := get_tree().current_scene
	if level_id > 0 and current_scene != null and current_scene.has_method("can_activate_level"):
		if not current_scene.can_activate_level(level_id):
			return

	_is_active = true
	_pending_player = null

	if body.has_method("set_spawn_position"):
		body.set_spawn_position(global_position)

	if level_id > 0 and current_scene != null and current_scene.has_method("set_current_level"):
		current_scene.set_current_level(level_id)

	print("Checkpoint reached at: ", global_position)
