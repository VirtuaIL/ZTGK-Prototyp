extends Node3D

const RAT_COUNT := 60

var rat_scene: PackedScene = preload("res://scenes/rat.tscn")

@onready var player: CharacterBody3D = $Player
@onready var rat_manager: Node3D = $RatManager
@onready var mode_hud: CanvasLayer = $ModeHUD

var camera_offset: Vector3 = Vector3(10, 12, 10)


func _ready() -> void:
	player.add_to_group("player")
	_setup_input_map()
	_init_game()

	var cam := get_viewport().get_camera_3d()
	if cam and player:
		camera_offset = cam.position - player.position


func _init_game() -> void:
	for i in range(RAT_COUNT):
		var rat := rat_scene.instantiate()
		var angle := (TAU / RAT_COUNT) * i
		rat.position = player.position + Vector3(
			cos(angle) * 2.0,
			0.5,
			sin(angle) * 2.0
		)
		rat.player = player
		add_child(rat)
		rat_manager.register_rat(rat)

	rat_manager.build_blob_offsets()
	rat_manager.rat_count_changed.connect(_on_rat_count_changed)


func _setup_input_map() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)
	_add_action("jump", KEY_SPACE)


func _add_action(action_name: String, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.keycode = key
		InputMap.action_add_event(action_name, event)


func _on_rat_count_changed(active: int, total: int) -> void:
	mode_hud.get_node("%RatLabel").text = "Rats: %d/%d" % [active, total]


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		var target_pos := player.position + camera_offset
		cam.position = cam.position.lerp(target_pos, 1.0 - exp(-10.0 * delta))
