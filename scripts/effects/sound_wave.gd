extends Node3D
class_name SoundWave

## The MeshInstance3D child that displays the wave
@export var wave_mesh: MeshInstance3D = null

## Height offset above the ground plane
@export var height_offset: float = 0.15

## Width of the wave plane (perpendicular to direction)
@export var wave_width: float = 1.8

## Minimum length before the wave becomes visible
@export var min_visible_distance: float = 1.0

## Maximum wave length (caps the plane stretch)
@export var max_wave_length: float = 40.0

## Smoothing speed for the end-point (rat side) only
@export var end_lerp_weight: float = 8.0

var _current_start: Vector3 = Vector3.ZERO
var _current_end: Vector3 = Vector3.ZERO
var _smooth_end: Vector3 = Vector3.ZERO
var _initialized: bool = false
var _shader_mat: ShaderMaterial = null
var _plane_mesh: PlaneMesh = null


func _ready() -> void:
	if wave_mesh == null:
		wave_mesh = get_node_or_null("WaveMesh") as MeshInstance3D
	if wave_mesh == null:
		push_warning("SoundWave: WaveMesh child not found, creating one.")
		_create_default_mesh()

	if wave_mesh.material_override is ShaderMaterial:
		_shader_mat = wave_mesh.material_override as ShaderMaterial
	elif wave_mesh.mesh and wave_mesh.mesh.surface_get_material(0) is ShaderMaterial:
		_shader_mat = wave_mesh.mesh.surface_get_material(0) as ShaderMaterial

	_plane_mesh = wave_mesh.mesh as PlaneMesh
	visible = false


func _create_default_mesh() -> void:
	wave_mesh = MeshInstance3D.new()
	wave_mesh.name = "WaveMesh"
	var pm := PlaneMesh.new()
	pm.size = Vector2(wave_width, 1.0)
	pm.subdivide_width = 0
	pm.subdivide_depth = 64
	pm.orientation = PlaneMesh.FACE_Y
	wave_mesh.mesh = pm
	wave_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wave_mesh)


## Call every frame to update the wave endpoints.
func update_wave(start_pos: Vector3, end_pos: Vector3) -> void:
	_current_start = start_pos
	_current_end = end_pos
	if not _initialized:
		_smooth_end = end_pos
		_initialized = true


func _process(delta: float) -> void:
	if _current_start == Vector3.ZERO and _current_end == Vector3.ZERO:
		visible = false
		return

	# Smooth only the rat-side end point; player side is always exact
	var weight := 1.0 - exp(-end_lerp_weight * delta)
	_smooth_end = _smooth_end.lerp(_current_end, weight)

	var start := _current_start
	var end := _smooth_end

	var dir := end - start
	dir.y = 0.0
	var length := dir.length()

	if length < min_visible_distance:
		visible = false
		return

	visible = true
	length = minf(length, max_wave_length)
	var dir_norm := dir.normalized()

	# Position the node exactly at the player start point
	var anchor := start
	anchor.y = maxf(start.y, end.y) + height_offset
	global_position = anchor

	# Orient: make local -Z point toward the rats
	var look_target := anchor + dir_norm
	look_target.y = anchor.y
	if anchor.distance_to(look_target) > 0.001:
		look_at(look_target, Vector3.UP)
		rotate_y(PI)

	# Offset the mesh child so it extends FROM the player TOWARD the rats
	# PlaneMesh center is at local origin, so shift it forward by half the length
	wave_mesh.position = Vector3(0.0, 0.0, length * 0.5)

	# Scale the plane mesh to match the distance
	if _plane_mesh:
		_plane_mesh.size = Vector2(wave_width, length)
