extends "res://scripts/enemies/enemy.gd"

const MortarProjectileScene = preload("res://scenes/projectiles/mortar_projectile.tscn")

var is_aiming: bool = false
var aim_target_pos: Vector3 = Vector3.ZERO
var aim_marker: MeshInstance3D = null
@export var explosion_radius: float = 8.0

func _ready() -> void:
	super._ready()
	max_health = 80.0
	health = max_health
	
	attack_range = 25.0 
	detection_range = 35.0
	lose_range = 40.0
	chase_speed = 2.0
	attack_delay = 1.5
	attack_cooldown = 5.0
	
	_ensure_aim_marker()

func _ensure_aim_marker() -> void:
	if aim_marker != null and is_instance_valid(aim_marker):
		return
		
	aim_marker = MeshInstance3D.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	aim_marker.material_override = mat
	aim_marker.visible = false
	
	var immediate = ImmediateMesh.new()
	aim_marker.mesh = immediate
	var r = explosion_radius
	var segments = 32
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a1 = (float(i) / segments) * TAU
		var a2 = (float(i + 1) / segments) * TAU
		immediate.surface_add_vertex(Vector3(0, 0.1, 0))
		immediate.surface_add_vertex(Vector3(sin(a1)*r, 0.1, cos(a1)*r))
		immediate.surface_add_vertex(Vector3(sin(a2)*r, 0.1, cos(a2)*r))
	immediate.surface_end()
	
	get_tree().current_scene.call_deferred("add_child", aim_marker)

func _exit_tree() -> void:
	if aim_marker != null and is_instance_valid(aim_marker):
		aim_marker.queue_free()

func _process_attack(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		if aim_marker:
			aim_marker.visible = false
		is_aiming = false
		return

	var dist := _distance_to_player()
	
	velocity.x = move_toward(velocity.x, 0.0, chase_speed * delta * 15.0)
	velocity.z = move_toward(velocity.z, 0.0, chase_speed * delta * 15.0)

	if attack_prepare_timer > 0.0:
		attack_prepare_timer -= delta
		
		if not is_aiming:
			is_aiming = true
			# We aim slightly ahead or exactly at player
			aim_target_pos = _player_ref.global_position
			
			# Find floor level via raycast
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(aim_target_pos + Vector3(0, 1, 0), aim_target_pos + Vector3(0, -10, 0), 1)
			var result = space_state.intersect_ray(query)
			if result:
				aim_target_pos.y = result.position.y
			else:
				aim_target_pos.y = _player_ref.global_position.y
				
			_ensure_aim_marker()
			if aim_marker:
				aim_marker.global_position = aim_target_pos
				aim_marker.visible = true
				
			var body: MeshInstance3D = get_child(0) as MeshInstance3D
			if body and body.material_override:
				body.material_override.albedo_color = Color(1.0, 0.0, 1.0)
		
		var to_aim := aim_target_pos - global_position
		to_aim.y = 0.0
		if to_aim.length() > 0.01:
			var target_angle := atan2(to_aim.x, to_aim.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * 1.5 * delta)
			
		if attack_prepare_timer <= 0.0:
			_shoot()
			# aim_marker is now owned by projectile, don't hide it here
			aim_marker = null
			is_aiming = false
			_attack_timer = attack_cooldown
			
			var body: MeshInstance3D = get_child(0) as MeshInstance3D
			if body and body.material_override:
				body.material_override.albedo_color = Color(0.5, 0.0, 0.5)
		return

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		if dist > attack_range * 0.9:
			ai_state = AIState.CHASE
			return
		attack_prepare_timer = attack_delay
		is_aiming = false
	else:
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * 0.5 * delta)

func _shoot() -> void:
	if MortarProjectileScene:
		var p = MortarProjectileScene.instantiate()
		get_parent().add_child(p)
		
		# Hand off marker to projectile
		if p.has_method("set") or "target_marker" in p:
			p.target_marker = aim_marker
		# Sync damage radius with the visual aim indicator
		p.explosion_radius = explosion_radius
		
		var spawn_pos = global_position + Vector3(0, 1.5, 0)
		var my_forward = Vector3(sin(rotation.y), 0, cos(rotation.y)).normalized()
		p.global_position = spawn_pos + my_forward * 1.0
		
		# Give it 1.5s to reach the target pos
		var t = 1.5
		var proj_gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * 2.0
		if p.get("fall_gravity") != null:
			proj_gravity = p.fall_gravity
			
		var d_pos = aim_target_pos - p.global_position
		var v_y = (d_pos.y + 0.5 * proj_gravity * t * t) / t
		var v_xz = Vector3(d_pos.x, 0, d_pos.z) / t
		
		p.velocity = Vector3(v_xz.x, v_y, v_xz.z)
