extends Node3D

@export var radius: float = 2.0
@export var gas_cloud_radius: float = 2.5  # how far gas points spread from grate center

var _gas_timer: float = 0.0
var _rat_mgr: Node = null

var is_activated_by_network: bool = false
var _network_timeout: float = 0.0


func _ready() -> void:
	add_to_group("sewer_grates")


func _process(delta: float) -> void:
	if _network_timeout > 0.0:
		_network_timeout -= delta
		if _network_timeout <= 0.0:
			is_activated_by_network = false

	var has_local_rat = _check_for_gas_rats()

	if has_local_rat:
		# Activate ALL grates on the map (simulating gas traveling through sewers)
		var grates = get_tree().get_nodes_in_group("sewer_grates")
		for grate in grates:
			if grate.has_method("activate_from_network"):
				grate.activate_from_network()

	if has_local_rat or is_activated_by_network:
		_gas_timer -= delta
		if _gas_timer <= 0.0:
			_gas_timer = 0.12
			_emit_gas_clouds()


func _get_rat_manager() -> Node:
	if _rat_mgr == null or not is_instance_valid(_rat_mgr):
		_rat_mgr = get_tree().get_first_node_in_group("rat_manager")
	return _rat_mgr


func _check_for_gas_rats() -> bool:
	# Direct distance check — rats have collision_layer=0 so Area3D cannot detect them
	var mgr = _get_rat_manager()
	if mgr == null or not "rats" in mgr:
		return false

	var rad_sq = radius * radius
	for rat in mgr.rats:
		if not is_instance_valid(rat) or rat.get("is_fallen"):
			continue
		var rat_type := int(rat.get("default_rat_type"))
		if mgr.has_method("get_effective_rat_type"):
			rat_type = int(mgr.get_effective_rat_type(rat_type))
		if rat_type != 2:  # 2 = GREEN
			continue
		var dist_sq = global_position.distance_squared_to(rat.global_position)
		if dist_sq <= rad_sq:
			return true
	return false


func activate_from_network() -> void:
	is_activated_by_network = true
	_network_timeout = 0.5


func _emit_gas_clouds() -> void:
	var gas_mgr = get_tree().get_first_node_in_group("gas_damage_manager")
	if gas_mgr and gas_mgr.has_method("add_gas_point"):
		# Multiple randomized points to create a large cloud area from grate
		var r = gas_cloud_radius
		var offsets = [
			Vector3(0, 0, 0),
			Vector3(randf_range(-r, r), 0, randf_range(-r, r)),
			Vector3(randf_range(-r, r), 0, randf_range(-r, r)),
			Vector3(randf_range(-r, r), 0, randf_range(-r, r)),
			Vector3(randf_range(-r, r), 0, randf_range(-r, r)),
			Vector3(randf_range(-r, r), 0, randf_range(-r, r)),
		]
		for offset in offsets:
			gas_mgr.add_gas_point(global_position + offset)
