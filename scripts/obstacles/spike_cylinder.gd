extends StaticBody3D
class_name SpikeCylinder

@export var radius: float = 1.2
@export var height: float = 2.0
@export var player_damage: float = 20.0
@export var player_damage_interval: float = 0.5
@export var enemy_damage: float = 50.0

const UNIT_CYLINDER_RADIUS: float = 1.0
const UNIT_CYLINDER_HEIGHT: float = 1.0
const SPIKE_VISUAL_MULTIPLIER: float = 1.0
const RAT_TOUCH_RADIUS: float = 0.22
const RAT_TOUCH_HEIGHT: float = 0.08
const SPIKE_ARC_SPACING: float = 0.8
const SPIKE_ROW_SPACING: float = 0.6
const SPIKE_VERTICAL_MARGIN: float = 0.25

var _player_dmg_timer: float = 0.0
var _radius_x: float = 1.2
var _radius_z: float = 1.2
var _effective_height: float = 2.0

@onready var _body_mesh: MeshInstance3D = $MeshInstance3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_bake_scale_into_dimensions()
	_rebuild_body_visual()
	_rebuild_collision_shapes()
	_create_spikes_visuals()

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
						
						# If they are pushed faster than their regular walk speed
						if flat_speed > walk_speed + 0.2:
							enemy.take_damage(enemy_damage)
							enemy.set_meta("spike_cooldown", 0.5)

func _bake_scale_into_dimensions() -> void:
	var baked_scale := Vector3(absf(scale.x), absf(scale.y), absf(scale.z))
	_radius_x = maxf(0.05, radius * baked_scale.x)
	_radius_z = maxf(0.05, radius * baked_scale.z)
	_effective_height = maxf(0.1, height * baked_scale.y)
	scale = Vector3.ONE


func _rebuild_body_visual() -> void:
	var body := CylinderMesh.new()
	body.top_radius = UNIT_CYLINDER_RADIUS
	body.bottom_radius = UNIT_CYLINDER_RADIUS
	body.height = UNIT_CYLINDER_HEIGHT
	if _body_mesh.mesh is PrimitiveMesh:
		body.material = (_body_mesh.mesh as PrimitiveMesh).material
	_body_mesh.mesh = body
	_body_mesh.transform = Transform3D(
		Basis.from_scale(Vector3(_radius_x, _effective_height, _radius_z)),
		Vector3(0.0, _effective_height * 0.5, 0.0)
	)


func _rebuild_collision_shapes() -> void:
	_collision_shape.shape = null
	for child in get_children():
		if child is CollisionShape3D and child != _collision_shape:
			child.queue_free()

	var minor_radius := minf(_radius_x, _radius_z)
	var major_radius := maxf(_radius_x, _radius_z)
	var major_is_x := _radius_x >= _radius_z
	var half_span := maxf(0.0, major_radius - minor_radius)
	var segments := 1
	if half_span > 0.01:
		segments = clampi(int(ceil((half_span * 2.0) / maxf(minor_radius * 1.5, 0.1))) + 1, 3, 7)

	for i in range(segments):
		var shape_node := _collision_shape if i == 0 else CollisionShape3D.new()
		if i > 0:
			add_child(shape_node)
			shape_node.owner = owner
		var shape := CylinderShape3D.new()
		shape.radius = minor_radius
		shape.height = _effective_height
		var offset := 0.0 if segments == 1 else lerpf(-half_span, half_span, float(i) / float(segments - 1))
		var origin := Vector3(offset, _effective_height * 0.5, 0.0) if major_is_x else Vector3(0.0, _effective_height * 0.5, offset)
		shape_node.shape = shape
		shape_node.transform = Transform3D(Basis.IDENTITY, origin)


func _is_point_inside_hazard(local_offset: Vector3, radius_padding: float = 0.0, height_padding: float = 0.0) -> bool:
	if local_offset.y <= (-0.5 - height_padding) or local_offset.y >= (_effective_height + height_padding):
		return false
	var padded_radius_x := _radius_x + radius_padding
	var padded_radius_z := _radius_z + radius_padding
	var x_term := (local_offset.x * local_offset.x) / maxf(padded_radius_x * padded_radius_x, 0.001)
	var z_term := (local_offset.z * local_offset.z) / maxf(padded_radius_z * padded_radius_z, 0.001)
	return x_term + z_term <= 1.0


func _create_spikes_visuals() -> void:
	for child in get_children():
		if child is MeshInstance3D and child != _body_mesh:
			child.queue_free()

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.1, 0.1)

	var ellipse_circumference: float = _get_ellipse_circumference(_radius_x, _radius_z)
	var spikes_per_ring: int = maxi(8, int(round(ellipse_circumference / SPIKE_ARC_SPACING)))
	var usable_height: float = maxf(0.1, _effective_height - SPIKE_VERTICAL_MARGIN * 2.0)
	var row_count: int = maxi(1, int(round(usable_height / SPIKE_ROW_SPACING)))

	for j in range(row_count):
		var y_ratio: float = 0.5 if row_count == 1 else float(j) / float(row_count - 1)
		var yy: float = SPIKE_VERTICAL_MARGIN + y_ratio * usable_height
		var row_angle_offset: float = 0.0 if j % 2 == 0 else PI / float(spikes_per_ring)
		for i in range(spikes_per_ring):
			var angle = row_angle_offset + (float(i) / float(spikes_per_ring)) * TAU
			var mesh_inst = MeshInstance3D.new()
			var cone = CylinderMesh.new()
			cone.bottom_radius = 0.1 * SPIKE_VISUAL_MULTIPLIER
			cone.top_radius = 0.0
			cone.height = 0.5 * SPIKE_VISUAL_MULTIPLIER
			mesh_inst.mesh = cone
			mesh_inst.material_override = mat
			
			var dir := Vector3(
				cos(angle) / maxf(_radius_x, 0.001),
				0.0,
				sin(angle) / maxf(_radius_z, 0.001)
			).normalized()
			var ring_pos := Vector3(cos(angle) * _radius_x, yy, sin(angle) * _radius_z)
			mesh_inst.position = ring_pos + dir * (cone.height * 0.25)
			
			add_child(mesh_inst)

			var up = Vector3.UP
			var rot_axis = up.cross(dir)
			if rot_axis.length_squared() > 0.001:
				rot_axis = rot_axis.normalized()
				var rot_angle = acos(up.dot(dir))
				mesh_inst.basis = Basis(rot_axis, rot_angle)


func _get_ellipse_circumference(radius_x: float, radius_z: float) -> float:
	var a := maxf(radius_x, radius_z)
	var b := minf(radius_x, radius_z)
	if a <= 0.0 or b <= 0.0:
		return 0.0
	var h := pow((a - b) / (a + b), 2.0)
	return PI * (a + b) * (1.0 + (3.0 * h) / (10.0 + sqrt(4.0 - 3.0 * h)))
