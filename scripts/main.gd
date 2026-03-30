extends Node3D

var lpm_label_val: Label
var spm_label_val: Label
var ppm_label_val: Label
var lpm_rect_val: ColorRect
var spm_rect_val: ColorRect
var ppm_rect_val: ColorRect
var space_rect_val: ColorRect
var cheatsheet_panel: Panel
var cheatsheet_margin: MarginContainer
var cheatsheet_body: RichTextLabel
var cheatsheet_vbox: VBoxContainer
var cheatsheet_title: Label
var cheatsheet_hint: Label
var goal_label: Label
var rat_count_label: RichTextLabel
var recall_indicator: Control
var recall_indicator_layer: CanvasLayer
var _recall_hold_time: float = 0.0
var _recall_triggered: bool = false
var _scroll_highlight_timer: float = 0.0
var indicator_layer: CanvasLayer
var indicator_root: Control
var indicator_pool: Array[Label] = []
var _indicator_blink_time: float = 0.0

# ── UI Theme ──────────────────────────────────────────────────────────────────
const UI_BG: Color = Color(0.06, 0.06, 0.07, 0.65)
const UI_BG_STRONG: Color = Color(0.09, 0.09, 0.1, 0.75)
const UI_BORDER: Color = Color(0.6, 0.6, 0.6, 0.6)
const UI_TEXT: Color = Color(0.95, 0.95, 0.95)
const UI_MUTED: Color = Color(0.78, 0.78, 0.78)
const UI_HINT: Color = Color(1.0, 0.92, 0.72)
const UI_OUTLINE_DARK: Color = Color(0, 0, 0, 0.75)

# ── Offscreen Indicators ──────────────────────────────────────────────────────
@export var indicator_max_distance: float = 26.0
@export var indicator_min_distance: float = 6.0
@export var indicator_screen_padding: float = 26.0
@export var indicator_color: Color = Color(1.0, 0.65, 0.25, 1.0)
@export var indicator_blink_speed: float = 4.0
@export var indicator_blink_depth: float = 0.35

# ── Camera look-ahead ─────────────────────────────────────────────────────────
@export var cam_look_ahead_max: float = 2.0
@export var cam_look_ahead_deadzone: float = 0.2
@export var cam_look_ahead_smooth: float = 6.0
var _cam_look_ahead: Vector3 = Vector3.ZERO

# ── Camera level centering ────────────────────────────────────────────────────
@export var cam_level_focus_weight: float = 0.4
@export var cam_level_focus_weight_forced: float = 0.55
@export var cam_level_switch_hysteresis: float = 3.0
var _levels: Array[Node3D] = []
var _current_level: Node3D = null
var _forced_level: Node3D = null

@onready var player: CharacterBody3D = $Player
@onready var rat_manager: Node3D = $RatManager
@onready var stratagem_system: Node = get_node_or_null("StratagemSystem")
@onready var stratagem_hud: CanvasLayer = get_node_or_null("StratagemHUD")
@onready var ability_hud: CanvasLayer = $AbilityTimerHUD
@onready var levels_root: Node3D = get_node_or_null("levels")


func _ready() -> void:
	_setup_input_map()
	_init_game()
	get_viewport().size_changed.connect(_refresh_cheatsheet_size)
	_gather_levels()
	call_deferred("_post_init_fixup")

func _post_init_fixup() -> void:
	await get_tree().process_frame
	if rat_manager and rat_manager.has_method("reset_after_level_load"):
		rat_manager.reset_after_level_load()


func _init_game() -> void:
	_setup_mode_ui()
	_setup_cheatsheet_ui()
	_setup_goal_ui()
	_setup_rat_count_ui()
	_setup_recall_indicator_ui()
	_setup_offscreen_indicators_ui()
	
	if rat_manager and player:
		rat_manager.setup_player(player)
		rat_manager.ensure_min_cap()
	else:
		push_warning("RatManager or Player missing in scene; skipping setup_player.")
	
	# Connect stratagem signals (optional)
	if stratagem_system and stratagem_hud:
		stratagem_system.stratagem_menu_toggled.connect(_on_stratagem_menu_toggled)
		stratagem_system.stratagem_input_received.connect(_on_stratagem_input)
		stratagem_system.stratagem_completed.connect(_on_stratagem_completed)
		stratagem_system.stratagem_failed.connect(_on_stratagem_failed)
	
	# Setup Ability HUD
	if ability_hud:
		ability_hud.rat_manager = rat_manager


