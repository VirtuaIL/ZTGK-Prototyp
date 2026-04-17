extends Area3D
class_name EnemyShield

@export var damage_to_player: float = 20.0
var damage_cooldown: float = 0.0

func _ready() -> void:
	# Avoid masking geometry or static props if not necessary, but safe to just collide with everything to catch players and rats
	collision_mask = 0xFFFFFFFF 
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if damage_cooldown > 0:
		damage_cooldown -= delta

func _on_body_entered(body: Node3D) -> void:
	# Instantly kill rats
	if body is Rat or body.has_method("die"):
		body.die()
	
	# Damage player
	if body.is_in_group("player") and body.has_method("take_damage"):
		if damage_cooldown <= 0.0:
			body.take_damage(damage_to_player)
			damage_cooldown = 0.5 # Give player half a second i-frames against the shield specifically

# Indestructible - ignores damage
func take_damage(_amount: float, _source_id: int = -1, _hit_pos: Vector3 = Vector3.ZERO, _text_color: Color = Color.WHITE) -> void:
	pass
