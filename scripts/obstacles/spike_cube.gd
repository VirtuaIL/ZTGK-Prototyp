extends StaticBody3D
class_name SpikeCube

@export var size: Vector3 = Vector3(2.0, 2.0, 2.0)
@export var player_damage: float = 20.0
@export var player_damage_interval: float = 0.5
@export var enemy_damage: float = 50.0

const SPIKE_VISUAL_MULTIPLIER: float = 1.0
const RAT_TOUCH_RADIUS: float = 0.22
const RAT_TOUCH_HEIGHT: float = 0.08
const SPIKE_ARC_SPACING: float = 0.4
const SPIKE_ROW_SPACING: float = 0.4
const SPIKE_VERTICAL_MARGIN: float = 0.25

var _player_dmg_timer: float = 0.0
var _effective_size: Vector3 = Vector3(2.0, 2.0, 2.0)

var _hazard_center := Vector3.ZERO

func _ready() -> void:
	var mi: MeshInstance3D = null
	for child in get_children():
		if child is MeshInstance3D:
			mi = child
			break

	if mi and mi.mesh:
		var aabb = mi.mesh.get_aabb()
		_effective_size = aabb.size * mi.scale
		_hazard_center = mi.position + aabb.position * mi.scale + _effective_size * 0.5
	else:
		_effective_size = size
		_hazard_center = Vector3.ZERO

	_create_spikes_visuals(_hazard_center)


func _physics_process(_delta: float) -> void:
	var mgr = get_tree().get_first_node_in_group("rat_manager")
	if mgr != null and "rats" in mgr:
		for rat in mgr.rats:
			if is_instance_valid(rat):
				var rat_local := to_local(rat.global_position)
				if _is_point_inside_hazard(rat_local, RAT_TOUCH_RADIUS, RAT_TOUCH_HEIGHT):
					if rat.has_method("die"):
						rat.die()

	for rat in get_tree().get_nodes_in_group("wild_rats"):
		if is_instance_valid(rat):
			var rat_local := to_local(rat.global_position)
			if _is_point_inside_hazard(rat_local, RAT_TOUCH_RADIUS, RAT_TOUCH_HEIGHT):
				if rat.has_method("die"):
					rat.die()

	# Player damage
	_player_dmg_timer = maxf(0.0, _player_dmg_timer - _delta)
	var p = get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		var player_local := to_local(p.global_position)
		if _is_point_inside_hazard(player_local):
			if _player_dmg_timer <= 0.0:
				_player_dmg_timer = player_damage_interval
				if p.has_method("take_damage"):
					p.take_damage(player_damage)

	# Enemy damage
	var enemies: Array = []
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_nodes_in_current_level"):
		enemies.append_array(current_scene.get_nodes_in_current_level("enemies"))
		enemies.append_array(current_scene.get_nodes_in_current_level("bosses"))
	else:
		enemies = get_tree().get_nodes_in_group("enemies")
		enemies += get_tree().get_nodes_in_group("bosses")

	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("take_damage") and (not enemy.has_method("is_dead") or not enemy.is_dead()):
			var t := 0.0
			if enemy.has_meta("spike_cooldown"):
				t = enemy.get_meta("spike_cooldown")
				t = maxf(0.0, t - _delta)
				enemy.set_meta("spike_cooldown", t)

			var enemy_local := to_local(enemy.global_position)
			if _is_point_inside_hazard(enemy_local):
				if t <= 0.0:
					var vel = enemy.get("velocity")
					if vel is Vector3:
						var flat_speed = Vector2(vel.x, vel.z).length()
						var walk_speed = 2.6
						if "chase_speed" in enemy:
							walk_speed = enemy.get("chase_speed")
						
						if flat_speed > walk_speed + 0.2:
							enemy.take_damage(enemy_damage)
							enemy.set_meta("spike_cooldown", 0.5)





func _is_point_inside_hazard(local_offset: Vector3, radius_padding: float = 0.0, height_padding: float = 0.0) -> bool:
	var offset = local_offset - _hazard_center
	
	var visual_offset = Vector3(
		offset.x * absf(scale.x),
		offset.y * absf(scale.y),
		offset.z * absf(scale.z)
	)
	
	var visual_size := Vector3(
		_effective_size.x * absf(scale.x),
		_effective_size.y * absf(scale.y),
		_effective_size.z * absf(scale.z)
	)
	
	var half_y := (visual_size.y * 0.5) + height_padding
	if absf(visual_offset.y) > half_y:
		return false
	var half_x := (visual_size.x * 0.5) + radius_padding
	if absf(visual_offset.x) > half_x:
		return false
	var half_z := (visual_size.z * 0.5) + radius_padding
	if absf(visual_offset.z) > half_z:
		return false
	return true


