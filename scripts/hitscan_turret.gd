extends CharacterBody3D
class_name hitscan_turret

@export var damage_per_second: float = 34.0 # Player dies in ~3 seconds of continuous damage
@export var attack_range: float = 20.0
@export var turn_speed: float = 8.0
@export var carriers_required: int = 4
@export var fall_death_y: float = -1.0
@export var gravity_multiplier: float = 5.0

signal object_reset

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []
var carrier_available_max: int = 0
var carrier_brush_desired: int = 0
var _spawn_position: Vector3 = Vector3.ZERO

var player_node: player = null
@onready var fire_point: Vector3 = Vector3(0, 0.7, 0) # Adjust based on the turret mesh

@onready var laser_mesh: MeshInstance3D = $LaserMesh

func _ready() -> void:
	add_to_group("turrets")
	collision_layer = 4 # Layer 3: Movable
	collision_mask = 31 | (1 << 8)  # Floor (1) + Player (2) + Movable (4) + Walls (8) + Barrier (16) + RatStructures (9)
	_spawn_position = global_position
	# Find the player in the scene
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_node = players[0]
	else:
		player_node = get_node_or_null("/root/Main/Player")

	
	# Ensure the laser starts invisible
	if laser_mesh:
		laser_mesh.visible = false

func _physics_process(delta: float) -> void:
	# Fall reset
	if global_position.y < fall_death_y:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		object_reset.emit()
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * gravity_multiplier
	else:
		velocity.y = 0.0

	move_and_slide()

	if not player_node:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
		
		if laser_mesh:
			laser_mesh.visible = false
		return

	var dist_to_player = global_position.distance_to(player_node.global_position)
	if dist_to_player <= attack_range:
		_aim_at_player(delta)
		_process_laser(delta)
	else:
		if laser_mesh:
			laser_mesh.visible = false

func _aim_at_player(delta: float) -> void:
	var target_pos = player_node.global_position
	target_pos.y = global_position.y # Only rotate horizontally
	
	var dir = (target_pos - global_position).normalized()
	if dir.length() > 0.1:
		var target_angle = atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)

func _process_laser(delta: float) -> void:
	if not laser_mesh:
		return

	var space_state := get_world_3d().direct_space_state
	
	var start_pos = global_position + fire_point
	var target_pos = player_node.global_position
	target_pos.y += 0.5 # Aim slightly above ground, at player's center
	
	var dir = (target_pos - start_pos).normalized()
	start_pos = global_position + fire_point + (dir * 0.01)
	var ray_end = start_pos + dir * attack_range
	
	var query := PhysicsRayQueryParameters3D.create(start_pos, ray_end)
	query.collision_mask = 15 | (1 << 8) # Floor (1) + Player (2) + Movable (4) + Walls (8) + RatStructures (9)
	# Exclude self if needed, but the laser originates from outside the collision shape usually 
	query.exclude = [self.get_rid()]
	
	var hit := space_state.intersect_ray(query)
	
	if hit:
		var hit_pos: Vector3 = hit.position
		_update_laser_visuals(start_pos, hit_pos)
		
		# Chain redirection or instant-kill player
		if hit.collider.has_method("receive_laser"):
			hit.collider.receive_laser(delta)
		elif hit.collider.is_in_group("rat_structures"):
			var manager = hit.collider.get_parent()
			if manager and manager.has_method("receive_laser"):
				manager.receive_laser(delta)
		elif hit.collider.has_method("die"):
			hit.collider.die()
	else:
		# If we hit nothing, draw laser to max range (shouldn't realistically happen if enclosed)
		_update_laser_visuals(start_pos, ray_end)


func set_highlight(enabled: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			# Skip the laser mesh itself
			if child.name == "LaserMesh": continue
			
			if enabled:
				if child.material_overlay: continue
				var highlight_mat = StandardMaterial3D.new()
				highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				highlight_mat.albedo_color = Color.YELLOW
				highlight_mat.cull_mode = BaseMaterial3D.CULL_FRONT
				highlight_mat.no_depth_test = true
				highlight_mat.grow = true
				highlight_mat.grow_amount = 0.03
				child.material_overlay = highlight_mat
			else:
				child.material_overlay = null

func _update_laser_visuals(start_pos: Vector3, end_pos: Vector3) -> void:
	laser_mesh.visible = true
	var distance = start_pos.distance_to(end_pos)
	
	if distance < 0.001:
		return
		
	var mid_point = start_pos.lerp(end_pos, 0.5)
	
	# Set global position to center
	laser_mesh.global_position = mid_point
	
	# Reset rotation before look_at to avoid cumulative issues
	laser_mesh.basis = Basis()
	
	# Point -Z axis at the target
	# Use a safe up vector depending on the direction
	var dir = (end_pos - start_pos).normalized()
	var up = Vector3.UP
	if abs(dir.y) > 0.99:
		up = Vector3.RIGHT
		
	laser_mesh.look_at(end_pos, up)
	
	# Rotate 90 degrees around local X to make the cylinder (which points up Y) point forward (-Z)
	laser_mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	
	# Scale the height (Y). Default cylinder height is 2.0, so divide distance by 2.0
	laser_mesh.scale = Vector3(1.0, distance / 2.0, 1.0)
