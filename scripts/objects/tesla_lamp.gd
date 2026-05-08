extends Node3D

@export var radius: float = 6.0
@export var damage: float = 15.0
@export var max_targets: int = 3
@export var attack_cooldown: float = 1.0

var _cooldown_timer: float = 0.0
var _active: bool = false
var _mm_instance: MultiMeshInstance3D
var _arcs: Array = []  # persistent arcs to electric rats
var _attack_arcs: Array = []  # arcs to enemies, shown during cooldown
var _attack_arc_timer: float = 0.0

var _rat_mgr: Node = null

func _ready() -> void:
	_mm_instance = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 0

	# Use CylinderMesh exactly like rat_manager does for electric arcs
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.08
	cylinder.height = 1.0
	cylinder.radial_segments = 6

	# Apply shader directly to the mesh material (not material_override)
	var arc_mat = ShaderMaterial.new()
	arc_mat.shader = load("res://scripts/rat/electric_arc.gdshader")
	if arc_mat.shader == null:
		push_error("TeslaLamp: Could not load electric_arc.gdshader")
		var fallback = StandardMaterial3D.new()
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fallback.albedo_color = Color(0.2, 0.5, 1.0, 0.8)
		cylinder.material = fallback
	else:
		cylinder.material = arc_mat

	mm.mesh = cylinder
	_mm_instance.multimesh = mm
	# MUST be top_level because we use global positions for arc transforms.
	# RatManager gets away without this because it sits at (0,0,0).
	# TeslaLamp is placed at an arbitrary position, so without top_level
	# the global coords would be offset by the lamp's position.
	_mm_instance.top_level = true
	add_child(_mm_instance)


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if _attack_arc_timer > 0.0:
		_attack_arc_timer -= delta
		if _attack_arc_timer <= 0.0:
			_attack_arcs.clear()

	_check_rats_and_attack()
	_update_arcs()


func _get_rat_manager() -> Node:
	if _rat_mgr == null or not is_instance_valid(_rat_mgr):
		_rat_mgr = get_tree().get_first_node_in_group("rat_manager")
	return _rat_mgr


func _check_rats_and_attack() -> void:
	_arcs.clear()
	_active = false

	var mgr = _get_rat_manager()
	if mgr == null or not "rats" in mgr:
		return

	# Find electric rats in range (direct distance check — rats have collision_layer=0)
	var my_pos = global_position + Vector3(0, 1.5, 0)
	var rad_sq = radius * radius
	var electric_rats_in_range: Array = []

	for rat in mgr.rats:
		if not is_instance_valid(rat) or rat.get("is_fallen"):
			continue
		if rat.get("default_rat_type") != 3:  # 3 = ELECTRIC
			continue
		var dist_sq = global_position.distance_squared_to(rat.global_position)
		if dist_sq <= rad_sq:
			electric_rats_in_range.append(rat)

	if electric_rats_in_range.is_empty():
		return

	_active = true

	# Draw arcs from lamp to each electric rat in range
	for rat in electric_rats_in_range:
		_arcs.append([my_pos, rat.global_position + Vector3(0, 0.2, 0)])

	# Attack enemies on cooldown
	if _cooldown_timer > 0.0:
		return

	var enemies = []
	var current_scene = get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_nodes_in_current_level"):
		enemies.append_array(current_scene.get_nodes_in_current_level("enemies"))
		enemies.append_array(current_scene.get_nodes_in_current_level("bosses"))
	else:
		enemies = get_tree().get_nodes_in_group("enemies")
		enemies += get_tree().get_nodes_in_group("bosses")

	var targets_hit = 0
	_attack_arcs.clear()
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.get("_is_dead"):
			continue
		if my_pos.distance_squared_to(enemy.global_position) <= rad_sq:
			enemy.take_damage(damage, get_instance_id(), enemy.global_position, Color(0.1, 0.3, 0.9))
			_attack_arcs.append([my_pos, enemy.global_position + Vector3(0, 0.5, 0)])
			targets_hit += 1
			if targets_hit >= max_targets:
				break

	if targets_hit > 0:
		_cooldown_timer = attack_cooldown
		_attack_arc_timer = attack_cooldown * 0.8


func _update_arcs() -> void:
	var all_arcs = _arcs.duplicate()
	all_arcs.append_array(_attack_arcs)

	var mm = _mm_instance.multimesh
	mm.instance_count = all_arcs.size()
	for i in range(all_arcs.size()):
		var p1 = all_arcs[i][0]
		var p2 = all_arcs[i][1]
		var center = (p1 + p2) * 0.5
		var dir = (p2 - p1)
		var dist = dir.length()
		if dist > 0.001:
			dir = dir / dist

		var basis = Basis()
		if abs(dir.y) < 0.999:
			basis.y = dir
			basis.x = Vector3.UP.cross(dir).normalized()
			basis.z = basis.x.cross(basis.y).normalized()
		else:
			basis.y = dir
			basis.x = Vector3.RIGHT.cross(dir).normalized()
			basis.z = basis.x.cross(basis.y).normalized()

		basis.y *= dist
		var t = Transform3D(basis, center)
		mm.set_instance_transform(i, t)
