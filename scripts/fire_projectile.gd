extends Node3D
class_name FireProjectile

@export var speed: float = 12.0

var velocity: Vector3 = Vector3.ZERO
var max_lifetime: float = 0.5
var _lifetime: float = 0.0

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()
		return
		
	var s = 1.0 - (_lifetime / max_lifetime)
	scale = Vector3(s, s, s)
