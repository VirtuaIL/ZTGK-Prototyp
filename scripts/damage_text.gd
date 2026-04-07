extends Node3D

@export var duration: float = 0.8
var _time_alive: float = 0.0
var _velocity: Vector3 = Vector3(0, 2.0, 0)
@onready var label = $Label3D

func set_damage(amount: int, color: Color) -> void:
	if label:
		label.text = str(amount)
		label.modulate = color
		
		# add slight random horizontal velocity
		_velocity.x = randf_range(-1.0, 1.0)
		_velocity.z = randf_range(-1.0, 1.0)

func _physics_process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= duration:
		queue_free()
		return
		
	position += _velocity * delta
	_velocity.y -= delta * 1.0 # Slight gravity
	
	if label:
		var alpha = clampf(1.0 - (_time_alive / duration), 0.0, 1.0)
		label.outline_modulate.a = alpha
		var c = label.modulate
		c.a = alpha
		label.modulate = c
