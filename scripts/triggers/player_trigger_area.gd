extends Area3D
class_name PlayerTriggerArea

## Emitted when the player enters the bounds of this trigger cube
signal player_entered

@export var size: Vector3 = Vector3(2.0, 2.0, 2.0)
@export var trigger_once: bool = true

func _ready() -> void:
	# Automatically construct an invisible Box collision for the trigger Area!
	var shape = BoxShape3D.new()
	shape.size = size
	var coll = CollisionShape3D.new()
	coll.shape = shape
	add_child(coll)
	
	# Only alert for physics bodies that cross into it
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	# Relying on "player" group tags is robust against varying physics layer setups
	if body.is_in_group("player"):
		print("player entered")
		player_entered.emit()
		
		# Immediately disable to avoid double triggering if set to activate only once
		if trigger_once:
			queue_free()
