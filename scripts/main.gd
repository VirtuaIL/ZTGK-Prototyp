extends Node3D

const RAT_COUNT := 60

var rat_scene: PackedScene = preload("res://scenes/rat.tscn")
enum GameMode { COMBAT, BUILD }
var current_mode: GameMode = GameMode.COMBAT

@onready var player: CharacterBody3D = $Player
@onready var rat_manager: Node3D = $RatManager
@onready var stratagem_system: Node = $StratagemSystem
@onready var stratagem_hud: CanvasLayer = $StratagemHUD
@onready var ability_hud: CanvasLayer = $AbilityTimerHUD
@onready var mode_hud: CanvasLayer = $ModeHUD


var camera_offset: Vector3 = Vector3(10, 12, 10)


func _ready() -> void:
	player.add_to_group("player")
	_setup_input_map()
	_init_game()
	_update_mode_state()
	
	# Capture initial camera offset if possible
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		camera_offset = cam.position - player.position


func _init_game() -> void:
	# Setup Rats
	for i in range(RAT_COUNT):
		var rat := rat_scene.instantiate()
		var angle := (TAU / RAT_COUNT) * i
		rat.position = player.position + Vector3(
			cos(angle) * 2.0,
			0,
			sin(angle) * 2.0
		)
		rat.player = player
		add_child(rat)
		rat_manager.register_rat(rat)
	
	# Connect stratagem signals
	stratagem_system.stratagem_menu_toggled.connect(_on_stratagem_menu_toggled)
	stratagem_system.stratagem_input_received.connect(_on_stratagem_input)
	stratagem_system.stratagem_completed.connect(_on_stratagem_completed)
	stratagem_system.stratagem_failed.connect(_on_stratagem_failed)
	
	# Connect rat manager signals
	rat_manager.rat_count_changed.connect(_on_rat_count_changed)
	
	# Setup Ability HUD
	ability_hud.rat_manager = rat_manager


func _setup_input_map() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)
	_add_action("toggle_mode", KEY_TAB)
	_add_action("jump", KEY_SPACE)
	_add_action("rotate_left", KEY_Q)
	_add_action("rotate_right", KEY_E)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mode"):
		if current_mode == GameMode.COMBAT:
			current_mode = GameMode.BUILD
		else:
			current_mode = GameMode.COMBAT
		_update_mode_state()


func _update_mode_state() -> void:
	var is_build := (current_mode == GameMode.BUILD)
	
	# Update systems
	stratagem_system.set_enabled(!is_build)
	rat_manager.set_build_mode(is_build)
	
	# Visual/UI feedback could go here
	if is_build:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		stratagem_hud.hide_menu()
		mode_hud.get_node("%Label").text = "MODE: BUILD"
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mode_hud.get_node("%Label").text = "MODE: COMBAT"


func _add_action(action_name: String, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.keycode = key
		InputMap.action_add_event(action_name, event)


func _on_stratagem_menu_toggled(active: bool) -> void:
	player.set_stratagem_mode(active)
	if active:
		stratagem_hud.show_menu(stratagem_system.get_stratagems())
	else:
		stratagem_hud.hide_menu()


func _on_stratagem_input(input_index: int, matching_strat_indices: Array) -> void:
	stratagem_hud.highlight_direction(input_index, matching_strat_indices)


func _on_stratagem_completed(stratagem_id: String) -> void:
	stratagem_hud.flash_success()
	rat_manager.on_stratagem_activated(stratagem_id)


func _on_stratagem_failed() -> void:
	stratagem_hud.flash_fail()


func _on_rat_count_changed(active: int, total: int) -> void:
	mode_hud.get_node("%RatLabel").text = "Rats: %d/%d" % [active, total]


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		var target_pos := player.position + camera_offset
		cam.position = cam.position.lerp(target_pos, 1.0 - exp(-10.0 * delta))
