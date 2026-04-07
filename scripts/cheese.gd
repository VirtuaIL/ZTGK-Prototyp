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

func _update_visuals() -> void:
	var mesh_inst = $MeshInstance3D
	if not mesh_inst:
		return
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.8
	
	match type:
		Type.RED:
			mat.albedo_color = Color(0.9, 0.1, 0.1) # Aggression
		Type.GREEN:
			mat.albedo_color = Color(0.1, 0.9, 0.1) # Gas
		Type.YELLOW:
			mat.albedo_color = Color(0.9, 0.9, 0.1) # Immortality
		Type.PURPLE:
			mat.albedo_color = Color(0.6, 0.1, 0.9) # Loss of control, no aggro

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
