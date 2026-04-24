extends Node
# GasDamageManager.gd - Wersja stabilna (StandardMaterial3D)

var gas_points: Array = [] # { pos: Vector3, time: float }
var _check_timer: float = 0.0
@export var check_interval: float = 0.1
@export var gas_duration: float = 2.5
@export var cloud_radius: float = 1.0
var cloud_radius_sq: float = 1.0
@export var damage_per_tick: float = 5.0
@export var max_points: int = 1000

var _multimesh_instance: MultiMeshInstance3D

func _ready() -> void:
	add_to_group("gas_damage_manager")
	cloud_radius_sq = cloud_radius * cloud_radius
	_setup_renderer()

func _setup_renderer() -> void:
	_multimesh_instance = MultiMeshInstance3D.new()
	# Ważne: ignorujemy transformację rodzica, żeby pozycje globalne działały idealnie
	_multimesh_instance.top_level = true
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true # Używamy kolorów do przezroczystości per-instancja
	mm.instance_count = max_points
	mm.visible_instance_count = 0
	
	var plane = PlaneMesh.new()
	plane.size = Vector2(cloud_radius * 2.5, cloud_radius * 2.5)
	mm.mesh = plane
	
	_multimesh_instance.multimesh = mm
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_instance)
	
	# Używamy StandardMaterial3D - najbardziej kompatybilny
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Brak cieni, czysty kolor
	mat.vertex_color_use_as_albedo = true # Pozwala kontrolować ALPHA przez MultiMesh
	mat.albedo_color = Color(0.1, 0.9, 0.15) # Bazowy zielony
	mat.albedo_texture = _generate_gas_texture() # Miękka tekstura
	
	_multimesh_instance.material_override = mat

func _generate_gas_texture() -> Texture2D:
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var center = Vector2(32, 32)
			var dist = center.distance_to(Vector2(x, y))
			var alpha = clamp(1.0 - (dist / 32.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, alpha * alpha))
	return ImageTexture.create_from_image(img)

func _physics_process(delta: float) -> void:
	var i = gas_points.size() - 1
	while i >= 0:
		gas_points[i].time -= delta
		if gas_points[i].time <= 0:
			gas_points.remove_at(i)
		i -= 1
	
	_update_multimesh()
	
	_check_timer -= delta
	if _check_timer <= 0:
		_check_timer = check_interval
		_deal_gas_damage()

func _update_multimesh() -> void:
	var mm = _multimesh_instance.multimesh
	var count = min(gas_points.size(), max_points)
	mm.visible_instance_count = count
	
	for i in range(count):
		var pt = gas_points[i]
		# Pozycja minimalnie nad ziemią, żeby uniknąć migotania
		var t = Transform3D(Basis().rotated(Vector3.UP, float(i)), pt.pos + Vector3(0, 0.1, 0))
		mm.set_instance_transform(i, t)
		
		# Przezroczystość na podstawie czasu życia
		var life_percent = pt.time / gas_duration
		var alpha = 0.5 * sin(life_percent * PI)
		mm.set_instance_color(i, Color(1, 1, 1, alpha))

func add_gas_point(pos: Vector3) -> void:
	if gas_points.size() >= max_points:
		gas_points.remove_at(0)
	if gas_points.size() > 0:
		if pos.distance_squared_to(gas_points[-1].pos) < 0.15:
			return
	gas_points.append({"pos": pos, "time": gas_duration})

func _deal_gas_damage() -> void:
	if gas_points.is_empty(): return
	var enemies = get_tree().get_nodes_in_group("enemies")
	enemies += get_tree().get_nodes_in_group("bosses")
	for enemy in enemies:
		if not is_instance_valid(enemy): continue
		var enemy_pos = enemy.global_position
		for pt in gas_points:
			if enemy_pos.distance_squared_to(pt.pos) < cloud_radius_sq:
				if enemy.has_method("take_damage"):
					enemy.take_damage(damage_per_tick, 0, pt.pos, Color(0.1, 0.9, 0.1))
				break
