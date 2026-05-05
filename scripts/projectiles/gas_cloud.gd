extends Node3D

# Pojedynczy segment śladu gazowego zostawiany przez szczury.
# Pojawia się jako półprzezroczysty dysk i zanika przez `duration` sekund.

@export var duration: float = 2.5
@export var damage_per_tick: float = 10.0   # zmienione z 5 na 10
@export var damage_interval: float = 0.5
@export var cloud_radius: float = 1.2

var _time_alive: float = 0.0
var _tick_timer: float = 0.0

# Shared material for batching
static var _shared_mat: StandardMaterial3D = null

func _ready() -> void:
	var mesh_inst = $MeshInstance3D
	if mesh_inst:
		if _shared_mat == null:
			_shared_mat = StandardMaterial3D.new()
			_shared_mat.albedo_color = Color(0.1, 0.85, 0.15, 0.55)
			_shared_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_shared_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_shared_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			# Note: We can't easily animate alpha per instance if we want full batching
			# unless we use vertex colors or a custom shader.
			# But sharing the material resource itself is already a win.
		
		mesh_inst.material_override = _shared_mat
		# Spłaszczony dysk poziomy
		mesh_inst.scale = Vector3(cloud_radius * 2.0, 0.04, cloud_radius * 2.0)

func _physics_process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= duration:
		queue_free()
		return

	# Zanikanie alpha w czasie – note: this currently affects ALL clouds if they share material!
	# To fix this while keeping batching, we should use vertex colors.
	# For now, let's keep it but recognize the limitation, or use unique materials if we must.
	# Actually, if we use material_override on each, it might still break batching if properties differ.
	# Let's use a simpler approach for now: if many clouds are active, don't animate alpha per-frame
	# OR use a shader that uses instance custom data.
	
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
