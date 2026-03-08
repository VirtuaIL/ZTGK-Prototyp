extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var vbox: VBoxContainer = $Panel/MarginContainer/VBoxContainer

var strat_rows: Array[Dictionary] = []
var direction_symbols := {
	"up": "↑",
	"down": "↓",
	"left": "←",
	"right": "→",
}

var is_visible_menu: bool = false


func _ready() -> void:
	panel.modulate.a = 0.0
	panel.visible = false


func show_menu(stratagems: Array[Dictionary]) -> void:
	if stratagems.size() == 0:
		return

	is_visible_menu = true
	panel.visible = true

	# Clear old rows (skip static children like TitleLabel/InputDisplay)
	for row in strat_rows:
		if is_instance_valid(row["container"]):
			row["container"].queue_free()
	strat_rows.clear()

	# Also hide old static children if they exist
	for child in vbox.get_children():
		child.visible = false

	# Build a row for each stratagem
	for strat in stratagems:
		var row_container := HBoxContainer.new()
		row_container.add_theme_constant_override("separation", 4)

		var name_lbl := Label.new()
		name_lbl.text = strat["name"] + "  "
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
		name_lbl.custom_minimum_size = Vector2(140, 0)
		row_container.add_child(name_lbl)

		var arrows: Array[Label] = []
		for dir_name in strat["sequence"]:
			var lbl := Label.new()
			lbl.text = direction_symbols.get(dir_name, "?")
			lbl.add_theme_font_size_override("font_size", 28)
			lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.custom_minimum_size = Vector2(36, 36)
			row_container.add_child(lbl)
			arrows.append(lbl)

		vbox.add_child(row_container)
		strat_rows.append({
			"container": row_container,
			"title": name_lbl,
			"arrows": arrows,
		})

	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)


func hide_menu() -> void:
	is_visible_menu = false
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.1)
	tween.tween_callback(func(): panel.visible = false)


func highlight_direction(input_index: int, matching_strat_indices: Array) -> void:
	for row_idx in range(strat_rows.size()):
		var arrows: Array = strat_rows[row_idx]["arrows"]
		if input_index < 0 or input_index >= arrows.size():
			continue

		if row_idx in matching_strat_indices:
			arrows[input_index].add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
			var tween := create_tween()
			tween.tween_property(arrows[input_index], "scale", Vector2(1.3, 1.3), 0.05)
			tween.tween_property(arrows[input_index], "scale", Vector2(1.0, 1.0), 0.1)
		else:
			# Dim entire non-matching row
			for lbl: Label in arrows:
				if is_instance_valid(lbl):
					lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))


func reset_highlights() -> void:
	for row in strat_rows:
		for lbl: Label in row["arrows"]:
			if is_instance_valid(lbl):
				lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))


func flash_success() -> void:
	for row in strat_rows:
		for lbl: Label in row["arrows"]:
			if is_instance_valid(lbl):
				lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))

	var tween := create_tween()
	tween.tween_interval(0.3)
	tween.tween_callback(func(): reset_highlights())


func flash_fail() -> void:
	for row in strat_rows:
		for lbl: Label in row["arrows"]:
			if is_instance_valid(lbl):
				lbl.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))

	var tween := create_tween()
	tween.tween_interval(0.3)
	tween.tween_callback(func(): reset_highlights())
