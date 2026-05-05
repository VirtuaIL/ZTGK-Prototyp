extends "res://scripts/enemies/mortar_enemy.gd"

func _ready() -> void:
	super._ready()
	max_health = 80.0
	health = max_health
	
	attack_range = 250.0 
	detection_range = 500.0
	lose_range = 550.0
	chase_speed = 0.0
	attack_delay = 4.5
	attack_cooldown = 5.0
	movement_pattern = MovePattern.KITE
	kite_preferred_range = 14.0
	strafe_bias = 0.45
	wall_avoidance_force = 3.2
	
	_ensure_aim_marker()
