extends Area3D
class_name MortarProjectile

@export var damage: float = 40.0
@export var explosion_radius: float = 3.0

var velocity: Vector3 = Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * 2.0
var _lifetime: float = 0.0
var max_lifetime: float = 10.0
var is_exploded: bool = false
var explosion_mat_ref: StandardMaterial3D

func _ready() -> void:
	collision_mask = 15 | (1 << 8) # Floor (1) + Player (2) + Movable (4) + Walls (8) + RatStructures (9)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	if is_exploded:
		return
		
	velocity.y -= gravity * delta
	global_position += velocity * delta
	
	_lifetime += delta
	if _lifetime >= max_lifetime or global_position.y < -20.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if is_exploded:
		return
		
	# Explode immediately upon hitting something
	_explode()

func _explode() -> void:
	is_exploded = true
	
	# Deal splash damage
	var targets = []
	var players = get_tree().get_nodes_in_group("player")
	var mgr = get_tree().get_first_node_in_group("rat_manager")
	
	targets.append_array(players)
	if mgr != null and "rats" in mgr:
		for r in mgr.rats:
			if is_instance_valid(r):
				targets.append(r)
				
	for t in targets:
		if is_instance_valid(t) and t.is_inside_tree():
			var dist = global_position.distance_to(t.global_position)
			if dist <= explosion_radius:
				if t.is_in_group("player") and t.has_method("take_damage"):
					t.take_damage(damage)
				elif t.has_method("die"): # Rat
					t.die()

	# Hide original cannonball
	var mesh_instance = $MeshInstance3D
	if mesh_instance:
		mesh_instance.hide()
	
	var collision = $CollisionShape3D
	if collision:
		collision.set_deferred("disabled", true)
	
	# Create visual explosion
	var explosion_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = explosion_radius
	sphere.height = explosion_radius * 2.0
	explosion_mesh.mesh = sphere
	
	explosion_mat_ref = StandardMaterial3D.new()
	explosion_mat_ref.albedo_color = Color(1.0, 0.5, 0.0, 0.7)
	explosion_mat_ref.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	explosion_mat_ref.emission_enabled = true
	explosion_mat_ref.emission = Color(1.0, 0.5, 0.0)
	explosion_mat_ref.emission_energy_multiplier = 4.0
	explosion_mesh.material_override = explosion_mat_ref
	
	add_child(explosion_mesh)
	
	var tween = create_tween()
	tween.tween_property(explosion_mat_ref, "albedo_color:a", 0.0, 0.3)
	tween.parallel().tween_property(explosion_mesh, "scale", Vector3(1.1, 1.1, 1.1), 0.3)
	tween.tween_callback(queue_free)
