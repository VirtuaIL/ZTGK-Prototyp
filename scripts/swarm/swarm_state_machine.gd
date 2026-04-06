extends Node
class_name SwarmStateMachine

const SwarmMassScript = preload("res://scripts/swarm/swarm_mass.gd")

## Top-level controller for the Bard Walk / Swarm Trans dual-mode system.
## Attach as a child of Main. Call setup() after instantiation.

signal state_changed(new_state: int)

enum State { BARD_WALK, SWARM_TRANS }

var current_state: State = State.BARD_WALK

var _player: CharacterBody3D = null
var _rat_manager: Node3D = null
var _camera: Camera3D = null
var _main: Node3D = null
var _swarm_mass: Node3D = null

# Camera transition
var _camera_size_default: float = 16.0
var _camera_size_trans: float = 11.0
var _camera_size_target: float = 16.0
var _camera_lerp_speed: float = 3.0


func setup(main: Node3D, p_player: CharacterBody3D, p_rat_manager: Node3D, p_camera: Camera3D) -> void:
	_main = main
	_player = p_player
	_rat_manager = p_rat_manager
	_camera = p_camera
	if _camera:
		_camera_size_default = _camera.size
		_camera_size_target = _camera_size_default


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_swarm_trans"):
		_toggle_state()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _camera and _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_camera.size = lerpf(_camera.size, _camera_size_target, 1.0 - exp(-_camera_lerp_speed * delta))


func _toggle_state() -> void:
	if current_state == State.BARD_WALK:
		_enter_swarm_trans()
	else:
		_exit_swarm_trans()


func _enter_swarm_trans() -> void:
	# Require rats to enter trans mode
	if _rat_manager and _rat_manager.has_method("get_active_rat_count"):
		if _rat_manager.get_active_rat_count() <= 0:
			return

	current_state = State.SWARM_TRANS

	# Lock player movement
	if _player:
		_player.is_trans_mode = true

	# Suspend individual rats
	var rat_count := 40
	if _rat_manager:
		rat_count = _rat_manager.get_active_rat_count()
		_rat_manager.is_trans_mode = true
		if _rat_manager.has_method("suspend_all_rats"):
			_rat_manager.suspend_all_rats()

	# Spawn swarm mass
	_swarm_mass = SwarmMassScript.new()
	_swarm_mass.bard = _player
	_swarm_mass.rat_count = maxi(rat_count, 5)
	_main.add_child(_swarm_mass)

	var start := _player.global_position if _player else Vector3.ZERO
	_swarm_mass.initialize(start)

	# Camera zoom in
	_camera_size_target = _camera_size_trans
	state_changed.emit(State.SWARM_TRANS)


func _exit_swarm_trans() -> void:
	current_state = State.BARD_WALK

	# Grab positions from mass before destroying
	var restore_positions: Array[Vector3] = []
	if _swarm_mass:
		restore_positions = _swarm_mass.get_rat_positions()
		_swarm_mass.queue_free()
		_swarm_mass = null

	# Resume individual rats
	if _rat_manager:
		if _rat_manager.has_method("resume_all_rats"):
			_rat_manager.resume_all_rats(restore_positions)
		_rat_manager.is_trans_mode = false

	# Unlock player
	if _player:
		_player.is_trans_mode = false

	# Camera restore
	_camera_size_target = _camera_size_default
	state_changed.emit(State.BARD_WALK)

func get_swarm_mass() -> Node3D:
	return _swarm_mass


func is_in_trans_mode() -> bool:
	return current_state == State.SWARM_TRANS
