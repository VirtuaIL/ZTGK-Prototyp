extends Area3D

@export var level_id: int = 0

var _is_active: bool = false

func _ready() -> void:
	# Podłącz się pod wbudowany sygnał, gdy jakieś ciało fizyczne wejdzie w obszar (Area).
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# Spradzamy czy weszliśmy już tu wcześniej
	if _is_active:
		return
		
	# Jeśli ciało, które nakłada się na obszar, ma grupę 'player' - to my.
	if body.is_in_group("player"):
		var current_scene := get_tree().current_scene
		if level_id > 0 and current_scene != null and current_scene.has_method("can_activate_level"):
			if not current_scene.can_activate_level(level_id):
				return

		_is_active = true
			
		# Ustawiamy punkt wskrzeszenia Gracza na naszą lokalizację. 
		if body.has_method("set_spawn_position"):
			body.set_spawn_position(global_position)

		if level_id > 0 and current_scene != null and current_scene.has_method("set_current_level"):
			current_scene.set_current_level(level_id)
			
		# Prosty sposób poinformowania gracza (opcjonalny tekst na wyjściu by zweryfikować że działa)
		print("Checkpoint reached at: ", global_position)
