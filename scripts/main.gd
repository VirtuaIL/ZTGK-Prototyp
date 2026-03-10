extends Node3D

const RAT_COUNT := 12

var rat_scene: PackedScene = preload("res://scenes/rat.tscn")
@onready var player: CharacterBody3D = $Player
@onready var rat_manager: Node3D = $RatManager
@onready var stratagem_system: Node = $StratagemSystem
@onready var stratagem_hud: CanvasLayer = $StratagemHUD
@onready var ability_hud: CanvasLayer = $AbilityTimerHUD


func _ready() -> void:
	_setup_input_map()
	_init_game()


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
	
	# Setup Ability HUD
	ability_hud.rat_manager = rat_manager


func _setup_input_map() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)


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


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		var offset := Vector3(10, 12, 10)
		cam.position = cam.position.lerp(player.position + offset, 0.05)
		cam.look_at(player.position)
