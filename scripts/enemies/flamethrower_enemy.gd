extends "res://scripts/enemies/enemy.gd"

const FireParticleScene = preload("res://scenes/projectiles/fire_projectile.tscn")

var is_flamethrowing: bool = false
var flame_timer: float = 0.0
var flame_duration: float = 2.0
var fire_tick_timer: float = 0.0
var fire_tick_rate: float = 0.1
var flame_spray_angle = deg_to_rad(30.0)

var recent_hits: Dictionary = {}
var flame_visual: MeshInstance3D

func _ready() -> void:
	super._ready()
	max_health = 130.0 
	health = max_health
	
	attack_range = 10.0 
	detection_range = 20.0
	lose_range = 25.0
	attack_damage = 20.0 
	attack_cooldown = 4.0
	attack_delay = 1.0

	flame_visual = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 2.5
	cone.bottom_radius = 0.0
	cone.height = attack_range
	flame_visual.mesh = cone
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.0)
	mat.emission_energy_multiplier = 2.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame_visual.material_override = mat
	flame_visual.position = Vector3(0, 1.0, attack_range * 0.5)
	flame_visual.rotation_degrees = Vector3(90, 0, 0)
	flame_visual.visible = false
	add_child(flame_visual)

func _process_attack(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		ai_state = AIState.WANDER
		if is_flamethrowing:
			is_flamethrowing = false
			var body: MeshInstance3D = get_child(0) as MeshInstance3D
			if body and body.material_override:
				body.material_override.albedo_color = Color(0.7, 0.3, 0.1)
			if flame_visual:
				flame_visual.visible = false
		return

	var dist := _distance_to_player()
	
	# Slow down while attacking
	velocity.x = move_toward(velocity.x, 0.0, chase_speed * delta * 5.0)
	velocity.z = move_toward(velocity.z, 0.0, chase_speed * delta * 5.0)

	# Clean up damage cooldowns
	var to_remove = []
	for t in recent_hits:
		recent_hits[t] -= delta
		if recent_hits[t] <= 0.0:
			to_remove.append(t)
	for t in to_remove:
		recent_hits.erase(t)

	if attack_prepare_timer > 0.0:
		attack_prepare_timer -= delta
		
		var body: MeshInstance3D = get_child(0) as MeshInstance3D
		if body and body.material_override:
			var flash_rate = 24.0
			var is_flash_frame = int(attack_prepare_timer * flash_rate) % 2 == 0
			if is_flash_frame:
				body.material_override.albedo_color = Color(1.0, 0.9, 0.2) # Bright flash
			else:
				body.material_override.albedo_color = Color(1.0, 0.5, 0.0) # Windup orange

		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
			
		if attack_prepare_timer <= 0.0:
			is_flamethrowing = true
			flame_timer = flame_duration
			fire_tick_timer = 0.0
			recent_hits.clear()
			if body and body.material_override:
				body.material_override.albedo_color = Color(0.8, 0.1, 0.1) # red
		return

	if is_flamethrowing:
		flame_timer -= delta
		fire_tick_timer -= delta
		
		if flame_visual:
			flame_visual.visible = true
			var jiggle = randf_range(0.9, 1.1)
			flame_visual.scale = Vector3(jiggle, randf_range(0.95, 1.05), jiggle)
		
		# Slowly track player while firing
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, (rotation_speed * 0.3) * delta)
			
		if fire_tick_timer <= 0.0:
			fire_tick_timer = fire_tick_rate
			_shoot_fire()
			
		if flame_timer <= 0.0:
			is_flamethrowing = false
			_attack_timer = attack_cooldown
			var body: MeshInstance3D = get_child(0) as MeshInstance3D
			if body and body.material_override:
				body.material_override.albedo_color = Color(0.7, 0.3, 0.1)
			if flame_visual:
				flame_visual.visible = false
		return

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		if dist > attack_range * 1.5:
			ai_state = AIState.CHASE
			return
		attack_prepare_timer = attack_delay
		var body: MeshInstance3D = get_child(0) as MeshInstance3D
		if body and body.material_override:
			body.material_override.albedo_color = Color(1.0, 0.5, 0.0) # windup
	else:
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

func _shoot_fire() -> void:
	var targets = []
	var players = get_tree().get_nodes_in_group("player")
	var mgr = get_tree().get_first_node_in_group("rat_manager")
	targets.append_array(players)
	if mgr != null:
		var purple_active = mgr.get("buff_purple_timer") != null and mgr.buff_purple_timer > 0.0
		if not purple_active:
			if "rats" in mgr:
				for r in mgr.rats:
					if is_instance_valid(r):
						targets.append(r)
			if "wild_rats" in mgr:
				for wr in mgr.wild_rats:
					if is_instance_valid(wr):
						targets.append(wr)
					
	var my_forward = Vector3(sin(rotation.y), 0, cos(rotation.y))
	
	for t in targets:
		if not is_instance_valid(t) or not t.is_inside_tree():
			continue
			
		if recent_hits.has(t) and recent_hits[t] > 0.0:
			continue
			
		var to_t = t.global_position - global_position
		to_t.y = 0.0
		var d = to_t.length()
		
		if d <= attack_range:
			var dir = to_t.normalized()
			var angle_diff = acos(clampf(my_forward.dot(dir), -1.0, 1.0))
			if angle_diff <= flame_spray_angle:
				if t.is_in_group("player") and t.has_method("take_damage"):
					t.take_damage(attack_damage)
					recent_hits[t] = 0.5 # Hit max once every 0.5s per attack
				elif t.has_method("die"):
					t.die()
					recent_hits[t] = 0.5 
