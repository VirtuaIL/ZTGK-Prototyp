extends Control

const HEADER_HEIGHT: float = 26.0
const FRAME_PADDING: float = 8.0
const PLAYER_AHEAD_DISTANCE: float = 2.8

@export var frame_color: Color = Color(0.84, 0.95, 0.93, 0.9)
@export var accent_color: Color = Color(0.22, 0.95, 0.76, 0.9)
@export var grid_color: Color = Color(0.55, 0.95, 0.89, 0.18)
@export var tint_color: Color = Color(0.02, 0.08, 0.1, 0.18)
@export var sweep_color: Color = Color(0.45, 1.0, 0.85, 0.12)
@export var player_color: Color = Color(0.98, 0.98, 1.0, 1.0)
@export var enemy_color: Color = Color(1.0, 0.4, 0.34, 0.95)
@export var turret_color: Color = Color(1.0, 0.77, 0.33, 0.95)
@export var boss_color: Color = Color(1.0, 0.2, 0.7, 1.0)
@export var crystal_color: Color = Color(0.34, 0.92, 1.0, 0.95)

var _player: Node3D = null
var _minimap_camera: Camera3D = null
var _subviewport: SubViewport = null
var _pulse_time: float = 0.0
var _sweep_angle: float = -PI * 0.5

var _title_label: Label
var _range_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_resolve_references()
	_create_labels()
	resized.connect(_layout_labels)
	_layout_labels()
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_time += delta
	_sweep_angle = wrapf(_sweep_angle + delta * 1.15, -PI, PI)

	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _minimap_camera == null or not is_instance_valid(_minimap_camera):
		_resolve_references()

	if _range_label and _minimap_camera:
		_range_label.text = "RANGE %dm" % int(round(_minimap_camera.size))

	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var radar_rect := _get_radar_rect(rect)
	if radar_rect.size.x <= 0.0 or radar_rect.size.y <= 0.0:
		return

	draw_rect(rect, tint_color, true)
	draw_rect(Rect2(0.0, 0.0, rect.size.x, HEADER_HEIGHT), Color(0.0, 0.0, 0.0, 0.42), true)
	draw_rect(rect, frame_color, false, 2.0)
	draw_rect(radar_rect, Color(frame_color.r, frame_color.g, frame_color.b, 0.2), false, 1.0)

	var center := radar_rect.get_center()
	var radius := minf(radar_rect.size.x, radar_rect.size.y) * 0.5 - 10.0
	var pulse := 0.5 + 0.5 * sin(_pulse_time * 2.6)

	draw_arc(center, radius, 0.0, TAU, 64, grid_color, 1.4, true)
	draw_arc(center, radius * 0.68, 0.0, TAU, 64, Color(grid_color.r, grid_color.g, grid_color.b, grid_color.a * 1.1), 1.0, true)
	draw_arc(center, radius * 0.36, 0.0, TAU, 64, Color(grid_color.r, grid_color.g, grid_color.b, grid_color.a * 1.2), 1.0, true)

	draw_line(Vector2(radar_rect.position.x, center.y), Vector2(radar_rect.end.x, center.y), grid_color, 1.0)
	draw_line(Vector2(center.x, radar_rect.position.y), Vector2(center.x, radar_rect.end.y), grid_color, 1.0)

	var sweep_end := center + Vector2(cos(_sweep_angle), sin(_sweep_angle)) * radius
	draw_line(center, sweep_end, Color(sweep_color.r, sweep_color.g, sweep_color.b, sweep_color.a + pulse * 0.08), 2.0)
	draw_circle(center, 3.0, Color(accent_color.r, accent_color.g, accent_color.b, 0.55))

	_draw_markers("enemies", enemy_color, "circle", 3.4 + pulse * 0.8, radar_rect)
	_draw_markers("turrets", turret_color, "square", 4.2, radar_rect)
	_draw_markers("bosses", boss_color, "diamond", 5.4 + pulse * 0.8, radar_rect)
	_draw_markers("healing_crystals", crystal_color, "diamond", 4.4, radar_rect)
	_draw_player_indicator(radar_rect)


func _resolve_references() -> void:
	_player = _find_player()
	_minimap_camera = get_node_or_null("../SubViewport/MinimapCamera") as Camera3D
	_subviewport = get_node_or_null("../SubViewport") as SubViewport


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D


