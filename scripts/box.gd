extends CharacterBody3D
class_name box

@export var carriers_required: int = 4
@export var fall_death_y: float = -1.0
@export var gravity_multiplier: float = 5.0

signal object_reset

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []
var carrier_available_max: int = 0
var carrier_brush_desired: int = 0

var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	collision_layer = 4 # Layer 3: Movable
	collision_mask = 31 | (1 << 8)  # Floor (1) + Player (2) + Movable (4) + Walls (8) + Barrier (16) + RatStructures (9)
	_spawn_position = global_position
	add_to_group("boxes")

func _activate_reset_to_spawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	object_reset.emit()

func die() -> void:
	_activate_reset_to_spawn()


func _physics_process(delta: float) -> void:
	# Fall reset
	if global_position.y < fall_death_y:
		global_position = _spawn_position
		velocity = Vector3.ZERO
		object_reset.emit()
		return

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * gravity_multiplier
	else:
		velocity.y = 0.0

	move_and_slide()

	# Check for overweight / overhang on bridge
	var overhanging_bridge := false
	var space_state := get_world_3d().direct_space_state
	var center := global_position + Vector3.UP * 0.1
	
	var query_center := PhysicsRayQueryParameters3D.create(center, center + Vector3.DOWN * 2.0)
	query_center.collision_mask = 1 | (1 << 8) # Floor (1) + RatStructures (9)
	query_center.exclude = [self]
	
	var hit_center := space_state.intersect_ray(query_center)
	if hit_center and hit_center.collider and hit_center.collider.is_in_group("rat_structures"):
		# We are on a bridge. Check corners/edges
		var shape_owner_id := shape_find_owner(0)
		if shape_owner_id != -1:
			var shape_owner := shape_owner_get_owner(shape_owner_id) as CollisionShape3D
			if shape_owner and shape_owner.shape:
				var aabb := shape_owner.shape.get_debug_mesh().get_aabb()
				var scl := global_transform.basis.get_scale()
				var extents := aabb.size * scl * 0.45
				
				# Check 4 corners. If any corner is unsupported, it's wider
				var corners = [
					Vector3(extents.x, 0, extents.z),
					Vector3(-extents.x, 0, extents.z),
					Vector3(extents.x, 0, -extents.z),
					Vector3(-extents.x, 0, -extents.z)
				]
				
				var unsupported_count := 0
				for c in corners:
					var world_c = global_transform * c + Vector3.UP * 0.1
					var q := PhysicsRayQueryParameters3D.create(world_c, world_c + Vector3.DOWN * 2.0)
					q.collision_mask = 1 | (1 << 8)
					q.exclude = [self]
					var hit := space_state.intersect_ray(q)
					if not hit:
						unsupported_count += 1
				
				# If at least 2 corners are unsupported, consider it overhanging
				if unsupported_count >= 2:
					overhanging_bridge = true
					
	if overhanging_bridge:
		var rm := get_tree().get_first_node_in_group("rat_manager")
		if rm and rm.has_method("add_bridge_stress"):
			rm.add_bridge_stress(delta)


func set_highlight(enabled: bool) -> void:
	var mesh_instance: MeshInstance3D = get_node_or_null("Body")
	if not mesh_instance:
		return
		
	if enabled:
		if mesh_instance.material_overlay:
			return # Already highlighted
			
		var highlight_mat = StandardMaterial3D.new()
		highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		highlight_mat.albedo_color = Color.YELLOW
		highlight_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		highlight_mat.no_depth_test = true
		highlight_mat.grow = true
		highlight_mat.grow_amount = 0.03
		
		mesh_instance.material_overlay = highlight_mat
	else:
		mesh_instance.material_overlay = null
