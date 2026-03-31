@tool
extends Node3D
class_name RatSpawn

@export var activation_radius: float = 2.5:
	set(value):
		activation_radius = max(0.1, value)
		_update_radius_visuals()

@export var show_radius_in_game: bool = true:
	set(value):
		show_radius_in_game = value
		_update_radius_visuals()

@export var is_level_start: bool = false:
	set(value):
		is_level_start = value
		_update_groups()

var _radius_mesh: MeshInstance3D = null

func _ready() -> void:
	add_to_group("rat_spawn")
	_cache_nodes()
	_update_groups()
	_update_radius_visuals()

func _cache_nodes() -> void:
	_radius_mesh = get_node_or_null("RadiusMesh") as MeshInstance3D

func _update_groups() -> void:
	if is_level_start:
		add_to_group("rat_spawn_start")
	else:
		remove_from_group("rat_spawn_start")

func _update_radius_visuals() -> void:
	if _radius_mesh == null:
		return
	var mesh := _radius_mesh.mesh
	if mesh is CylinderMesh:
		var cylinder := mesh as CylinderMesh
		cylinder.top_radius = activation_radius
		cylinder.bottom_radius = activation_radius
	_radius_mesh.visible = Engine.is_editor_hint() or show_radius_in_game

func get_activation_radius() -> float:
	return activation_radius
