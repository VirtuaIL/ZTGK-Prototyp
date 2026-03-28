extends Area3D
class_name FragileBridge

@export var safe_radius_threshold: float = 1.6
@export var time_to_break: float = 2.0
@export var break_color: Color = Color(1.0, 0.2, 0.0)

var _break_timer: float = 0.0
var _bodies_inside: Array[Node3D] = []
var _rat_manager: Node = null
var _meshes: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _orig_colors: Array[Color] = []
var _orig_positions: Array[Vector3] = []
var _is_broken: bool = false
var _player: Node3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	for child in get_children():
		if child is MeshInstance3D:
			_meshes.append(child)
			_orig_positions.append(child.position)
			
			var mat = null
			if child.material_override:
				mat = child.material_override.duplicate()
			elif child.mesh and child.mesh.get_surface_count() > 0:
				var s_mat = child.mesh.surface_get_material(0)
				if s_mat:
					mat = s_mat.duplicate()
			
			if not mat:
				mat = StandardMaterial3D.new()
				mat.albedo_color = Color(0.4, 0.4, 0.4)
				
			child.material_override = mat
			_mats.append(mat)
			_orig_colors.append(mat.albedo_color)
	
	call_deferred("_init_refs")

func _init_refs():
	var managers = get_tree().get_nodes_in_group("rat_manager")
	if managers.size() > 0:
		_rat_manager = managers[0]
		
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		if _player.has_signal("player_died"):
			_player.player_died.connect(_on_player_died)

func _on_player_died():
	_is_broken = false
	_break_timer = 0.0
	_bodies_inside.clear()
	for i in range(_meshes.size()):
		_meshes[i].show()
		_meshes[i].position = _orig_positions[i]
	_update_visuals()

func _on_body_entered(body: Node3D):
	if body is Rat or body.is_in_group("player"):
		if not _bodies_inside.has(body):
			_bodies_inside.append(body)

func _on_body_exited(body: Node3D):
	if _bodies_inside.has(body):
		_bodies_inside.erase(body)

func _process(delta: float) -> void:
	if _is_broken:
		return
		
	var is_stressed = false
	var has_player = false
	var has_rats = false
	
	for i in range(_bodies_inside.size() - 1, -1, -1):
		var b = _bodies_inside[i]
		if not is_instance_valid(b):
			_bodies_inside.remove_at(i)
			continue
		if b.is_in_group("player"):
			has_player = true
		elif b is Rat:
			if not b.is_fallen:
				has_rats = true
			
	if has_player:
		is_stressed = true
	elif has_rats and _rat_manager != null:
		var current_radius = _rat_manager.get("circle_radius")
		if current_radius != null and current_radius < safe_radius_threshold:
			is_stressed = true
			
	if is_stressed:
		_break_timer += delta
		if _meshes.size() > 0:
			var intensity = clamp(_break_timer / time_to_break, 0.0, 1.0)
			for i in range(_meshes.size()):
				_meshes[i].position.y = _orig_positions[i].y + (randf() - 0.5) * 0.15 * intensity
		
		if _break_timer >= time_to_break:
			_break()
	else:
		_break_timer = max(0.0, _break_timer - delta * 0.5)
		for i in range(_meshes.size()):
			_meshes[i].position.y = lerp(_meshes[i].position.y, _orig_positions[i].y, delta * 15.0)
		
	_update_visuals()

func _update_visuals():
	var stress_ratio = clamp(_break_timer / time_to_break, 0.0, 1.0)
	for i in range(_mats.size()):
		var mat = _mats[i]
		var orig = _orig_colors[i]
		mat.albedo_color = orig.lerp(break_color, stress_ratio)
		if mat is StandardMaterial3D:
			if stress_ratio > 0.1:
				mat.emission_enabled = true
				mat.emission = break_color
				mat.emission_energy_multiplier = stress_ratio * 2.0
			else:
				mat.emission_enabled = false

func _break():
	_is_broken = true
	for i in range(_meshes.size()):
		_meshes[i].hide()
		_meshes[i].position = _orig_positions[i]
	
	var killed_player = false
	for b in _bodies_inside:
		if not is_instance_valid(b):
			continue
		if b.is_in_group("player"):
			if b.has_method("die"):
				b.die()
				killed_player = true
	
	if not killed_player:
		for b in _bodies_inside:
			if not is_instance_valid(b):
				continue
			if b is Rat:
				if b.player and b.player.has_method("die"):
					b.player.die()
					break
