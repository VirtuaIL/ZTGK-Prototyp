extends Area3D
class_name Projectile

@export var speed: float = 20.0
@export var damage: float = 10.0 # Just in case we want to deal damage later

var velocity: Vector3 = Vector3.ZERO
var max_lifetime: float = 5.0
var _lifetime: float = 0.0

func _ready() -> void:
	collision_mask = 15 # Floor (1) + Player (2) + Movable (4) + Walls (8)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if body is player:
		if body.has_method("take_damage"):
			body.take_damage(body.max_hp * 0.5)
		queue_free()
	elif not (body is turret or body is hitscan_turret):
		# Hit wall, box, floor, or wall button
		if body.has_method("on_projectile_hit"):
			body.on_projectile_hit()
		elif body.is_in_group("rat_structures"):
			var manager = body.get_parent()
			if manager and manager.has_method("on_projectile_hit"):
				manager.on_projectile_hit()
		queue_free()