func _create_spikes_visuals(center_offset: Vector3) -> void:
	for child in get_children():
		if child.name == "SpikesContainer":
			child.queue_free()

	var container = Node3D.new()
	container.name = "SpikesContainer"
	var inv_scale := Vector3(
		1.0 / scale.x if absf(scale.x) > 0.001 else 1.0,
		1.0 / scale.y if absf(scale.y) > 0.001 else 1.0,
		1.0 / scale.z if absf(scale.z) > 0.001 else 1.0
	)
	container.scale = inv_scale
	add_child(container)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.1, 0.1)

	var visual_size := Vector3(
		_effective_size.x * absf(scale.x),
		_effective_size.y * absf(scale.y),
		_effective_size.z * absf(scale.z)
	)
	var visual_center := Vector3(
		center_offset.x * scale.x,
		center_offset.y * scale.y,
		center_offset.z * scale.z
	)

	var usable_height: float = maxf(0.1, visual_size.y - SPIKE_VERTICAL_MARGIN * 2.0)
	var row_count: int = maxi(1, int(round(usable_height / SPIKE_ROW_SPACING)))

	var transforms := []

	for j in range(row_count):
		var y_ratio: float = 0.5 if row_count == 1 else float(j) / float(row_count - 1)
		var yy: float = visual_center.y - (visual_size.y * 0.5) + SPIKE_VERTICAL_MARGIN + y_ratio * usable_height
		
		# Right face (+X)
		_create_spikes_for_face(Vector3(1, 0, 0), Vector3(0, 0, 1), visual_size.z, visual_size.x * 0.5, yy, j, visual_center, transforms)
		# Left face (-X)
		_create_spikes_for_face(Vector3(-1, 0, 0), Vector3(0, 0, -1), visual_size.z, visual_size.x * 0.5, yy, j, visual_center, transforms)
		# Back face (+Z)
		_create_spikes_for_face(Vector3(0, 0, 1), Vector3(-1, 0, 0), visual_size.x, visual_size.z * 0.5, yy, j, visual_center, transforms)
		# Front face (-Z)
		_create_spikes_for_face(Vector3(0, 0, -1), Vector3(1, 0, 0), visual_size.x, visual_size.z * 0.5, yy, j, visual_center, transforms)

	if transforms.size() > 0:
		var multimesh_inst = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = transforms.size()
		
		var cone = CylinderMesh.new()
		cone.bottom_radius = 0.1 * SPIKE_VISUAL_MULTIPLIER
		cone.top_radius = 0.0
		cone.height = 0.5 * SPIKE_VISUAL_MULTIPLIER
		cone.radial_segments = 4
		cone.rings = 1
		cone.material = mat
		mm.mesh = cone
		
		for k in range(transforms.size()):
			mm.set_instance_transform(k, transforms[k])
			
		multimesh_inst.multimesh = mm
		container.add_child(multimesh_inst)


func _create_spikes_for_face(normal: Vector3, tangent: Vector3, width: float, depth: float, yy: float, row_index: int, center_offset: Vector3, transforms: Array) -> void:
	var usable_width := maxf(0.01, width - 0.2)
	var spikes_on_face: int = maxi(1, int(round(usable_width / SPIKE_ARC_SPACING)))
	
	# Alternate number of spikes or position if row_index % 2 == 1
	var is_odd_row = (row_index % 2 == 1)
	var actual_spikes = spikes_on_face
	if is_odd_row and spikes_on_face > 1:
		actual_spikes -= 1
		
	if actual_spikes < 1:
		actual_spikes = 1

	for i in range(actual_spikes):
		var t: float = 0.5 if actual_spikes == 1 else float(i) / float(actual_spikes - 1)
		
		var offset = (t - 0.5) * usable_width
		
		# Working entirely in visual, unscaled container space
		var face_point = center_offset + normal * depth + tangent * offset
		face_point.y = yy
		
		var pos_offset = normal * (0.5 * SPIKE_VISUAL_MULTIPLIER * 0.25)
		var final_pos = face_point + pos_offset
		
		var up = Vector3.UP
		var rot_axis = up.cross(normal)
		var basis = Basis.IDENTITY
		if rot_axis.length_squared() > 0.001:
			rot_axis = rot_axis.normalized()
			var rot_angle = acos(up.dot(normal))
			basis = Basis(rot_axis, rot_angle)
			
		transforms.append(Transform3D(basis, final_pos))
