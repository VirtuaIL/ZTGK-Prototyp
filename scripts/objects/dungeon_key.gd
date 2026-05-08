extends Area3D
class_name DungeonKeyPickup

@export var source_level_id: int = 0
@export var bob_height: float = 0.12
@export var bob_speed: float = 2.5
@export var spin_speed: float = 1.6

var _time_alive: float = 0.0
var _collected: bool = false

@onready var _visual_root: Node3D = $Visual
@onready var _light: OmniLight3D = $OmniLight3D


func _ready() -> void:
	add_to_group("dungeon_keys")
	body_entered.connect(_on_body_entered)
	_recolor_visuals()
	if _light:
		_light.visible = true


func set_source_level_id(level_id: int) -> void:
	source_level_id = level_id


func _process(delta: float) -> void:
	_time_alive += delta
	if _visual_root:
		_visual_root.position.y = 2.05 + sin(_time_alive * bob_speed) * bob_height
		_visual_root.rotation.y += spin_speed * delta
	if _light:
		_light.light_energy = 1.5 + sin(_time_alive * 3.0) * 0.25


func _on_body_entered(body: Node3D) -> void:
	if _collected:
		return
	if body == null or not body.is_in_group("player"):
		return
	_collected = true
	var main := get_tree().current_scene
	if main != null and main.has_method("collect_dungeon_key"):
		main.call("collect_dungeon_key", source_level_id, self)
	else:
		queue_free()


func _recolor_visuals() -> void:
	if _visual_root == null:
		return
	_recursive_recolor(_visual_root)


func _recursive_recolor(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.84, 0.15)
		mat.metallic = 0.85
		mat.roughness = 0.2
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.92, 0.3)
		mat.emission_energy_multiplier = 2.0
		mi.material_override = mat
	for child in node.get_children():
		_recursive_recolor(child)
