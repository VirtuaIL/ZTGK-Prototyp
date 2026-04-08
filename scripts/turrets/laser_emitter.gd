extends StaticBody3D
class_name laser_emitter

@export var damage_per_second: float = 34.0
@export var max_range: float = 50.0
@export var is_active: bool = true

@onready var laser_mesh: MeshInstance3D = $LaserMesh
@onready var fire_point: Vector3 = Vector3(0, 0, 0) # Ray starts at origin of emitter

func _ready() -> void:
	# Ensure the laser starts invisible if inactive
	if laser_mesh:
		laser_mesh.visible = is_active

func _physics_process(delta: float) -> void:
	if not is_active:
		if laser_mesh:
			laser_mesh.visible = false
		return
		
	_process_laser(delta)

func _process_laser(delta: float) -> void:
	if not laser_mesh:
		return

	var space_state := get_world_3d().direct_space_state
	
	var start_pos = global_position + (-global_transform.basis.z * 0.01)
	# The laser always points in the emitter's -Z direction (forward)
	var dir = -global_transform.basis.z.normalized()
	var ray_end = start_pos + dir * max_range
	
	var query := PhysicsRayQueryParameters3D.create(start_pos, ray_end)
	query.collision_mask = 15 # Floor (1) + Player (2) + Movable (4) + Walls (8)
	query.exclude = [self.get_rid()]
	
	var hit := space_state.intersect_ray(query)
	
	if hit:
		var hit_pos: Vector3 = hit.position
		_update_laser_visuals(start_pos, hit_pos)
		
		# Chain redirection or damage
		if hit.collider.has_method("receive_laser"):
			hit.collider.receive_laser(delta)
		elif hit.collider.has_method("take_damage"):
			hit.collider.take_damage(damage_per_second * delta)
	else:
		_update_laser_visuals(start_pos, ray_end)

func _update_laser_visuals(start_pos: Vector3, end_pos: Vector3) -> void:
	laser_mesh.visible = true
	var distance = start_pos.distance_to(end_pos)
	
	if distance < 0.001:
		laser_mesh.visible = false
		return
		
	var mid_point = start_pos.lerp(end_pos, 0.5)
	laser_mesh.global_position = mid_point
	
	# Reset rotation
	laser_mesh.basis = Basis()
	
	# Point -Z axis at the target
	var dir = (end_pos - start_pos).normalized()
	var up = Vector3.UP
	if abs(dir.y) > 0.99:
		up = Vector3.RIGHT
		
	laser_mesh.look_at(end_pos, up)
	laser_mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	
	# Cylinder is 2.0m tall by default
	laser_mesh.scale = Vector3(0.1, distance / 2.0, 0.1)
