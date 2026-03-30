@tool
extends Area3D
class_name HeatGrate

@export var is_active: bool = false:
	set(val):
		is_active = val
		_update_visuals()

var _mesh: MeshInstance3D
var _mat_hot: StandardMaterial3D
var _mat_cold: StandardMaterial3D

func _ready() -> void:
	_mesh = get_node_or_null("MeshInstance3D")
	
	_mat_hot = StandardMaterial3D.new()
	_mat_hot.albedo_color = Color.RED
	_mat_hot.emission_enabled = true
	_mat_hot.emission = Color(1.0, 0.1, 0.0)
	_mat_hot.emission_energy_multiplier = 2.0
	
	_mat_cold = StandardMaterial3D.new()
	_mat_cold.albedo_color = Color(0.1, 0.1, 0.1)
	
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
	_update_visuals()

func _update_visuals() -> void:
	if _mesh == null:
		return
	if is_active:
		_mesh.material_override = _mat_hot
	else:
		_mesh.material_override = _mat_cold

func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
	
	if body.has_method("die"):
		body.die()
	elif body is Rat:
		if body.player and body.player.has_method("die"):
			body.player.die()
