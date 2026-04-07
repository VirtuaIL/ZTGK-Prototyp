extends Area3D

@export var duration: float = 2.0
@export var damage_per_tick: float = 5.0
@export var damage_interval: float = 0.5
@export var cloud_radius: float = 0.4

var _time_alive: float = 0.0
var _tick_timer: float = 0.0

func _ready() -> void:
	# Make sure it only interacts with enemies
	# If enemies are on a certain mask, we can set that, but we'll also just check groups
	pass

func _physics_process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= duration:
		queue_free()
		return
		
	# visual pulse
	var mesh_inst = $MeshInstance3D
	if mesh_inst:
		var scale_val = 1.0 + sin(_time_alive * 5.0) * 0.1
		mesh_inst.scale = Vector3(scale_val, scale_val, scale_val)
		# fade out
		if mesh_inst.material_override:
			var mat = mesh_inst.material_override
			mat.albedo_color.a = clampf(1.0 - (_time_alive / duration), 0.0, 0.6)

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
