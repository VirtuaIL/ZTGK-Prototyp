extends Area3D

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
		_is_active = true
		
		# Ustawiamy punkt wskrzeszenia Gracza na naszą lokalizację. 
		if body.has_method("set_spawn_position"):
			body.set_spawn_position(global_position)
		
		# Prosty sposób poinformowania gracza (opcjonalny tekst na wyjściu by zweryfikować że działa)
		print("Checkpoint reached at: ", global_position)
