extends box
class_name redirection_box

@export var damage_per_second: float = 34.0
@export var max_range: float = 20.0
@export var indicator_range: float = 14.0
@export var indicator_thickness: float = 0.03
@export var indicator_color: Color = Color(1.0, 0.65, 0.25, 0.6)

@onready var laser_mesh: MeshInstance3D = $LaserMesh
@onready var fire_point: Vector3 = Vector3(0, 0.7, 0.45) # Front face of the box

var _laser_active_this_frame: bool = false
var _is_processing_laser: bool = false # Loop prevention
var _indicator_mesh: MeshInstance3D

func _ready() -> void:
	super._ready()
	if laser_mesh:
		laser_mesh.visible = false
	_indicator_mesh = MeshInstance3D.new()
	_indicator_mesh.mesh = CylinderMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = indicator_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_indicator_mesh.material_override = mat
	_indicator_mesh.visible = false
	add_child(_indicator_mesh)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	
	# Update visibility. If no laser hit us this frame, the laser turns off.
	if laser_mesh:
		laser_mesh.visible = _laser_active_this_frame

	_update_drag_indicator()
	
	# Reset for the next frame
	_laser_active_this_frame = false

# Called by emitters or other redirection boxes
func receive_laser(delta: float) -> void:
	if _is_processing_laser:
		return
	
	_is_processing_laser = true
	_laser_active_this_frame = true
	_cast_redirected_laser(delta)
	_is_processing_laser = false

func _cast_redirected_laser(delta: float) -> void:
	if not laser_mesh:
		return

	var space_state := get_world_3d().direct_space_state
	
	# The redirected laser starts at the front of the box
	var start_pos = global_transform.translated_local(fire_point).origin
	# Laser points forward (-Z direction in local space)
	var dir = -global_transform.basis.z.normalized()
	var ray_end = start_pos + dir * max_range
	
	var query := PhysicsRayQueryParameters3D.create(start_pos, ray_end)
	query.collision_mask = 15 # Floor (1) + Player (2) + Movable (4) + Walls (8)
	query.exclude = [self.get_rid()]
	
	var hit := space_state.intersect_ray(query)
	
	if hit:
		var hit_pos: Vector3 = hit.position
		_update_laser_visuals(start_pos, hit_pos)
		
		# Chain redirection or damage
		if hit.collider.has_method("receive_laser"):
			hit.collider.receive_laser(delta)
		elif hit.collider.has_method("die"):
			hit.collider.die()
	else:
		_update_laser_visuals(start_pos, ray_end)

func _update_laser_visuals(start_pos: Vector3, end_pos: Vector3) -> void:
	laser_mesh.visible = true
	var distance = start_pos.distance_to(end_pos)
	
	if distance < 0.001:
		laser_mesh.visible = false
		return
		
	var mid_point = start_pos.lerp(end_pos, 0.5)
	laser_mesh.global_position = mid_point
	
	# Reset rotation
	laser_mesh.basis = Basis()
	
	# Point -Z axis at the target
	var dir = (end_pos - start_pos).normalized()
	var up = Vector3.UP
	if abs(dir.y) > 0.99:
		up = Vector3.RIGHT
		
	laser_mesh.look_at(end_pos, up)
	laser_mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	
	# Scale the height (Y). Cylinder default is 2.0m.
	laser_mesh.scale = Vector3(0.1, distance / 2.0, 0.1)

func _update_drag_indicator() -> void:
	if _indicator_mesh == null:
		return
	var dragging := false
	if has_meta("is_being_dragged"):
		dragging = bool(get_meta("is_being_dragged"))
	if not dragging:
		_indicator_mesh.visible = false
		return
	_cast_indicator_beam()

func _cast_indicator_beam() -> void:
	var space_state := get_world_3d().direct_space_state
	var start_pos = global_transform.translated_local(fire_point).origin
	var dir = -global_transform.basis.z.normalized()
	var ray_end = start_pos + dir * indicator_range

	var query := PhysicsRayQueryParameters3D.create(start_pos, ray_end)
	query.collision_mask = 15 # Floor (1) + Player (2) + Movable (4) + Walls (8)
	query.exclude = [self.get_rid()]

	var hit := space_state.intersect_ray(query)
	if hit:
		_update_indicator_visuals(start_pos, hit.position)
	else:
		_update_indicator_visuals(start_pos, ray_end)

func _update_indicator_visuals(start_pos: Vector3, end_pos: Vector3) -> void:
	_indicator_mesh.visible = true
	var distance = start_pos.distance_to(end_pos)
	if distance < 0.001:
		_indicator_mesh.visible = false
		return

	var mid_point = start_pos.lerp(end_pos, 0.5)
	_indicator_mesh.global_position = mid_point
	_indicator_mesh.basis = Basis()

	var dir = (end_pos - start_pos).normalized()
	var up = Vector3.UP
	if abs(dir.y) > 0.99:
		up = Vector3.RIGHT
	_indicator_mesh.look_at(end_pos, up)
	_indicator_mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	_indicator_mesh.scale = Vector3(indicator_thickness, distance / 2.0, indicator_thickness)
