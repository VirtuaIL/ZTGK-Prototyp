@tool
extends CharacterBody3D
class_name door

const DUNGEON_KEY_SCENE := preload("res://scenes/objects/dungeon_key.tscn")

# The ID used by buttons to target this door
@export var doorId: int = -1

# Optional level gate controlled by Main.
# When set, the door stays closed until the assigned level is cleared.
@export var controlled_level_id: int = 0

# Optional level transition triggered when the player enters this door.
@export var target_level_id: int = 0
@export var target_spawn_path: NodePath
@export var transition_requires_open: bool = false
@export var required_dungeon_keys: int = 0

# How far (in local X units) the door slides when opened
@export var slide_distance: float = 9.0

# Duration of the slide animation in seconds
@export var slide_duration: float = 1.8

# If true, the door starts open and closes when triggered
@export var is_inverse: bool = false

# If true, the door is visually open as soon as the scene loads.
@export var start_open: bool = false

# If true, the door stays open until the player enters the level
# matched by controlled_level_id.
@export var open_until_level_enter: bool = false

@export var debug_show_direction: bool = false:
	set(value):
		_debug_show_direction = value
		_update_debug_direction()
	get:
		return _debug_show_direction

@export var debug_length_override: float = 0.0:
	set(value):
		_debug_length_override = value
		_update_debug_direction()
	get:
		return _debug_length_override

var _closed_position: Vector3
var _open_position: Vector3
var _is_open: bool = false
var _transition_locked: bool = false
var _dungeon_key_sequence_running: bool = false
var _debug_mesh: MeshInstance3D
var _debug_show_direction: bool = false
var _debug_length_override: float = 0.0


func _ready() -> void:
	add_to_group("doors")
	_closed_position = position
	# Use local basis to keep slide direction consistent with parent rotation.
	_open_position = position + transform.basis.x * slide_distance
	
	if start_open:
		position = _open_position
		_is_open = true
	elif is_inverse:
		position = _open_position
		_is_open = true
	else:
		_is_open = false

	var transition_area := get_node_or_null("TransitionArea") as Area3D
	if transition_area != null and not transition_area.body_entered.is_connected(_on_transition_body_entered):
		transition_area.body_entered.connect(_on_transition_body_entered)
	
	_update_debug_direction()


func _enter_tree() -> void:
	_update_debug_direction()


func open() -> void:
	if is_inverse:
		if not _is_open: return
		_is_open = false
		_animate_to(_closed_position)
	else:
		if _is_open: return
		_is_open = true
		_animate_to(_open_position)


func close() -> void:
	if is_inverse:
		if _is_open: return
		_is_open = true
		_animate_to(_open_position)
	else:
		if not _is_open: return
		_is_open = false
		_animate_to(_closed_position)


## Called by Capstan every frame to smoothly position the door between
## closed (0.0) and open (1.0).  Bypasses the tween animation.
func set_open_progress(progress: float) -> void:
	progress = clampf(progress, 0.0, 1.0)
	if is_inverse:
		# inverse door: fully open at progress 0, closes as progress grows
		position = _open_position.lerp(_closed_position, progress)
	else:
		position = _closed_position.lerp(_open_position, progress)


func _animate_to(target_pos: Vector3) -> void:
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", target_pos, slide_duration)


func _on_transition_body_entered(body: Node3D) -> void:
	if _transition_locked or target_level_id <= 0:
		return
	if not body.is_in_group("player"):
		return
	if required_dungeon_keys > 0 and not _is_open:
		await _try_unlock_with_keys(body)
		return
	if transition_requires_open and not _is_open:
		return

	await _enter_target_level()


