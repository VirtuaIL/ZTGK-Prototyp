extends Node3D

@export var flight_time: float = 1.1
@export var arc_height: float = 5.0
@export var blast_radius: float = 2.2
@export var damage_rats: bool = true

var _start_pos: Vector3
var _target_pos: Vector3
var _t: float = 0.0

func setup(start_pos: Vector3, target_pos: Vector3) -> void:
	_start_pos = start_pos
	_target_pos = target_pos
	global_position = _start_pos

func _ready() -> void:
	if _start_pos == Vector3.ZERO and _target_pos == Vector3.ZERO:
		_start_pos = global_position
		_target_pos = global_position
	for child in find_children("*", "VisualInstance3D"):
		child.layers = 2

func _physics_process(delta: float) -> void:
	_t += delta
	var alpha := clampf(_t / max(0.01, flight_time), 0.0, 1.0)
	var pos := _start_pos.lerp(_target_pos, alpha)
	pos.y += sin(alpha * PI) * arc_height
	global_position = pos
	if alpha >= 1.0:
		_explode()

func _explode() -> void:
	if damage_rats:
		var mgr = get_tree().get_first_node_in_group("rat_manager")
		if mgr and "rats" in mgr:
			for r in mgr.rats:
				if r and r.global_position.distance_to(_target_pos) <= blast_radius:
					if r.has_method("die"):
						r.die()
	queue_free()
