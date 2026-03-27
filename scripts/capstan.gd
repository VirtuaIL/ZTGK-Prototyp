extends StaticBody3D
class_name Capstan

## The door ID this capstan controls (must match a door's doorId)
@export var doorId: int = 0

## Radius around the capstan in which rats count as "pushing"
@export var detection_radius: float = 2.5

## How much rat angular movement translates to open_progress (per radian)
@export var rotation_sensitivity: float = 0.12

## How fast open_progress decays when no rats are pushing (per second)
@export var decay_speed: float = 0.15

## Minimum number of rats required to start turning
@export var min_rats_to_turn: int = 3

## Visual rotation speed multiplier (how fast the cylinder spins visually)
@export var visual_rotation_mult: float = 2.0

## How far the capstan sinks into the ground when fully opened
@export var sink_depth: float = 1.2

## If the mouse cursor is within this radius, rats are attracted to orbit the capstan
@export var cursor_attract_radius: float = 4.0

## Radius at which attracted rats orbit the capstan (must be > cylinder radius + rat size)
@export var orbit_attract_radius: float = 1.6

## Orbit speed in radians per second
@export var orbit_speed: float = 2.5

# ── Internal state ────────────────────────────────────────────────────────────
var open_progress: float = 0.0
var _rat_angles: Dictionary = {}   # rat instance_id → last angle (radians)
var _detection_radius_sq: float = 0.0
var _initial_y: float = 0.0
var _completed: bool = false
var _prev_cursor_angle: float = 0.0
var _cursor_angle_valid: bool = false
var _orbit_direction: float = 1.0   # +1 or -1, smoothed


func _ready() -> void:
	add_to_group("capstans")
	_detection_radius_sq = detection_radius * detection_radius
	_initial_y = global_position.y


func _get_rat_angle(rat: Node3D) -> float:
	var diff := rat.global_position - global_position
	return atan2(diff.x, diff.z)


func _get_nearby_rats() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var managers := get_tree().get_nodes_in_group("rat_manager")
	if managers.is_empty():
		return result
	var rm = managers[0]
	for r in rm.rats:
		var rat := r as Node3D
		if rat == null or not is_instance_valid(rat) or not rat.is_inside_tree():
			continue
		var dx: float = rat.global_position.x - global_position.x
		var dz: float = rat.global_position.z - global_position.z
		if (dx * dx + dz * dz) <= _detection_radius_sq:
			result.append(rat)
	return result


func _physics_process(delta: float) -> void:
	# Once fully opened, nothing more to do
	if _completed:
		return

	var nearby_rats := _get_nearby_rats()
	var active_rat_count := nearby_rats.size()

	# Build a set of current nearby rat IDs for cleanup
	var current_ids: Dictionary = {}
	for rat in nearby_rats:
		current_ids[rat.get_instance_id()] = true

	# Remove stale entries from _rat_angles
	var stale_keys: Array = []
	for key in _rat_angles:
		if not current_ids.has(key):
			stale_keys.append(key)
	for key in stale_keys:
		_rat_angles.erase(key)

	if active_rat_count >= min_rats_to_turn:
		# Calculate total angular movement of all rats around the capstan
		var total_delta_angle: float = 0.0

		for rat in nearby_rats:
			var id := rat.get_instance_id()
			var current_angle := _get_rat_angle(rat)

			if _rat_angles.has(id):
				var prev_angle: float = _rat_angles[id]
				var da := current_angle - prev_angle

				# Wrap angle delta to [-PI, PI] to handle crossing the ±PI boundary
				while da > PI:
					da -= TAU
				while da < -PI:
					da += TAU

				total_delta_angle += absf(da)

			_rat_angles[id] = current_angle

		# Apply rotation to open_progress
		open_progress += total_delta_angle * rotation_sensitivity
		open_progress = clampf(open_progress, 0.0, 1.0)

		# Visual rotation of the cylinder mesh
		var visual := get_node_or_null("CylinderMesh")
		if visual:
			visual.rotation.y += total_delta_angle * visual_rotation_mult

	else:
		# Update stored angles even when not enough rats (prevents jump when
		# new rats arrive)
		for rat in nearby_rats:
			_rat_angles[rat.get_instance_id()] = _get_rat_angle(rat)

		# Decay progress when not enough rats are pushing
		if open_progress > 0.0:
			open_progress = maxf(0.0, open_progress - decay_speed * delta)

	# Apply progress to doors
	_apply_to_doors()

	# Attract rats when cursor is near the capstan
	_attract_rats_to_capstan(delta)

	# When fully opened → play final sink animation and lock
	if open_progress >= 1.0:
		_trigger_completed()


func _attract_rats_to_capstan(delta: float) -> void:
	var mouse_world := _mouse_to_world()
	if mouse_world == Vector3.ZERO:
		_cursor_angle_valid = false
		return

	# Check if cursor is near the capstan (XZ distance only)
	var cdx: float = mouse_world.x - global_position.x
	var cdz: float = mouse_world.z - global_position.z
	if (cdx * cdx + cdz * cdz) > cursor_attract_radius * cursor_attract_radius:
		_cursor_angle_valid = false
		return

	# Only attract rats that are already near the capstan (the ones pushing)
	var nearby_rats := _get_nearby_rats()
	var follow_rats: Array[Node3D] = []
	for rat in nearby_rats:
		if rat is Rat and rat.state == Rat.State.FOLLOW and not rat.is_carrier:
			follow_rats.append(rat)

	if follow_rats.is_empty():
		_cursor_angle_valid = false
		return

	# Track cursor movement around the capstan to determine orbit direction
	var cursor_angle := atan2(cdx, cdz)
	if _cursor_angle_valid:
		var cursor_da := cursor_angle - _prev_cursor_angle
		while cursor_da > PI:
			cursor_da -= TAU
		while cursor_da < -PI:
			cursor_da += TAU
		# If cursor is actively moving around capstan, follow its direction
		if absf(cursor_da) > 0.005:
			_orbit_direction = lerpf(_orbit_direction, signf(cursor_da), 0.15)
	_prev_cursor_angle = cursor_angle
	_cursor_angle_valid = true

	for rat in follow_rats:
		var to_rat := rat.global_position - global_position
		to_rat.y = 0.0
		var dist := to_rat.length()
		if dist < 0.01:
			continue

		var radial_dir := to_rat / dist

		# Tangent direction (perpendicular to radius, in orbit direction)
		var tangent := Vector3(-radial_dir.z, 0.0, radial_dir.x) * _orbit_direction

		# Pull toward orbit radius (gentle radial correction)
		var radial_pull := (orbit_attract_radius - dist) * radial_dir * 0.5

		# Target = current pos + tangent movement + radial correction
		var target := rat.global_position + tangent * 2.0 + radial_pull
		target.y = global_position.y
		rat.set_target(target)


func _mouse_to_world() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var mp := get_viewport().get_mouse_position()
	var ro := cam.project_ray_origin(mp)
	var rd := cam.project_ray_normal(mp)
	# Intersect with Y = capstan Y plane
	if abs(rd.y) > 0.001:
		var t := (global_position.y - ro.y) / rd.y
		if t > 0.0:
			return ro + rd * t
	return Vector3.ZERO


func _trigger_completed() -> void:
	_completed = true
	open_progress = 1.0
	_apply_to_doors()

	# Animate the capstan sinking completely underground
	var final_y: float = _initial_y - sink_depth - 2.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "global_position:y", final_y, 1.2)


func _apply_to_doors() -> void:
	var doors := get_tree().get_nodes_in_group("doors")
	for d in doors:
		if d is door and d.doorId == doorId:
			d.set_open_progress(open_progress)