func _try_unlock_with_keys(body: Node3D) -> void:
	if _dungeon_key_sequence_running or _is_open:
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	if not current_scene.has_method("has_dungeon_keys") or not current_scene.has_method("consume_dungeon_keys"):
		return
	if not current_scene.has_dungeon_keys(required_dungeon_keys):
		return

	_dungeon_key_sequence_running = true
	_transition_locked = true
	if not current_scene.consume_dungeon_keys(required_dungeon_keys):
		_dungeon_key_sequence_running = false
		_transition_locked = false
		return

	var inserted_keys := _spawn_inserted_key_visuals(required_dungeon_keys)
	_play_key_insert_animation(inserted_keys)
	await get_tree().create_timer(0.85).timeout
	set_meta("_dungeon_key_unlocked", true)
	open()
	_dungeon_key_sequence_running = false
	_transition_locked = false
	if body != null and is_instance_valid(body) and body.is_in_group("player"):
		await _enter_target_level()


func _enter_target_level() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	if current_scene.has_method("set_current_level"):
		_transition_locked = true
		current_scene.set_current_level(target_level_id)
		await get_tree().create_timer(0.35).timeout
		_transition_locked = false
		return
	if not current_scene.has_method("transition_to_level"):
		return

	var target_position := _get_target_position()
	_transition_locked = true
	current_scene.transition_to_level(target_level_id, target_position)
	await get_tree().create_timer(0.35).timeout
	_transition_locked = false


func _spawn_inserted_key_visuals(count: int) -> Array[Node3D]:
	var spawned: Array[Node3D] = []
	if count <= 0 or DUNGEON_KEY_SCENE == null:
		return spawned

	for i in range(count):
		var key: Node = DUNGEON_KEY_SCENE.instantiate()
		if key == null:
			continue
		var key_node: Node3D = key as Node3D
		if key_node == null:
			continue
		add_child(key_node)
		key_node.set_process(false)
		key_node.set_physics_process(false)
		if key_node is Area3D:
			var key_area := key_node as Area3D
			key_area.monitoring = false
			key_area.monitorable = false
			key_area.collision_layer = 0
			key_area.collision_mask = 0
		key_node.position = Vector3(-1.0 + float(i) * 1.0, 1.4, 0.45)
		spawned.append(key_node)
	return spawned


func _play_key_insert_animation(keys: Array[Node3D]) -> void:
	if keys.is_empty():
		return

	var slots := [
		Vector3(-0.95, 1.4, 0.0),
		Vector3(0.0, 1.4, 0.0),
		Vector3(0.95, 1.4, 0.0),
	]
	for i in range(min(keys.size(), slots.size())):
		var key: Node3D = keys[i]
		if key == null or not is_instance_valid(key):
			continue
		var tween := create_tween()
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(key, "position", slots[i], 0.75).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(key, "rotation", Vector3(0.0, PI * 2.0, 0.0), 0.75)


func _get_target_position() -> Vector3:
	if not target_spawn_path.is_empty():
		var marker := get_node_or_null(target_spawn_path) as Node3D
		if marker != null:
			return marker.global_position
	return global_position + Vector3.UP * 0.5


func _update_debug_direction() -> void:
	if not Engine.is_editor_hint():
		if is_instance_valid(_debug_mesh):
			_debug_mesh.queue_free()
			_debug_mesh = null
		return

	if not debug_show_direction:
		if is_instance_valid(_debug_mesh):
			_debug_mesh.queue_free()
			_debug_mesh = null
		return

	if not is_instance_valid(_debug_mesh):
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "DebugDirection_%s" % get_instance_id()
		_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_debug_mesh.visibility_range_end = 80.0
		add_child(_debug_mesh)
		if Engine.is_editor_hint():
			var owner_node := get_owner()
			if owner_node == null:
				var tree := get_tree()
				if tree != null:
					owner_node = tree.edited_scene_root
			if owner_node != null:
				_debug_mesh.owner = owner_node

	var mesh := BoxMesh.new()
	var length := maxf(debug_length_override, maxf(slide_distance, 0.5))
	mesh.size = Vector3(length, 0.08, 0.08)
	_debug_mesh.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 1.0, 0.6, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.0, 1.0, 0.6, 1.0)
	_debug_mesh.material_override = mat

	# Offset so the bar points from the door origin toward +X.
	_debug_mesh.transform.origin = Vector3(length * 0.5, 0.0, 0.0)
