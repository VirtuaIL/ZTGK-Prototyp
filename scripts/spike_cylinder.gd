extends StaticBody3D
class_name SpikeCylinder

@export var radius: float = 1.2
@export var height: float = 2.0

func _ready() -> void:
	_create_spikes_visuals()

func _physics_process(_delta: float) -> void:
	var mgr = get_tree().get_first_node_in_group("rat_manager")
	if mgr != null and "rats" in mgr:
		var effective_radius = radius * maxf(scale.x, scale.z)
		var effective_height = height * scale.y
		var r_sq = effective_radius * effective_radius
		for rat in mgr.rats:
			if is_instance_valid(rat):
				var diff: Vector3 = rat.global_position - global_position
				var dist_sq: float = diff.x * diff.x + diff.z * diff.z
				if dist_sq <= r_sq:
					if diff.y > -0.5 and diff.y < effective_height:
						if rat.has_method("die"):
							rat.die()

func _create_spikes_visuals() -> void:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.1, 0.1)
	
	for i in range(12):
		for j in range(3):
			var angle = (i / 12.0) * TAU
			var yy = 0.4 + j * 0.6
			var mesh_inst = MeshInstance3D.new()
			var cone = CylinderMesh.new()
			cone.bottom_radius = 0.1
			cone.top_radius = 0.0
			cone.height = 0.5
			mesh_inst.mesh = cone
			mesh_inst.material_override = mat
			
			var dir = Vector3(cos(angle), 0, sin(angle))
			mesh_inst.position = Vector3(0, yy, 0) + dir * 0.8
			
			add_child(mesh_inst)
			
			# Align cone to point outward
			# Default cone points UP (+Y). We want it to point in `dir`
			var up = Vector3.UP
			var rot_axis = up.cross(dir)
			if rot_axis.length_squared() > 0.001:
				rot_axis = rot_axis.normalized()
				var rot_angle = acos(up.dot(dir))
				mesh_inst.basis = Basis(rot_axis, rot_angle)
