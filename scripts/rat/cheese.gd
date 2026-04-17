extends Area3D

enum Type { RED, GREEN, YELLOW, PURPLE }

var type: int = Type.YELLOW
var time_alive: float = 0.0
var _scan_timer: float = 0.0
var _mgr: Node = null

@export var pickup_radius: float = 1.5
@export var scan_interval: float = 0.1

func set_type(new_type: int) -> void:
	type = new_type
	_update_visuals()

func _ready() -> void:
	_update_visuals()
	_mgr = get_tree().get_first_node_in_group("rat_manager")
	add_to_group("dropped_items")

func _update_visuals() -> void:
	var mesh_inst = $MeshInstance3D
	if not mesh_inst:
		return
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.8
	
	var particles = get_node_or_null("ToxicParticles")
	if not particles:
		particles = GPUParticles3D.new()
		particles.name = "ToxicParticles"
		particles.amount = 8
		particles.lifetime = 1.0
		
		var pmat = ParticleProcessMaterial.new()
		pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pmat.emission_sphere_radius = 0.5
		pmat.direction = Vector3(0, 1, 0)
		pmat.spread = 15.0
		pmat.initial_velocity_min = 0.5
		pmat.initial_velocity_max = 1.5
		pmat.gravity = Vector3(0, 0.5, 0)
		pmat.scale_min = 0.2
		pmat.scale_max = 0.5
		
		var cramp = GradientTexture1D.new()
		var grad = Gradient.new()
		grad.set_color(0, Color(0.6, 0.1, 0.9, 0.8)) # Purple
		grad.add_point(0.5, Color(0.4, 0.8, 0.2, 0.5)) # Sickly green
		grad.set_color(1, Color(0.2, 0.8, 0.1, 0.0))
		cramp.gradient = grad
		pmat.color_ramp = cramp
		particles.process_material = pmat
		
		var img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		var c0 = Color(0, 0, 0, 0)
		var c1 = Color(1, 1, 1, 1)
		var c2 = Color(0, 0, 0, 1)
		img.fill(c0)
		
		var pixels = [
			0,0,1,1,1,1,0,0,
			0,1,1,1,1,1,1,0,
			1,1,0,1,1,0,1,1,
			1,1,0,1,1,0,1,1,
			0,1,1,1,1,1,1,0,
			0,0,1,0,0,1,0,0,
			0,0,1,0,0,1,0,0,
			0,0,0,0,0,0,0,0
		]
		for i in range(64):
			var x = i % 8
			var y = int(i / 8)
			if pixels[i] == 1:
				img.set_pixel(x, y, c1)
			elif y >= 2 and y <= 3 and (x == 2 or x == 5):
				img.set_pixel(x, y, c0) # empty eyes
		
		var tex = ImageTexture.create_from_image(img)
		
		var quad = QuadMesh.new()
		quad.size = Vector2(0.3, 0.3)
		var qmat = StandardMaterial3D.new()
		qmat.albedo_texture = tex
		qmat.vertex_color_use_as_albedo = true
		qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		quad.material = qmat
		particles.draw_pass_1 = quad
		
		add_child(particles)
	
	match type:
		Type.RED:
			mat.albedo_color = Color(0.9, 0.1, 0.1) # Aggression
			particles.emitting = false
		Type.GREEN:
			mat.albedo_color = Color(0.1, 0.9, 0.1) # Gas
			particles.emitting = false
		Type.YELLOW:
			mat.albedo_color = Color(0.9, 0.9, 0.1) # Immortality
			particles.emitting = false
		Type.PURPLE:
			mat.albedo_color = Color(0.6, 0.1, 0.9) # Loss of control, no aggro
			particles.emitting = true

	# Trutka (PURPLE) ma model kuli, reszta zostaje z pryzma
	if type == Type.PURPLE:
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		mesh_inst.mesh = sphere

	mesh_inst.material_override = mat

func _physics_process(delta: float) -> void:
	time_alive += delta
	
	# Hover and spin animation
	var mesh_inst = $MeshInstance3D
	if mesh_inst:
		mesh_inst.position.y = sin(time_alive * 3.0) * 0.1
		mesh_inst.rotation.y += delta * 2.0
	
	# Check for nearby rats manually (since rats have collision_layer=0)
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = max(0.02, scan_interval)
	if _mgr == null or not is_instance_valid(_mgr):
		_mgr = get_tree().get_first_node_in_group("rat_manager")
	var mgr = _mgr
	if mgr != null and "rats" in mgr:
		# Podnoszenie przedmiotów jest możliwe TYLKO gdy szczury podążają za kursorem
		# (nie atakują i nie niosą barda / obiektu)
		var combat_active: bool = mgr.get("combat_rmb_down") == true
		var carrying_bard: bool = mgr.get("grabbed_object") != null
		if combat_active or carrying_bard:
			return

		for rat in mgr.rats:
			if not is_instance_valid(rat):
				continue
			# Dodatkowa blokada: szczury w trybie carrier (niosą obiekt)
			if rat.get("is_carrier") == true:
				continue
			var d_sq = global_position.distance_squared_to(rat.global_position)
			if d_sq < pickup_radius * pickup_radius:
				# Pickup!
				if mgr.has_method("apply_cheese_buff"):
					mgr.apply_cheese_buff(type)
				queue_free()
				break
