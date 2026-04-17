extends "res://scripts/enemies/enemy.gd"

const SniperProjectileScene = preload("res://scenes/projectiles/projectile.tscn")

var laser_visual: MeshInstance3D
var laser_mat: StandardMaterial3D
var lock_on_time: float = 0.5
var is_locked: bool = false
var flee_range: float = 12.0

func _ready() -> void:
	super._ready()
	max_health = 40.0
	health = max_health
	
	attack_range = 25.0
	detection_range = 45.0
	lose_range = 50.0
	chase_speed = 3.5
	attack_delay = 2.0
	movement_pattern = MovePattern.KITE
	kite_preferred_range = 16.0
	strafe_bias = 0.55
	wall_avoidance_force = 3.0
	attack_cooldown = 3.5
	
	laser_visual = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 1.0
	laser_visual.mesh = cyl
	laser_mat = StandardMaterial3D.new()
	laser_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.6)
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.emission_enabled = true
	laser_mat.emission = Color(1.0, 0.0, 0.0)
	laser_mat.emission_energy_multiplier = 2.0
	laser_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	laser_visual.material_override = laser_mat
	
	laser_visual.rotation_degrees = Vector3(90, 0, 0)
	laser_visual.visible = false
	add_child(laser_visual)

func _find_target() -> void:
	var players = get_tree().get_nodes_in_group("player")
	var best_d := INF
	var best_t: Node3D = null
	
	for p in players:
		if is_instance_valid(p) and p.is_inside_tree():
			var curr_d = global_position.distance_squared_to(p.global_position)
			if curr_d < best_d:
				best_d = curr_d
				best_t = p
				
	_player_ref = best_t as CharacterBody3D

func _process_chase(delta: float) -> void:
	_find_target()
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		return

	var dist := _distance_to_player()

	if dist > lose_range:
		ai_state = AIState.WANDER
		return

	# Close enough to attack
	if dist < attack_range:
		ai_state = AIState.ATTACK
		_attack_timer = 0.0
		return

	# If player is too close, run away from them
	if dist < flee_range:
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		var away := -to_player.normalized()
		velocity.x = away.x * chase_speed * 1.3
		velocity.z = away.z * chase_speed * 1.3
		var target_angle := atan2(away.x, away.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	else:
		# Move toward player to get in attack range
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		var dir := to_player.normalized()
		velocity.x = dir.x * chase_speed
		velocity.z = dir.z * chase_speed
		var target_angle := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

func _process_attack(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		laser_visual.visible = false
		is_locked = false
		return

	var dist := _distance_to_player()
	
	# Aggressively flee from player if too close
	var to_player := _player_ref.global_position - global_position
	to_player.y = 0.0
	if dist < flee_range:
		var away_dir := -to_player.normalized()
		velocity.x = away_dir.x * chase_speed * 1.3
		velocity.z = away_dir.z * chase_speed * 1.3
		var flee_angle := atan2(away_dir.x, away_dir.z)
		rotation.y = lerp_angle(rotation.y, flee_angle, rotation_speed * delta)
	else:
		# Stop moving when at safe range
		velocity.x = move_toward(velocity.x, 0.0, chase_speed * delta * 15.0)
		velocity.z = move_toward(velocity.z, 0.0, chase_speed * delta * 15.0)

	if attack_prepare_timer > 0.0:
		attack_prepare_timer -= delta
		
		var laser_len = 30.0
		laser_visual.scale = Vector3(1.0, laser_len, 1.0)
		laser_visual.position = Vector3(0, 1.0, laser_len * 0.5)
		
		if attack_prepare_timer <= lock_on_time:
			# Locked phase
			if not is_locked:
				is_locked = true
				laser_mat.albedo_color = Color(1.0, 0.5, 0.8, 0.8)
				laser_mat.emission = Color(1.0, 0.5, 0.8)
				laser_mat.emission_energy_multiplier = 4.0
		else:
			# Tracking phase
			is_locked = false
			laser_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.6)
			laser_mat.emission = Color(1.0, 0.0, 0.0)
			laser_mat.emission_energy_multiplier = 2.0
			
			if to_player.length() > 0.01:
				var target_angle := atan2(to_player.x, to_player.z)
				rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * 1.5 * delta)
				
		laser_visual.visible = true
			
		if attack_prepare_timer <= 0.0:
			_shoot()
			laser_visual.visible = false
			is_locked = false
			_attack_timer = attack_cooldown
			
			var body: MeshInstance3D = get_child(0) as MeshInstance3D
			if body and body.material_override:
				body.material_override.albedo_color = Color(0.1, 0.1, 0.5)
		return

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		if dist > attack_range * 0.9:
			ai_state = AIState.CHASE
			return
		attack_prepare_timer = attack_delay
		is_locked = false
	else:
		# Track player and back away during cooldown
		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * 0.5 * delta)
			# Back away during cooldown
			if dist < flee_range * 1.5:
				var away_dir := -to_player.normalized()
				velocity.x = away_dir.x * chase_speed
				velocity.z = away_dir.z * chase_speed

func _shoot() -> void:
	if SniperProjectileScene:
		var p = SniperProjectileScene.instantiate()
		get_parent().add_child(p)
		
		if "deal_damage_instead_of_kill" in p:
			p.deal_damage_instead_of_kill = true
		if "damage" in p:
			p.damage = 50.0
		if "speed" in p:
			p.speed = 25.0
		
		# Set global position out of the box so it isn't blocked by enemy collider if any exists
		p.global_position = global_position + Vector3(0, 1.0, 0)
		var my_forward = Vector3(sin(rotation.y), 0, cos(rotation.y)).normalized()
		p.global_position += my_forward * 1.0
		p.velocity = my_forward * p.speed
