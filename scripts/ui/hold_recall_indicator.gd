extends Control

@export var radius: float = 10.0
@export var thickness: float = 2.0
@export var bg_color: Color = Color(0.0, 0.0, 0.0, 0.6)
@export var fg_color: Color = Color(1.0, 1.0, 1.0, 0.9)

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := radius * 2.0 + thickness * 2.0
	custom_minimum_size = Vector2(d, d)
	size = custom_minimum_size


func _draw() -> void:
	var center := size * 0.5
	draw_arc(center, radius, 0.0, TAU, 32, bg_color, thickness)
	if progress > 0.0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, fg_color, thickness)
