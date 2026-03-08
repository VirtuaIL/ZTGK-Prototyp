extends CharacterBody3D

signal stratagem_activated(stratagem_id: String)

@export var speed: float = 7.0
@export var rotation_speed: float = 10.0

var is_stratagem_mode: bool = false


func _ready() -> void:
	# Body mesh (capsule)
	var body_mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	body_mesh.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 0.3)
	body_mesh.material_override = mat
	body_mesh.position.y = 0.8
	add_child(body_mesh)

	# Collision shape
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.6
	col.shape = shape
	col.position.y = 0.8
	add_child(col)


func _physics_process(delta: float) -> void:
	if is_stratagem_mode:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var input_dir := Vector3.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.z = Input.get_axis("move_forward", "move_back")

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		velocity = input_dir * speed

		var target_angle := atan2(input_dir.x, input_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, speed * delta * 5.0)

	move_and_slide()


func set_stratagem_mode(active: bool) -> void:
	is_stratagem_mode = active