func _create_labels() -> void:
	_title_label = Label.new()
	_title_label.text = "MAPA TAKTYCZNA"
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_color_override("font_color", Color(0.97, 0.99, 0.98, 1.0))
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.72))
	_title_label.add_theme_constant_override("outline_size", 3)
	_title_label.add_theme_font_size_override("font_size", 11)
	add_child(_title_label)

	_range_label = Label.new()
	_range_label.text = "RANGE"
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_range_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_range_label.add_theme_color_override("font_color", accent_color)
	_range_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.72))
	_range_label.add_theme_constant_override("outline_size", 3)
	_range_label.add_theme_font_size_override("font_size", 10)
	add_child(_range_label)


func _layout_labels() -> void:
	if _title_label:
		_title_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_title_label.position = Vector2(10.0, 5.0)

	if _range_label:
		_range_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_range_label.size = Vector2(92.0, 16.0)
		_range_label.position = Vector2(size.x - _range_label.size.x - 10.0, 6.0)


func _get_radar_rect(rect: Rect2) -> Rect2:
	var pos := Vector2(FRAME_PADDING, HEADER_HEIGHT + 6.0)
	var radar_size := rect.size - Vector2(FRAME_PADDING * 2.0, HEADER_HEIGHT + FRAME_PADDING + 6.0)
	return Rect2(pos, radar_size)


func _draw_markers(group_name: String, color: Color, marker_kind: String, marker_size: float, radar_rect: Rect2) -> void:
	if _minimap_camera == null or _subviewport == null:
		return

	var current_scene := get_tree().current_scene

	for node in get_tree().get_nodes_in_group(group_name):
		var target := node as Node3D
		if target == null or not is_instance_valid(target):
			continue
		if target == _player:
			continue
		if current_scene != null and current_scene.has_method("is_node_in_current_level"):
			if not current_scene.is_node_in_current_level(target):
				continue
		if _minimap_camera.is_position_behind(target.global_position):
			continue

		var projected := _project_world(target.global_position)
		var clamped := Vector2(
			clampf(projected.x, radar_rect.position.x + 4.0, radar_rect.end.x - 4.0),
			clampf(projected.y, radar_rect.position.y + 4.0, radar_rect.end.y - 4.0)
		)
		var is_edge_marker := projected.distance_squared_to(clamped) > 1.0
		var draw_color := color
		if is_edge_marker:
			draw_color.a *= 0.55

		match marker_kind:
			"circle":
				draw_circle(clamped, marker_size, draw_color)
			"square":
				draw_rect(Rect2(clamped - Vector2.ONE * marker_size, Vector2.ONE * marker_size * 2.0), draw_color, true)
			"diamond":
				_draw_diamond(clamped, marker_size, draw_color)

		if group_name == "bosses":
			_draw_diamond(clamped, marker_size + 2.2, Color(1.0, 1.0, 1.0, 0.18))


func _draw_player_indicator(radar_rect: Rect2) -> void:
	if _player == null or not is_instance_valid(_player) or _minimap_camera == null:
		return

	var center := _project_world(_player.global_position)
	center.x = clampf(center.x, radar_rect.position.x + 6.0, radar_rect.end.x - 6.0)
	center.y = clampf(center.y, radar_rect.position.y + 6.0, radar_rect.end.y - 6.0)

	var facing := Vector3(sin(_player.rotation.y), 0.0, cos(_player.rotation.y))
	var nose := _project_world(_player.global_position + facing * PLAYER_AHEAD_DISTANCE)
	var direction := nose - center
	if direction.length_squared() < 0.01:
		direction = Vector2.UP * -1.0
	else:
		direction = direction.normalized()

	var side := Vector2(-direction.y, direction.x)
	var tip := center + direction * 10.0
	var base := center - direction * 4.0
	var points := PackedVector2Array([
		tip,
		base + side * 5.0,
		base - side * 5.0,
	])
	draw_colored_polygon(points, player_color)
	draw_circle(center, 3.0, accent_color)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius),
		center + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(points, color)


func _project_world(world_position: Vector3) -> Vector2:
	if _minimap_camera == null or _subviewport == null:
		return size * 0.5

	var projected := _minimap_camera.unproject_position(world_position)
	var viewport_size := Vector2(_subviewport.size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return size * 0.5

	return Vector2(
		projected.x * size.x / viewport_size.x,
		projected.y * size.y / viewport_size.y
	)
