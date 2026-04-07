extends Node3D

var lifetime: float = 0.6
var timer: float = 0.0

var parts: Array[MeshInstance3D] = []
var vels: Array[Vector3] = []
var shockwave: MeshInstance3D
var smat: StandardMaterial3D

func _ready() -> void:
	var box = BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.1)
	
	var pmat = StandardMaterial3D.new()
	pmat.albedo_color = Color(0.8, 0.1, 0.1)
	pmat.emission_enabled = true
	pmat.emission = Color(0.8, 0.1, 0.1)
	box.material = pmat
	
	for i in range(8):
		var p = MeshInstance3D.new()
		p.mesh = box
		add_child(p)
		parts.append(p)
		
		var angle = randf() * TAU
		var up_angle = randf_range(0.2, 1.2)
		var speed = randf_range(2.0, 5.0)
		
		var dir = Vector3(cos(angle)*cos(up_angle), sin(up_angle), sin(angle)*cos(up_angle))
		vels.append(dir * speed)

	var sphere = SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	
	smat = StandardMaterial3D.new()
	smat.albedo_color = Color(1.0, 0.4, 0.1, 0.6)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.4, 0.1)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = smat
	
	shockwave = MeshInstance3D.new()
	shockwave.mesh = sphere
	add_child(shockwave)

func _process(delta: float) -> void:
	timer += delta
	if timer >= lifetime:
		queue_free()
		return
		
	var progress = timer / lifetime
	
	if shockwave:
		var s = 1.0 + progress * 2.5
		shockwave.scale = Vector3(s, s, s)
		smat.albedo_color.a = 0.6 * (1.0 - progress)
			
	for i in range(parts.size()):
		var p = parts[i]
		var v = vels[i]
		
		v.y -= 25.0 * delta
		vels[i] = v
		
		p.position += v * delta
		p.rotate_x(delta * 12.0)
		p.rotate_y(delta * 15.0)
		
		var ps = 1.0 - progress
		p.scale = Vector3(ps, ps, ps)
