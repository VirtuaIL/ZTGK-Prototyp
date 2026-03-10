extends CanvasLayer

var progress_bar: ProgressBar
var label: Label
var container: PanelContainer
var rat_manager: Node = null


func _ready() -> void:
	# Container panel - top-left
	container = PanelContainer.new()
	container.position = Vector2(20, 20)
	container.custom_minimum_size = Vector2(220, 0)
	container.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	container.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	container.add_child(vbox)

	# Label
	label = Label.new()
	label.text = "Szczurza Orbita"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(label)

	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(200, 14)
	progress_bar.max_value = 1.0
	progress_bar.value = 1.0
	progress_bar.show_percentage = false

	# Style the bar
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.22)
	bg.corner_radius_top_left = 3
	bg.corner_radius_top_right = 3
	bg.corner_radius_bottom_left = 3
	bg.corner_radius_bottom_right = 3
	progress_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.85, 0.4)
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	progress_bar.add_theme_stylebox_override("fill", fill)

	vbox.add_child(progress_bar)

	add_child(container)


func _process(_delta: float) -> void:
	if rat_manager == null:
		return

	if rat_manager.orbit_active:
		container.visible = true
		var progress: float = rat_manager.get_orbit_progress()
		progress_bar.value = progress

		# Color shifts from green to yellow to red
		var fill_style: StyleBoxFlat = progress_bar.get_theme_stylebox("fill")
		if progress > 0.5:
			fill_style.bg_color = Color(0.3, 0.85, 0.4)
		elif progress > 0.2:
			fill_style.bg_color = Color(0.9, 0.75, 0.2)
		else:
			fill_style.bg_color = Color(0.9, 0.25, 0.2)
	else:
		if container.visible:
			container.visible = false
