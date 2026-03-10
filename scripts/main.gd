extends Node3D

const RAT_COUNT := 50

enum RatMode { COMBAT, BUILD }
var current_mode: RatMode = RatMode.COMBAT

var combat_mode_rect: ColorRect
var build_mode_rect: ColorRect

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
	_setup_mode_ui()
	
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
	_add_action("toggle_mode", KEY_F)


func _setup_mode_ui() -> void:
	var mode_hud = CanvasLayer.new()
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# anchoring bottom right, adjust position upwards/leftwards
	hbox.position = Vector2(-150, -80) 
	
	combat_mode_rect = ColorRect.new()
	combat_mode_rect.custom_minimum_size = Vector2(50, 50)
	
	build_mode_rect = ColorRect.new()
	build_mode_rect.custom_minimum_size = Vector2(50, 50)
	
	# spacing
	hbox.add_theme_constant_override("separation", 20)
	hbox.add_child(combat_mode_rect)
	hbox.add_child(build_mode_rect)
	
	mode_hud.add_child(hbox)
	add_child(mode_hud)
	
	_update_mode_ui()


func _update_mode_ui() -> void:
	if current_mode == RatMode.COMBAT:
		combat_mode_rect.color = Color.WHITE
		build_mode_rect.color = Color.hex(0x666666ff) # gray
	else:
		combat_mode_rect.color = Color.hex(0x666666ff) # gray
		build_mode_rect.color = Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mode"):
		if current_mode == RatMode.COMBAT:
			current_mode = RatMode.BUILD
		else:
			current_mode = RatMode.COMBAT
		stratagem_system.mode = current_mode
		rat_manager.mode = current_mode
		_update_mode_ui()


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
