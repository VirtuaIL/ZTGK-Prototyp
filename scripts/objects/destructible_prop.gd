extends StaticBody3D
class_name DestructibleProp

signal destroyed

@export var level_id: int = 0
@export var max_hp: float = 8.0
@export var intact_model_path: NodePath = NodePath("SM_PROP_planks_dungeon_05")
@export var broken_model_path: NodePath = NodePath("BrokenModel")

var _hp: float = 0.0
var _destroyed: bool = false


func _ready() -> void:
	add_to_group("destructible_props")
	collision_layer = 8 # Walls
	collision_mask = 0
	if level_id > 0:
		set_meta("level_id", level_id)
	_hp = max_hp
	_set_destroyed_visuals(false)


func take_damage(amount: float, _source_id: int = -1, _hit_pos: Vector3 = Vector3.ZERO, _text_color: Color = Color.WHITE) -> void:
	if _destroyed:
		return

	_hp = maxf(0.0, _hp - maxf(0.0, amount))
	if _hp <= 0.0:
		_destroy()


func is_destroyed() -> bool:
	return _destroyed


func _destroy() -> void:
	if _destroyed:
		return

	_destroyed = true
	collision_layer = 0
	collision_mask = 0
	_set_destroyed_visuals(true)
	destroyed.emit()


func _set_destroyed_visuals(destroyed_state: bool) -> void:
	var intact := get_node_or_null(intact_model_path) as Node3D
	if intact != null:
		intact.visible = not destroyed_state

	var broken := get_node_or_null(broken_model_path) as Node3D
	if broken != null:
		broken.visible = destroyed_state
