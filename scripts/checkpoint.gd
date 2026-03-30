extends Area3D

var _is_active: bool = false
@export var target_level_path: NodePath

func _ready() -> void:
	# Podłącz się pod wbudowany sygnał, gdy jakieś ciało fizyczne wejdzie w obszar (Area).
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# Jeśli ciało, które nakłada się na obszar, ma grupę 'player' - to my.
	if body.is_in_group("player"):
		# Ustaw checkpoint tylko raz
		if not _is_active:
			_is_active = true
			# Ustawiamy punkt wskrzeszenia Gracza na naszą lokalizację. 
			if body.has_method("set_spawn_position"):
				body.set_spawn_position(global_position)
			# Prosty sposób poinformowania gracza (opcjonalny tekst na wyjściu by zweryfikować że działa)
			print("Checkpoint reached at: ", global_position)
		
		# Opcjonalnie: wymuś level dla kamery/occlusion
		if target_level_path != NodePath():
			var main := get_tree().current_scene
			if main and main.has_method("restart_level_for_checkpoint"):
				var level := get_node_or_null(target_level_path)
				if level:
					main.restart_level_for_checkpoint(level)
			elif main and main.has_method("force_current_level"):
				var level2 := get_node_or_null(target_level_path)
				if level2:
					main.force_current_level(level2)
