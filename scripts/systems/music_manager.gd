extends Node
# MusicManager.gd
# Manages musical note texture and effect for the bard

var _note_texture: Texture2D = null

func _ready() -> void:
	add_to_group("music_manager")

func get_note_texture() -> Texture2D:
	if _note_texture == null:
		_note_texture = _generate_note_texture()
	return _note_texture

func _generate_note_texture() -> Texture2D:
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var white = Color(1, 1, 1, 1)
	var transparent = Color(0, 0, 0, 0)
	img.fill(transparent)
	
	# Simple musical note (eighth note) drawing
	# Note head
	for y in range(45, 58):
		for x in range(15, 30):
			var dist = Vector2(x, y).distance_to(Vector2(22, 51))
			if dist < 7:
				img.set_pixel(x, y, white)
				
	# Note stem
	for y in range(15, 51):
		for x in range(27, 31):
			img.set_pixel(x, y, white)
			
	# Note flag
	for y in range(15, 30):
		for x in range(31, 45):
			if x - 31 < (y - 15) * 1.5 and x - 31 < 10:
				img.set_pixel(x, y, white)
				
	return ImageTexture.create_from_image(img)

func create_notes_particles(color: Color = Color(1, 1, 1), amount: int = 8) -> GPUParticles3D:
	var particles = GPUParticles3D.new()
	
	# Particle process material
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.5, 0.2, 0.5)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.gravity = Vector3(0, 0, 0)
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.0
	mat.damping_min = 0.5
	mat.damping_max = 1.0
	mat.scale_min = 0.15
	mat.scale_max = 0.35
	
	# Transparency fade
	var alpha_curve = Curve.new()
	alpha_curve.add_point(Vector2(0, 0))
	alpha_curve.add_point(Vector2(0.2, 1.0))
	alpha_curve.add_point(Vector2(0.7, 1.0))
	alpha_curve.add_point(Vector2(1.0, 0))
	
	var alpha_tex = CurveTexture.new()
	alpha_tex.curve = alpha_curve
	mat.alpha_curve = alpha_tex
	
	# FIXED COLOR for this emitter
	mat.color = color
	
	particles.process_material = mat
	
	# Geometry
	var quad = QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var spatial_mat = StandardMaterial3D.new()
	spatial_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spatial_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spatial_mat.vertex_color_use_as_albedo = true 
	spatial_mat.albedo_texture = get_note_texture()
	spatial_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = spatial_mat
	
	particles.draw_pass_1 = quad
	particles.amount = amount
	particles.lifetime = 1.5
	particles.explosiveness = 0.0
	particles.randomness = 0.8
	particles.visibility_aabb = AABB(Vector3(-1,-1,-1), Vector3(2,4,2))
	
	return particles