func _setup_input_map() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)
	_add_action_key("recall_rats", KEY_SPACE)
	_add_action_key("toggle_cheatsheet", KEY_H)
	_add_action_key("toggle_enemy_passive", KEY_F2)


func _create_action_box(title: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", UI_TEXT)
	title_lbl.add_theme_color_override("font_outline_color", UI_OUTLINE_DARK)
	title_lbl.add_theme_constant_override("outline_size", 3)
	title_lbl.add_theme_font_size_override("font_size", 14)
	
	var rect = ColorRect.new()
	rect.custom_minimum_size = Vector2(120, 36)
	rect.color = UI_BG_STRONG
	
	var val_lbl = Label.new()
	val_lbl.text = "-"
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	val_lbl.add_theme_color_override("font_outline_color", UI_OUTLINE_DARK)
	val_lbl.add_theme_constant_override("outline_size", 3)
	val_lbl.add_theme_font_size_override("font_size", 13)
	rect.add_child(val_lbl)
	
	vbox.add_child(title_lbl)
	vbox.add_child(rect)
	return vbox


func _setup_mode_ui() -> void:
	var mode_hud = CanvasLayer.new()

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	main_vbox.position = Vector2(-480, -140)
	main_vbox.add_theme_constant_override("separation", 15)

	# Action buttons (LPM, SCROLL, PPM)
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 10)
	actions_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var lpm_box = _create_action_box("LPM")
	lpm_rect_val = lpm_box.get_child(1) as ColorRect
	lpm_label_val = lpm_rect_val.get_child(0) as Label
	var spm_box = _create_action_box("SCROLL")
	spm_rect_val = spm_box.get_child(1) as ColorRect
	spm_label_val = spm_rect_val.get_child(0) as Label
	var ppm_box = _create_action_box("PPM")
	ppm_rect_val = ppm_box.get_child(1) as ColorRect
	ppm_label_val = ppm_rect_val.get_child(0) as Label

	var space_box = _create_action_box("SPACJA")
	space_rect_val = space_box.get_child(1) as ColorRect
	var space_label_val = space_rect_val.get_child(0) as Label
	space_label_val.text = "hard-recall szczury"
	space_rect_val.custom_minimum_size = Vector2(160, 36)

	var space_hbox = HBoxContainer.new()
	space_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	space_hbox.add_child(space_box)

	actions_hbox.add_child(lpm_box)
	actions_hbox.add_child(spm_box)
	actions_hbox.add_child(ppm_box)

	main_vbox.add_child(space_hbox)
	main_vbox.add_child(actions_hbox)

	mode_hud.add_child(main_vbox)
	add_child(mode_hud)

	_update_mode_ui()

