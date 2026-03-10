extends StaticBody3D

var damage_cooldowns: Dictionary = {}


func _ready() -> void:
	add_to_group("enemies")


func _process(delta: float) -> void:
	# Tick cooldowns
	var to_remove: Array = []
	for key in damage_cooldowns:
		damage_cooldowns[key] -= delta
		if damage_cooldowns[key] <= 0.0:
			to_remove.append(key)
	for key in to_remove:
		damage_cooldowns.erase(key)


func take_damage(amount: float, source_id: int = -1) -> void:
	# Per-source cooldown to prevent damage spam
	if source_id >= 0:
		if damage_cooldowns.has(source_id):
			return
		damage_cooldowns[source_id] = 0.3 # 0.3s cooldown per rat

	# Spawn damage number
	_spawn_damage_number(amount)

	# Flash white on hit
	_flash_hit()


func _spawn_damage_number(amount: float) -> void:
	var label := Label3D.new()
	label.text = str(round(amount))
	label.font_size = 48
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 5
	
	# Initial position with slight randomness
	label.position = Vector3(
		randf_range(-0.3, 0.3),
		2.2,
		randf_range(-0.3, 0.3)
	)
	add_child(label)
	
	# Animate: float up and fade out
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 1.5, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func _flash_hit() -> void:
	# Quick white flash on body
	# Assuming the body is the first MeshInstance3D child (from enemy.tscn)
	for child in get_children():
		if child is MeshInstance3D and child.name == "Body":
			if child.material_override:
				var original_color: Color = Color(0.8, 0.15, 0.15)
				child.material_override.albedo_color = Color(1.0, 1.0, 1.0)
				var tween := create_tween()
				tween.tween_property(child.material_override, "albedo_color", original_color, 0.15)
			break
