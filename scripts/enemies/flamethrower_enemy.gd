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
var flame_particles: GPUParticles3D
var _flame_telegraph: MeshInstance3D = null
var _flame_telegraph_mat: StandardMaterial3D = null

func _ready() -> void:
	super._ready()
	max_health = 250.0
	health = max_health
	
	attack_range = 10.0
	detection_range = 35.0
	lose_range = 42.0
	attack_damage = 20.0
	attack_cooldown = 5.0
	attack_delay = 2.0
	movement_pattern = MovePattern.STRAFE
	strafe_bias = 0.62
	wall_avoidance_force = 3.4
	chase_speed = 1.5

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

	flame_particles = GPUParticles3D.new()
	flame_particles.name = "FlameParticles"
	flame_particles.amount = 120
	flame_particles.lifetime = 0.35
	flame_particles.one_shot = false
	flame_particles.emitting = false
	flame_particles.visible = false
	flame_particles.randomness = 0.8
	flame_particles.fixed_fps = 30
	flame_particles.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	flame_particles.position = Vector3(0, 1.0, 0.6)
	flame_particles.rotation_degrees = Vector3(0, 0, 0)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.12)
	flame_particles.draw_pass_1 = quad

	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	pmat.emission_enabled = true
	pmat.emission = Color(1.0, 0.25, 0.05, 1.0)
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = pmat

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.2, 0.15, 0.2)
	proc.direction = Vector3(0, 0.05, 1)
	proc.spread = 18.0
	proc.initial_velocity_min = 6.0
	proc.initial_velocity_max = 10.0
	proc.scale_min = 0.5
	proc.scale_max = 1.1
	proc.gravity = Vector3(0, 0.6, 0)
	proc.damping_min = 0.4
	proc.damping_max = 0.7
	flame_particles.process_material = proc
	add_child(flame_particles)

	# ── White ground telegraph for flame attack ──
	_flame_telegraph = MeshInstance3D.new()
	_flame_telegraph.layers = 2
	var tele_mesh := ImmediateMesh.new()
	_flame_telegraph.mesh = tele_mesh
	tele_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var tele_segments := 20
	var tele_r := attack_range
	var tele_half_angle: float = flame_spray_angle
	for i in range(tele_segments):
		var a1 := -tele_half_angle + (float(i) / tele_segments) * (tele_half_angle * 2.0)
		var a2 := -tele_half_angle + (float(i + 1) / tele_segments) * (tele_half_angle * 2.0)
		tele_mesh.surface_add_vertex(Vector3(0, 0.08, 0))
		tele_mesh.surface_add_vertex(Vector3(-sin(a1) * tele_r, 0.08, cos(a1) * tele_r))
		tele_mesh.surface_add_vertex(Vector3(-sin(a2) * tele_r, 0.08, cos(a2) * tele_r))
	tele_mesh.surface_end()
	_flame_telegraph_mat = StandardMaterial3D.new()
	_flame_telegraph_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	_flame_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_telegraph_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_telegraph_mat.no_depth_test = true
	_flame_telegraph.material_override = _flame_telegraph_mat
	_flame_telegraph.visible = false
	add_child(_flame_telegraph)

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
		if _flame_telegraph:
			_flame_telegraph.visible = false
		return

	var dist := _distance_to_player()
	var to_player := _player_ref.global_position - global_position
	to_player.y = 0.0
	
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

		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
			
		# Show telegraph during windup
		if _flame_telegraph:
			_flame_telegraph.visible = true
			if _flame_telegraph_mat:
				var pulse := sin(Time.get_ticks_msec() * 0.01) * 0.12
				var progress := 1.0 - clampf(attack_prepare_timer / maxf(0.01, attack_delay), 0.0, 1.0)
				var base_a := 0.35 + progress * 0.3
				_flame_telegraph_mat.albedo_color = Color(1.0, 1.0, 1.0, clampf(base_a + pulse, 0.1, 0.8))

		if attack_prepare_timer <= 0.0:
			_play_attack_animation()
			is_flamethrowing = true
			flame_timer = flame_duration
			fire_tick_timer = 0.0
			recent_hits.clear()
			if body and body.material_override:
				body.material_override.albedo_color = Color(0.8, 0.1, 0.1) # red
			if _flame_telegraph:
				_flame_telegraph.visible = false
		return

	if is_flamethrowing:
		flame_timer -= delta
		fire_tick_timer -= delta
		
		if flame_visual:
			flame_visual.visible = true
			var jiggle = randf_range(0.9, 1.1)
			flame_visual.scale = Vector3(jiggle, randf_range(0.95, 1.05), jiggle)
		if flame_particles:
			flame_particles.visible = true
			flame_particles.emitting = true
		
		# Slowly track player while firing
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
			if flame_particles:
				flame_particles.emitting = false
				flame_particles.visible = false
		return

	_attack_timer -= delta
	if _attack_timer <= 0.0:
		if dist > attack_range * 1.5:
			ai_state = AIState.CHASE
			return
		attack_prepare_timer = attack_delay
		_play_windup_animation()
		var body: MeshInstance3D = get_child(0) as MeshInstance3D
		if body and body.material_override:
			body.material_override.albedo_color = Color(1.0, 0.5, 0.0) # windup
		if flame_particles:
			flame_particles.emitting = false
			flame_particles.visible = false
		if _flame_telegraph:
			_flame_telegraph.visible = false
	else:
		if to_player.length() > 0.01:
			var target_angle := atan2(to_player.x, to_player.z)
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
			# Strafe sideways while waiting for cooldown
			var strafe_dir := to_player.normalized().cross(Vector3.UP)
			velocity.x = strafe_dir.x * chase_speed * 0.6
			velocity.z = strafe_dir.z * chase_speed * 0.6

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
