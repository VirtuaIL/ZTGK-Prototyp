extends Node3D
class_name healingCrystal

@export var heal_range: float = 25.0
@export var heal_rate: float = 50.0 # HP per second

var laser_mesh: MeshInstance3D
var _is_destroyed: bool = false

func _ready() -> void:
	add_to_group("healing_crystals")
	laser_mesh = get_node_or_null("LaserMesh")
	if not laser_mesh:
		# Fallback if no LaserMesh node exists in the scene
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.9, 0.3, 0.8) # Green laser
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.9, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		
		var mesh = CylinderMesh.new()
		mesh.top_radius = 0.1
		mesh.bottom_radius = 0.1
		mesh.material = mat
		
		laser_mesh = MeshInstance3D.new()
		laser_mesh.mesh = mesh
		add_child(laser_mesh)
	
	laser_mesh.visible = false

func _physics_process(delta: float) -> void:
	if _is_destroyed:
		return
		
	var bosses = get_tree().get_nodes_in_group("bosses")
	var healed_anyone = false
	
	# Only heal the closest one if multiple are in range
	var closest_boss: bossTurret = null
	var closest_dist = heal_range + 0.1
	
	var space_state := get_world_3d().direct_space_state
	
	for boss in bosses:
		if boss is bossTurret:
			if boss.current_state != bossTurret.State.DEAD and boss.health < boss.max_health:
				var dist = global_position.distance_to(boss.global_position)
				if dist <= heal_range and dist < closest_dist:
					var start_pos = global_position
					var end_pos = boss.global_position + Vector3(0, 0.7, 0)
					var query = PhysicsRayQueryParameters3D.create(start_pos, end_pos)
					query.collision_mask = 8 | 4 | (1 << 8) # Walls (8) + Movable (4) + RatStructures (256)
					query.exclude = [boss.get_rid()]
					var hit = space_state.intersect_ray(query)
					
					if hit:
						# Blocked connection: still display the laser towards the blockage
						_update_laser_visuals(start_pos, hit.position)
						closest_boss = null # Ensures no healing logic runs
						healed_anyone = true # Ensures laser_mesh.visible doesn't get set to false unnecessarily
					else:
						closest_dist = dist
						closest_boss = boss
						
	if closest_boss:
		# We found a boss to heal and line of sight is clear
		healed_anyone = true
		closest_boss.take_damage(-heal_rate * delta)
		
		# Draw laser fully to boss
		_update_laser_visuals(global_position, closest_boss.global_position + Vector3(0, 0.7, 0))
	
	if not healed_anyone:
		laser_mesh.visible = false

func _update_laser_visuals(start_pos: Vector3, end_pos: Vector3) -> void:
	if not laser_mesh: return
	
	laser_mesh.visible = true
	var distance = start_pos.distance_to(end_pos)
	
	if distance < 0.001:
		return
		
	var mid_point = start_pos.lerp(end_pos, 0.5)
	laser_mesh.global_position = mid_point
	laser_mesh.basis = Basis()
	
	var dir = (end_pos - start_pos).normalized()
	var up = Vector3.UP
	if abs(dir.y) > 0.99:
		up = Vector3.RIGHT
		
	laser_mesh.look_at(end_pos, up)
	laser_mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	laser_mesh.scale = Vector3(1.0, distance / 2.0, 1.0)

func receive_laser(delta: float) -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	remove_from_group("healing_crystals")
	
	if laser_mesh:
		laser_mesh.visible = false
		
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.2).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