func _setup_cheatsheet_ui() -> void:
	var layer = CanvasLayer.new()
	var panel = Panel.new()
	cheatsheet_panel = panel
	panel.visible = true
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(20, 95)
	panel.custom_minimum_size = Vector2(380, 300)

	var style := StyleBoxFlat.new()
	style.bg_color = UI_BG
	style.border_color = UI_BORDER
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
	cheatsheet_margin = margin
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	cheatsheet_vbox = vbox
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	var title = Label.new()
	cheatsheet_title = title
	title.text = "STEROWANIE"
	title.add_theme_color_override("font_color", UI_TEXT)
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var body = RichTextLabel.new()
	cheatsheet_body = body
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_theme_font_size_override("normal_font_size", 12)
	body.add_theme_font_size_override("bold_font_size", 12)
	body.text = \
		"[b]Ruch[/b]\n" + \
		"WASD — ruch\n" + \
		"SPACJA (przytrzymaj 0.5s) — hard-recall szczurów (teleport)\n" + \
		"\n[b]Mysz[/b]\n" + \
		"LPM (przytrzymaj) — atak (okrąg wokół kursora)\n" + \
		"PPM (ciągnij) — rysuj strukturę lub przenieś obiekt\n" + \
		"Scroll — rozmiar pędzla (obrót przy przenoszeniu)\n" + \
		"\n[b]Inne[/b]\n" + \
		"H — pokaż/ukryj pomoc\n" + \
		"F2 — tryb pasywny wrogów"
	body.add_theme_color_override("default_color", UI_TEXT)
	body.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	body.add_theme_constant_override("outline_size", 2)
	vbox.add_child(body)

	var hint = Label.new()
	cheatsheet_hint = hint
	hint.text = "H — pokaż/ukryj pomoc"
	hint.add_theme_color_override("font_color", UI_HINT)
	hint.add_theme_color_override("font_outline_color", UI_OUTLINE_DARK)
	hint.add_theme_constant_override("outline_size", 3)
	hint.add_theme_font_size_override("font_size", 15)
	vbox.add_child(hint)

	layer.add_child(panel)
	add_child(layer)
	call_deferred("_refresh_cheatsheet_size")

func _refresh_cheatsheet_size() -> void:
	if not cheatsheet_panel or not cheatsheet_margin or not cheatsheet_body or not cheatsheet_vbox or not cheatsheet_title or not cheatsheet_hint:
		return
	# Fit panel to its content, but keep it on-screen and reasonably wide.
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var max_w: float = vp_size.x - 20.0
	var target_w: float = 440.0
	if max_w <= 0.0:
		return
	if max_w < 200.0:
		target_w = max_w
	else:
		target_w = clampf(440.0, 260.0, max_w)

	var m_left: int = cheatsheet_margin.get_theme_constant("margin_left")
	var m_right: int = cheatsheet_margin.get_theme_constant("margin_right")
	var m_top: int = cheatsheet_margin.get_theme_constant("margin_top")
	var m_bottom: int = cheatsheet_margin.get_theme_constant("margin_bottom")
	var sep: int = cheatsheet_vbox.get_theme_constant("separation")

	var content_w: float = max(200.0, target_w - float(m_left + m_right))
	cheatsheet_body.custom_minimum_size = Vector2(content_w, 0.0)

	var title_h: float = cheatsheet_title.get_minimum_size().y
	var hint_h: float = cheatsheet_hint.get_minimum_size().y
	var body_h: float = cheatsheet_body.get_content_height()

	var desired_h: float = float(m_top + m_bottom) + title_h + float(sep) + body_h + float(sep) + hint_h
	var max_h: float = max(200.0, vp_size.y - 40.0)
	var final_h: float = min(desired_h, max_h)

	cheatsheet_body.fit_content = desired_h <= max_h
	cheatsheet_body.scroll_active = desired_h > max_h

	cheatsheet_panel.custom_minimum_size = Vector2(target_w, final_h)
	cheatsheet_panel.size = cheatsheet_panel.custom_minimum_size
	var desired_x: float = 20.0
	var max_x: float = vp_size.x - cheatsheet_panel.size.x - 10.0
	cheatsheet_panel.position.x = max(10.0, min(desired_x, max_x))

func _setup_goal_ui() -> void:
	var layer = CanvasLayer.new()
	var label = Label.new()
	goal_label = label
	label.text = "Cel prototypu: wydostań się z labiryntu, pokonując kolejne poziomy i bossa na końcu."
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_left = 0
	label.offset_right = 0
	label.offset_top = 12
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 10)
	layer.add_child(label)
	add_child(layer)

