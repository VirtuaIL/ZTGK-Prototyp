extends Area3D

# Pojedynczy segment śladu gazowego zostawiany przez szczury.
# Pojawia się jako półprzezroczysty dysk i zanika przez `duration` sekund.

@export var duration: float = 2.5
@export var damage_per_tick: float = 10.0   # zmienione z 5 na 10
@export var damage_interval: float = 0.5
@export var cloud_radius: float = 0.35

var _time_alive: float = 0.0
var _tick_timer: float = 0.0

func _ready() -> void:
	var mesh_inst = $MeshInstance3D
	if mesh_inst:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.85, 0.15, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_inst.material_override = mat
		# Spłaszczony dysk poziomy
		mesh_inst.scale = Vector3(cloud_radius * 2.0, 0.04, cloud_radius * 2.0)

func _physics_process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= duration:
		queue_free()
		return

	# Zanikanie alpha w czasie – bez pulsowania, ciągły ślad
	var mesh_inst = $MeshInstance3D
	if mesh_inst and mesh_inst.material_override:
		var mat = mesh_inst.material_override as StandardMaterial3D
		if mat:
			var progress: float = _time_alive / duration
			mat.albedo_color.a = clampf(0.55 * (1.0 - progress), 0.0, 0.55)

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = damage_interval
		_deal_damage()

func _deal_damage() -> void:
	var nodes = get_tree().get_nodes_in_group("enemies")
	for n in nodes:
		if is_instance_valid(n) and n.has_method("take_damage"):
			if global_position.distance_squared_to(n.global_position) < cloud_radius * cloud_radius:
				n.take_damage(damage_per_tick, get_instance_id(), global_position, Color(0.1, 0.9, 0.1))
