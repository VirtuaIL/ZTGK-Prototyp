extends Node3D

enum RatMode { COMBAT, BUILD }
var current_mode: RatMode = RatMode.COMBAT

var combat_mode_rect: ColorRect
var build_mode_rect: ColorRect
var cheatsheet_panel: Panel
var goal_label: Label
var rat_count_label: Label
var recall_indicator: Control
var recall_indicator_layer: CanvasLayer
var _recall_hold_time: float = 0.0
var _recall_triggered: bool = false

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
	_setup_cheatsheet_ui()
	_setup_goal_ui()
	_setup_rat_count_ui()
	_setup_recall_indicator_ui()
	
	rat_manager.setup_player(player)
	rat_manager.ensure_min_cap()
	
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
	_add_action_key("recall_rats", KEY_SPACE)
	_add_action_key("toggle_cheatsheet", KEY_H)
	_add_action_key("toggle_enemy_passive", KEY_F2)


func _setup_mode_ui() -> void:
	var mode_hud = CanvasLayer.new()
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hbox.position = Vector2(-150, -80) 
	
	combat_mode_rect = ColorRect.new()
	combat_mode_rect.custom_minimum_size = Vector2(50, 50)
	
	build_mode_rect = ColorRect.new()
	build_mode_rect.custom_minimum_size = Vector2(50, 50)
	
	hbox.add_theme_constant_override("separation", 20)
	hbox.add_child(combat_mode_rect)
	hbox.add_child(build_mode_rect)
	
	mode_hud.add_child(hbox)
	add_child(mode_hud)
	
	_update_mode_ui()

func _setup_cheatsheet_ui() -> void:
	var layer = CanvasLayer.new()
	var panel = Panel.new()
	cheatsheet_panel = panel
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(380, 340)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.06, 0.85)
	style.border_color = Color(0.6, 0.6, 0.6, 0.6)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "STEROWANIE (H – pokaż/ukryj)"
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(title)

	var body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.text = \
		"WASD – ruch\n" + \
		"CTRL (trzymaj) – tryb budowy, puść – tryb walki\n" + \
		"SPACJA (przytrzymaj 1.5s) – przywołaj wszystkie szczury\n\n" + \
		"MYSZ (Tryb walki)\n" + \
		"LPM (przytrzymaj) – formacja wokół kursora\n" + \
		"PPM (przytrzymaj) – obrót formacji\n\n" + \
		"MYSZ (Tryb budowy)\n" + \
		"LPM – rysuj/wyznaczaj miejsce\n" + \
		"PPM – chwytaj/upuść obiekty\n" + \
		"Scroll – szerokość pędzla / promień koła\n" + \
		"Boczne przyciski myszy – obrót niesionego obiektu\n\n" + \
		"DEBUG\n" + \
		"F2 – przełącz tryb pasywny wrogów"
	body.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(body)

	layer.add_child(panel)
	add_child(layer)

func _setup_goal_ui() -> void:
	var layer = CanvasLayer.new()
	var label = Label.new()
	goal_label = label
	label.text = "Cel prototypu: wydostań się z labiryntu"
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_left = 0
	label.offset_right = 0
	label.offset_top = 12
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	add_child(layer)

func _setup_rat_count_ui() -> void:
	var layer = CanvasLayer.new()
	var label = Label.new()
	rat_count_label = label
	var max_cap := 0
	if rat_manager and rat_manager.has_method("get_max_cap"):
		max_cap = rat_manager.get_max_cap()
	label.text = "Szczury: 0 / " + str(max_cap)
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.offset_left = 20
	label.offset_top = 60
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	add_child(layer)

func _setup_recall_indicator_ui() -> void:
	recall_indicator_layer = CanvasLayer.new()
	var indicator_scene = preload("res://scripts/ui/hold_recall_indicator.gd")
	recall_indicator = indicator_scene.new()
	recall_indicator.visible = false
	recall_indicator_layer.add_child(recall_indicator)
	add_child(recall_indicator_layer)

func _update_rat_count_ui() -> void:
	if not rat_count_label or not rat_manager:
		return
	var current_count := 0
	var max_cap := 0
	if rat_manager.has_method("get_active_rat_count"):
		current_count = rat_manager.get_active_rat_count()
	else:
		current_count = rat_manager.rats.size()
	if rat_manager.has_method("get_max_cap"):
		max_cap = rat_manager.get_max_cap()
	else:
		max_cap = rat_manager.rats.size()
	rat_count_label.text = "Szczury: " + str(current_count) + " / " + str(max_cap)


func _update_mode_ui() -> void:
	if current_mode == RatMode.COMBAT:
		combat_mode_rect.color = Color.WHITE
		build_mode_rect.color = Color.hex(0x666666ff)
	else:
		combat_mode_rect.color = Color.hex(0x666666ff)
		build_mode_rect.color = Color.WHITE


func _process(delta: float) -> void:
	# ── Ctrl-based mode switching ──
	var ctrl_held := Input.is_key_pressed(KEY_CTRL)
	var new_mode: RatMode = RatMode.BUILD if ctrl_held else RatMode.COMBAT
	
	if new_mode != current_mode:
		current_mode = new_mode
		stratagem_system.mode = current_mode
		rat_manager.mode = current_mode
		_update_mode_ui()

	_update_rat_count_ui()
	_update_recall_hold(delta)
	
	# ── Camera follow ──
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		var offset := Vector3(10, 12, 10)
		cam.position = cam.position.lerp(player.position + offset, 0.05)
		cam.look_at(player.position)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_cheatsheet"):
		if cheatsheet_panel:
			cheatsheet_panel.visible = not cheatsheet_panel.visible
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_enemy_passive"):
		_toggle_all_enemies_passive()
		get_viewport().set_input_as_handled()
		return


func _update_recall_hold(delta: float) -> void:
	var holding := Input.is_action_pressed("recall_rats")
	if holding and not _recall_triggered:
		_recall_hold_time = min(_recall_hold_time + delta, 1.5)
		if _recall_hold_time >= 1.5:
			rat_manager.recall_all_rats()
			_recall_triggered = true
	else:
		_recall_hold_time = 0.0
		_recall_triggered = false

	if recall_indicator:
		if holding and not _recall_triggered:
			recall_indicator.visible = true
			recall_indicator.set("progress", _recall_hold_time / 1.5)
			var mp := get_viewport().get_mouse_position()
			var sz := recall_indicator.size
			recall_indicator.position = mp + Vector2(-sz.x * 0.5, -sz.y - 14.0)
		else:
			recall_indicator.visible = false


func _add_action(action_name: String, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.keycode = key
		InputMap.action_add_event(action_name, event)


func _add_action_key(action_name: String, key: Key) -> void:
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


func _toggle_all_enemies_passive() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("toggle_passive"):
			enemy.toggle_passive()