func _setup_rat_count_ui() -> void:
	var layer = CanvasLayer.new()
	var label = RichTextLabel.new()
	rat_count_label = label
	var min_cap := 0
	if rat_manager and rat_manager.has_method("get_min_cap"):
		min_cap = rat_manager.get_min_cap()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.scroll_following = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.custom_minimum_size = Vector2(10, 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "Szczury: 0 | cap " + str(min_cap) + " | do wykorzystania [color=#9aa0a6]0[/color] | bonus [color=#9aa0a6]+0[/color]"
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

func _setup_offscreen_indicators_ui() -> void:
	indicator_layer = CanvasLayer.new()
	indicator_root = Control.new()
	indicator_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	indicator_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator_layer.add_child(indicator_root)
	add_child(indicator_layer)

func _get_indicator(idx: int) -> Label:
	while indicator_pool.size() <= idx:
		var lbl = Label.new()
		lbl.text = "▲"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.custom_minimum_size = Vector2(48, 48)
		lbl.size = Vector2(48, 48)
		lbl.pivot_offset = lbl.size * 0.5
		lbl.add_theme_font_size_override("font_size", 34)
		lbl.add_theme_color_override("font_color", indicator_color)
		lbl.visible = false
		indicator_root.add_child(lbl)
		indicator_pool.append(lbl)
	return indicator_pool[idx]

func _update_offscreen_indicators() -> void:
	if not indicator_layer or not indicator_root or player == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	var pad: float = indicator_screen_padding
	var inner_rect := Rect2(Vector2(pad, pad), vp_rect.size - Vector2(pad * 2.0, pad * 2.0))
	var center: Vector2 = inner_rect.get_center()

	var targets: Array[Node] = []
	targets.append_array(get_tree().get_nodes_in_group("enemies"))
	targets.append_array(get_tree().get_nodes_in_group("bosses"))
	targets.append_array(get_tree().get_nodes_in_group("turrets"))

	var idx: int = 0
	var ppos: Vector3 = player.global_position
	for t in targets:
		var node := t as Node3D
		if node == null:
			continue
		var dist: float = ppos.distance_to(node.global_position)
		if dist < indicator_min_distance or dist > indicator_max_distance:
			continue

		var screen_pos: Vector2 = cam.unproject_position(node.global_position)
		var behind: bool = cam.is_position_behind(node.global_position)

		if not behind and inner_rect.has_point(screen_pos):
			continue

		var dir: Vector2 = screen_pos - center
		if dir.length() < 0.001:
			continue
		if behind:
			dir = -dir

		var half: Vector2 = inner_rect.size * 0.5
		var scale_x: float = half.x / max(0.001, absf(dir.x))
		var scale_y: float = half.y / max(0.001, absf(dir.y))
		var scale: float = min(scale_x, scale_y)
		var pos: Vector2 = center + dir * scale

		var ind := _get_indicator(idx)
		idx += 1
		ind.visible = true
		ind.position = pos - ind.pivot_offset
		ind.rotation = atan2(dir.y, dir.x) + PI * 0.5

		var t_dist: float = clampf((dist - indicator_min_distance) / max(0.001, indicator_max_distance - indicator_min_distance), 0.0, 1.0)
		var alpha: float = lerpf(1.0, 0.35, t_dist)
		var blink: float = 1.0 - indicator_blink_depth + indicator_blink_depth * (0.5 + 0.5 * sin(_indicator_blink_time * indicator_blink_speed))
		alpha *= blink
		ind.modulate = Color(indicator_color.r, indicator_color.g, indicator_color.b, alpha)

	for i in range(idx, indicator_pool.size()):
		indicator_pool[i].visible = false

func _update_rat_count_ui() -> void:
	if not rat_count_label or not rat_manager:
		return
	var current_count := 0
	var min_cap := 0
	if rat_manager.has_method("get_active_rat_count"):
		current_count = rat_manager.get_active_rat_count()
	else:
		current_count = rat_manager.rats.size()
	if rat_manager.has_method("get_min_cap"):
		min_cap = rat_manager.get_min_cap()
	var available_count := current_count
	if rat_manager.has_method("get_available_rat_count"):
		available_count = rat_manager.get_available_rat_count()
	var extra: int = maxi(current_count - min_cap, 0)
	var extra_color: String = "#4ccf6a" if extra > 0 else "#9aa0a6"
	rat_count_label.text = "Szczury: " + str(current_count) + " | cap " + str(min_cap) + " | do wykorzystania [color=#9aa0a6]" + str(available_count) + "[/color] | bonus [color=" + extra_color + "]+" + str(extra) + "[/color]"


func _update_mode_ui() -> void:
	if lpm_label_val: lpm_label_val.text = "atak"
	if spm_label_val: spm_label_val.text = "rozmiar / obrót"
	if ppm_label_val: ppm_label_val.text = "buduj / przenieś"

func _gather_levels() -> void:
	_levels.clear()
	if levels_root == null:
		return
	for child in levels_root.get_children():
		var lvl := child as Node3D
		if lvl:
			_levels.append(lvl)

func _get_level_center_node(level: Node3D) -> Node3D:
	if level == null:
		return null
	var center := level.get_node_or_null("CameraCenter")
	if center and center is Node3D:
		return center as Node3D
	return level

func _pick_current_level(player_pos: Vector3) -> Node3D:
	if _levels.is_empty():
		return null
	var best: Node3D = null
	var best_dist := INF
	for lvl in _levels:
		var center := _get_level_center_node(lvl)
		if center == null:
			continue
		var dist := player_pos.distance_to(center.global_position)
		if dist < best_dist:
			best = lvl
			best_dist = dist

	if _current_level and best and best != _current_level:
		var cur_center := _get_level_center_node(_current_level)
		if cur_center:
			var cur_dist := player_pos.distance_to(cur_center.global_position)
			if cur_dist - best_dist < cam_level_switch_hysteresis:
				best = _current_level

	return best

func _set_level_occlusion(level: Node3D, enabled: bool) -> void:
	if level == null:
		return
	level.visible = enabled

	# Disable collisions for hidden levels
	var queue: Array[Node] = [level]
	while not queue.is_empty():
		var n: Node = queue.pop_back() as Node
		if n is CollisionObject3D:
			var co := n as CollisionObject3D
			if enabled:
				if co.has_meta("_saved_collision_layer"):
					co.collision_layer = int(co.get_meta("_saved_collision_layer"))
					co.collision_mask = int(co.get_meta("_saved_collision_mask"))
			else:
				if not co.has_meta("_saved_collision_layer"):
					co.set_meta("_saved_collision_layer", co.collision_layer)
					co.set_meta("_saved_collision_mask", co.collision_mask)
				co.collision_layer = 0
				co.collision_mask = 0
		for child in n.get_children():
			queue.append(child)

func _close_level_doors(level: Node3D) -> void:
	if level == null:
		return
	for door in get_tree().get_nodes_in_group("doors"):
		var d := door as Node3D
		if d and level.is_ancestor_of(d) and d.has_method("close"):
			d.close()
		if d and level.is_ancestor_of(d) and d.has_method("reset_presses"):
			d.reset_presses()

func _reset_level_objects(level: Node3D) -> void:
	if level == null:
		return
	for box in get_tree().get_nodes_in_group("boxes"):
		var b := box as Node3D
		if b and level.is_ancestor_of(b) and b.has_method("_activate_reset_to_spawn"):
			b._activate_reset_to_spawn()
	for btn in get_tree().get_nodes_in_group("buttons"):
		var n := btn as Node
		if n and level.is_ancestor_of(n) and n.has_method("reset_button_state"):
			n.reset_button_state()

func restart_level_for_checkpoint(level: Node3D) -> void:
	if level == null:
		return
	force_current_level(level)
	_close_level_doors(level)
	_reset_level_objects(level)
	if rat_manager and rat_manager.has_method("reset_respawn_and_restore"):
		rat_manager.reset_respawn_and_restore()

func _update_level_occlusion(current: Node3D) -> void:
	var current_idx := _levels.find(current)
	for i in range(_levels.size()):
		var lvl := _levels[i]
		var is_visible := (i == current_idx) or (i == current_idx + 1)
		_set_level_occlusion(lvl, is_visible)
		if not is_visible:
			_close_level_doors(lvl)

func force_current_level(level: Node3D) -> void:
	if level == null:
		return
	_forced_level = level
	_current_level = level
	_update_level_occlusion(_current_level)

func clear_forced_level(level: Node3D = null) -> void:
	if level == null or _forced_level == level:
		_forced_level = null


func _process(delta: float) -> void:
	_update_rat_count_ui()
	_update_recall_hold(delta)
	_indicator_blink_time += delta
	
	# ── Update Action Colors (LPM, SCROLL, PPM) ──
	var highlight_color = Color(0.9, 0.9, 0.9, 1.0)
	var normal_color = Color(0.1, 0.1, 0.1, 0.8)
	
	if lpm_rect_val: lpm_rect_val.color = highlight_color if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else normal_color
	if ppm_rect_val: ppm_rect_val.color = highlight_color if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else normal_color
	if space_rect_val: space_rect_val.color = highlight_color if Input.is_action_pressed("recall_rats") else normal_color
	
	if _scroll_highlight_timer > 0.0:
		_scroll_highlight_timer -= delta
		if spm_rect_val: spm_rect_val.color = highlight_color
	else:
		if spm_rect_val: spm_rect_val.color = normal_color
		
	# ── Camera follow ──
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		# Focus point: between player and cursor world pos (closer to player)
		var focus := player.position
		var mouse_pos := get_viewport().get_mouse_position()
		var ray_origin := cam.project_ray_origin(mouse_pos)
		var ray_dir := cam.project_ray_normal(mouse_pos)
		# Intersect with Y=0 ground plane
		if abs(ray_dir.y) > 0.001:
			var t := -ray_origin.y / ray_dir.y
			if t > 0.0:
				var cursor_world := ray_origin + ray_dir * t
				focus = player.position.lerp(cursor_world, 1.0 / 6.0)

		# Look-ahead based on cursor position on screen (biased to where you point)
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		if viewport_size.x > 0.0 and viewport_size.y > 0.0:
			var center := viewport_size * 0.5
			var norm := (mouse_pos - center) / center
			norm.x = clampf(norm.x, -1.0, 1.0)
			norm.y = clampf(norm.y, -1.0, 1.0)
			if norm.length() < cam_look_ahead_deadzone:
				norm = Vector2.ZERO

			# Map screen space to world XZ (isometric camera)
			var desired := Vector3(norm.x, 0.0, norm.y) * cam_look_ahead_max
			_cam_look_ahead = _cam_look_ahead.lerp(desired, 1.0 - exp(-cam_look_ahead_smooth * delta))
		else:
			_cam_look_ahead = _cam_look_ahead.lerp(Vector3.ZERO, 1.0 - exp(-cam_look_ahead_smooth * delta))

		# Keep constant offset angle
		var offset := Vector3(10, 12, 10)
		
		# Blend in level center for better puzzle visibility
		var current_level := _forced_level if _forced_level else _pick_current_level(player.global_position)
		if current_level and current_level != _current_level:
			_current_level = current_level
			_update_level_occlusion(_current_level)
		var center_node := _get_level_center_node(_current_level) if _current_level else null
		if center_node:
			var weight := cam_level_focus_weight_forced if _forced_level else cam_level_focus_weight
			focus = focus.lerp(center_node.global_position, weight)

		cam.position = cam.position.lerp(focus + offset + _cam_look_ahead, 0.03)
		
		# Force strict isometric angle by looking parallel to the offset vector
		var current_focus := cam.position - offset
		cam.look_at(current_focus, Vector3.UP)
	
	_update_offscreen_indicators()


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

	# Catch scroll events for UI highlight
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_scroll_highlight_timer = 0.15


func _update_recall_hold(delta: float) -> void:
	if not rat_manager:
		return
	var holding := Input.is_action_pressed("recall_rats")
	if holding and not _recall_triggered:
		_recall_hold_time = min(_recall_hold_time + delta, 0.5)
		if _recall_hold_time >= 0.5:
			rat_manager.hard_recall_all_rats()
			_recall_triggered = true
	else:
		_recall_hold_time = 0.0
		_recall_triggered = false

	if recall_indicator:
		if holding and not _recall_triggered:
			recall_indicator.visible = true
			recall_indicator.set("progress", _recall_hold_time / 0.5)
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
