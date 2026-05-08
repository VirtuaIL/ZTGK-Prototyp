extends Node3D

@export var radius: float = 4.0
@export var damage: float = 50.0
@export var trigger_radius: float = 1.5

var _is_exploding: bool = false
var _explode_timer: float = 0.0
var _explode_duration: float = 1.0
var _rat_mgr: Node = null

var _explosion_sphere: MeshInstance3D = null


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	if _is_exploding:
		_explode_timer += delta
		if _explode_timer >= _explode_duration:
			_explode()
		return

	_check_for_red_rats()


func _get_rat_manager() -> Node:
	if _rat_mgr == null or not is_instance_valid(_rat_mgr):
		_rat_mgr = get_tree().get_first_node_in_group("rat_manager")
	return _rat_mgr


func _check_for_red_rats() -> void:
	var mgr = _get_rat_manager()
	if mgr == null or not "rats" in mgr:
		return

	var rad_sq = trigger_radius * trigger_radius
	for rat in mgr.rats:
		if not is_instance_valid(rat) or rat.get("is_fallen"):
			continue
		var rat_type := int(rat.get("default_rat_type"))
		if mgr.has_method("get_effective_rat_type"):
			rat_type = int(mgr.get_effective_rat_type(rat_type))
		if rat_type != 1:  # 1 = RED
			continue
		var dist_sq = global_position.distance_squared_to(rat.global_position)
		if dist_sq <= rad_sq:
			_start_ignition()
			return


func _start_ignition() -> void:
	_is_exploding = true
	_explode_timer = 0.0

	# Tween the barrel white
	var tween = create_tween()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0, 0, 1)
	_apply_material_override(self, mat)

	tween.tween_property(mat, "albedo_color", Color.WHITE, _explode_duration)
	tween.parallel().tween_property(mat, "emission", Color.WHITE, _explode_duration)

	var model = get_node_or_null("Model")
	if model:
		tween.parallel().tween_property(model, "scale", Vector3(1.2, 1.2, 1.2), _explode_duration)

	# Create explosion radius preview sphere (grows during ignition)
	_explosion_sphere = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.1
	sphere_mesh.height = 0.2
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16
	_explosion_sphere.mesh = sphere_mesh

	var sphere_mat = StandardMaterial3D.new()
	sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sphere_mat.albedo_color = Color(1.0, 0.3, 0.0, 0.15)
	_explosion_sphere.material_override = sphere_mat

	add_child(_explosion_sphere)
	_explosion_sphere.position = Vector3(0, 0.5, 0)

	# Animate the sphere growing to show explosion radius
	var sphere_tween = create_tween()
	sphere_tween.tween_property(_explosion_sphere, "scale",
		Vector3(radius * 2, radius * 2, radius * 2), _explode_duration).set_ease(Tween.EASE_IN)
	sphere_tween.parallel().tween_property(sphere_mat, "albedo_color",
		Color(1.0, 0.5, 0.0, 0.35), _explode_duration)


func _apply_material_override(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_material_override(child, mat)


func _explode() -> void:
	# Flash explosion effect
	if _explosion_sphere:
		var flash_mat = _explosion_sphere.material_override as StandardMaterial3D
		if flash_mat:
			flash_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.7)

		var flash_tween = create_tween()
		flash_tween.tween_property(flash_mat, "albedo_color",
			Color(1.0, 0.2, 0.0, 0.0), 0.4)
		flash_tween.tween_callback(_finish_explosion)
	else:
		_finish_explosion()

	# Deal damage
	var enemies = []
	var current_scene = get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_nodes_in_current_level"):
		enemies.append_array(current_scene.get_nodes_in_current_level("enemies"))
		enemies.append_array(current_scene.get_nodes_in_current_level("bosses"))
	else:
		enemies = get_tree().get_nodes_in_group("enemies")
		enemies += get_tree().get_nodes_in_group("bosses")

	var rad_sq = radius * radius
	var my_pos = global_position

	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.get("_is_dead"):
			if my_pos.distance_squared_to(enemy.global_position) <= rad_sq:
				if enemy.has_method("take_damage"):
					enemy.take_damage(damage, get_instance_id(), enemy.global_position, Color(1.0, 0.5, 0.0))

	# Hide the barrel model immediately
	var model = get_node_or_null("Model")
	if model:
		model.visible = false
	var light = get_node_or_null("OmniLight3D")
	if light:
		light.visible = false


func _finish_explosion() -> void:
	queue_free()
