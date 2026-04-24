extends CharacterBody3D
class_name Rat

const DeathEffect := preload("res://scenes/rat/rat_death_effect.tscn")
const GasCloudScene := preload("res://scenes/projectiles/gas_cloud.tscn")

enum State {FOLLOW, ORBIT, WAVE, TRAVEL_TO_BUILD, WAITING_FOR_FORMATION, STATIC, PATH_DASH}
enum RatType {NORMAL, RED, GREEN}
@export var rat_type: RatType = RatType.NORMAL
var default_rat_type: RatType = RatType.NORMAL
var _base_material: Material = null
var _speed_mult: float = 1.0

@export_group("Blob Shadow")
@export var shadow_enabled: bool = true
@export var shadow_size: float = 0.8
@export var shadow_opacity: float = 1.0
@export var shadow_offset_y: float = 0.2
@export_group("")



@export var follow_speed: float = 6.0
@export var orbit_radius: float = 4.0
@export var orbit_speed: float = 4.0
@export var max_follow_distance: float = 22.0
@export var travel_timeout: float = 3.0

# Spring-damp parameters (used in FOLLOW state)
@export var spring_stiffness: float = 30.0
@export var damping: float = 0.8
@export var separation_dist: float = 0.5
@export var separation_force: float = 12.0
@export var alignment_force: float = 5.0
@export var cohesion_force: float = 3.0
@export var boid_max_force: float = 20.0
@export var max_speed: float = 26.0
@export var edge_avoidance_enabled: bool = true
@export var edge_probe_distance: float = 0.45
@export var edge_max_drop: float = 0.6
@export var wall_avoidance_enabled: bool = true
@export var wall_avoidance_force: float = 52.0
@export var wall_avoidance_probe_distance: float = 1.2
@export var wall_avoidance_side_probe_distance: float = 0.85
@export var wall_avoidance_tangent_bias: float = 0.75
@export var stuck_recovery_enabled: bool = true
@export var stuck_min_speed: float = 0.22
@export var stuck_target_distance: float = 2.4
@export var stuck_time_to_trigger: float = 0.7
@export var stuck_unblock_duration: float = 0.45
@export var stuck_target_boost: float = 1.9
@export var release_boost_speed: float = 14.0
@export var release_boost_up: float = 20.0
@export var release_boost_time: float = 0.25

var state: State = State.FOLLOW
var is_wild: bool = false
@export var recruitment_range: float = 3.5
@export var wild_lifespan: float = 10.0
var _wild_timer: float = 0.0
var player: Node3D = null
var follow_offset: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var lerp_speed: float = 8.0
var extra_spin_speed: float = 0.0

# Spring-damp internal state
var _spring_velocity: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO
var _target_ready: bool = false
var _neighbors: Array = []

# Blob State (Build Mode) — kept for blob_target compat
var is_following_player: bool = true
var blob_target: Vector3 = Vector3.ZERO

# Wave state
var wave_direction: Vector3 = Vector3.ZERO
var wave_speed: float = 18.0
var wave_timer: float = 0.0
var wave_duration: float = 0.8

var _dash_path: PackedVector3Array
var _dash_index: int = 0
var _dash_lateral_offset: float = 0.0
@export var dash_speed: float = 30.0

# Damage
var damage_per_hit: float = 1.5
var hit_range: float = 0.8
var attack_cooldown: float = 0.0

var _gas_timer: float = 0.0

# Build state
var build_target: Vector3 = Vector3.ZERO
var _travel_timer: float = 0.0

# Carrier flag — set while this rat is assigned to carry a box;
# prevents brush operations from reassigning it
var is_carrier: bool = false

# Fall recovery
@export var fall_death_y: float = -1.0
@export var respawn_time: float = 1.0
@export var spawn_player_distance: float = 3.0
@export var respawn_near_player_when_near_spawn: bool = true

# Bridge anchoring — when true, gravity and fall-recovery are suppressed
# so rats can float in mid-air to form bridges
var is_anchored: bool = false
@export var anchor_radius: float = 2.0

var is_fallen: bool = false
var _recall_boost_timer: float = 0.0
var _mgr: Node = null
var _mgr_refresh_timer: float = 0.0
@export var mgr_refresh_interval: float = 1.0
@export var edge_check_interval: float = 0.15
@export var wall_check_interval: float = 0.1
var _edge_check_timer: float = 0.0
var _wall_check_timer: float = 0.0
var _edge_blocked_cached: bool = false
var _wall_steer_cached: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
var _unstuck_timer: float = 0.0
var _current_buff_material: Material = null
var _blob_mesh: MeshInstance3D = null
var _is_showing_blob: bool = false
var _visual_meshes: Array[MeshInstance3D] = []
var _visual_base_transforms: Dictionary = {}
var _visual_phase: Dictionary = {}
var _blob_wobble_time: float = 0.0
var _blob_wobble_speed: float = 6.5
var _blob_wobble_amp: float = 0.08
var _blob_wobble_rot: float = 0.25
var _blob_wobble_bob: float = 0.03

# Throttling rekrutacji
var _recruit_timer: float = 0.0
@export var recruit_interval: float = 0.15

# Shared materials to allow batching
static var _shared_mats: Dictionary = {}

func _get_shared_material(r_type: RatType, wild_variant: bool) -> Material:
	var key := str(int(r_type)) + "_" + str(wild_variant)
	if _shared_mats.has(key):
		return _shared_mats[key]
	
	var mat := _make_type_material(r_type, wild_variant)
	_shared_mats[key] = mat
	return mat

func _ready() -> void:
	var shadow: Decal = get_node_or_null("BlobShadow")
	if shadow:
		shadow.visible = shadow_enabled
		shadow.size = Vector3(shadow_size, 2.0, shadow_size)
		shadow.modulate = Color(1, 1, 1, shadow_opacity)
		shadow.position.y = shadow_offset_y
		shadow.cull_mask = 1048575 - 2 # Prevent projection on layer 2 (rats)

	for child in find_children("*", "VisualInstance3D"):
		if child != shadow:
			child.layers = 2
	follow_offset = Vector3(
		randf_range(-1.5, 1.5),
		0.0,
		randf_range(-1.5, 1.5)
	)
	
	if is_wild:
		add_to_group("wild_rats")
	
	# Layer 1 = Floor, Layer 2 = Player, Layer 3 = Movable Objects, Layer 4 = Walls
	collision_layer = 0 # Rats don't need to be hit by anything except maybe projectiles
	collision_mask = 9 | (1 << 8) # Floor (1) + Walls (8) + RatStructures (9)
	
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(45.0)
	_mgr = get_tree().get_first_node_in_group("rat_manager")
	_wall_check_timer = randf_range(0.0, wall_check_interval)
	_edge_check_timer = randf_range(0.0, edge_check_interval)
	
	var sphere = SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	_blob_mesh = MeshInstance3D.new()
	_blob_mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.30, 0.18)
	_blob_mesh.material_override = mat
	_blob_mesh.visible = false
	add_child(_blob_mesh)
	_cache_visual_meshes()
	default_rat_type = rat_type
	set_rat_type(int(rat_type))


func _process(delta: float) -> void:
	if _mgr != null:
		var mgr = _mgr
		var should_be_blob = mgr.get("combat_rmb_down") and mgr.get("current_attack_mode") == 1 and state == State.FOLLOW and not is_carrier and not is_wild and not is_fallen
		if should_be_blob != _is_showing_blob:
			_is_showing_blob = should_be_blob
			show_visuals()
			if not _is_showing_blob:
				_reset_blob_visuals()
	
	if _is_showing_blob:
		_update_blob_visuals(delta)
	
	if _wild_timer > 0.0 and is_wild:
		_wild_timer -= delta
		if _wild_timer <= 0.0:
			queue_free()

func _physics_process(delta: float) -> void:
	if is_wild:
		_process_wild_physics(delta)
		return

	if player == null:
		return
		
	if _mgr_refresh_timer > 0.0:
		_mgr_refresh_timer = max(0.0, _mgr_refresh_timer - delta)
	if _mgr == null or not is_instance_valid(_mgr):
		if _mgr_refresh_timer <= 0.0:
			_mgr = get_tree().get_first_node_in_group("rat_manager")
			_mgr_refresh_timer = mgr_refresh_interval
	var mgr = _mgr
	
	# ── Purple poison: slow down instead of freezing ──
	_speed_mult = 1.0
	if mgr != null and "buff_purple_timer" in mgr and mgr.buff_purple_timer > 0.0:
		_speed_mult = 0.15

	# ── Green gas ──
	if mgr != null:
		var has_green = (default_rat_type == RatType.GREEN) or ("buff_green_timer" in mgr and mgr.buff_green_timer > 0.0)
		if has_green:
			_gas_timer -= delta
			var speed_sq = velocity.x * velocity.x + velocity.z * velocity.z
			if _gas_timer <= 0.0 and speed_sq > 0.05:
				_gas_timer = 0.07
				var can_emit := true
				if mgr.has_method("request_gas_emit"):
					can_emit = mgr.request_gas_emit()
				if GasCloudScene and can_emit:
					var p = get_parent()
					if p:
						var g = GasCloudScene.instantiate()
						p.add_child(g)
						g.global_position = global_position
		
	if attack_cooldown > 0.0:
		attack_cooldown = maxf(0.0, attack_cooldown - delta)

	if _edge_check_timer > 0.0:
		_edge_check_timer = max(0.0, _edge_check_timer - delta)
	if _unstuck_timer > 0.0:
		_unstuck_timer = max(0.0, _unstuck_timer - delta)

	if _recall_boost_timer > 0.0:
		_recall_boost_timer = max(0.0, _recall_boost_timer - delta)
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.000001:
			var dir := to_player.normalized()
			velocity.x = dir.x * release_boost_speed * _speed_mult
			velocity.z = dir.z * release_boost_speed * _speed_mult
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 50
		else:
			velocity.y = 0.0
		move_and_slide()
		return

	if not is_anchored and global_position.y < fall_death_y:
		_start_respawn()
		return

	if is_anchored or state == State.TRAVEL_TO_BUILD or state == State.WAITING_FOR_FORMATION:
		velocity.y = 0.0
	else:
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 50
		else:
			velocity.y = 0.0
		
	var target_mat = null
	if mgr != null and mgr.has_method("get_current_buff_material"):
		var buff_mat = mgr.get_current_buff_material()
		if buff_mat != null:
			target_mat = buff_mat

	if target_mat == null:
		target_mat = _base_material

	if target_mat != _current_buff_material:
		_current_buff_material = target_mat
		_apply_material_override(target_mat)

	match state:
		State.FOLLOW:
			_process_follow_spring(delta)
		State.ORBIT:
			_process_orbit(delta)
		State.WAVE:
			_process_wave(delta)
		State.TRAVEL_TO_BUILD:
			_process_travel_to_build(delta)
		State.WAITING_FOR_FORMATION:
			return
		State.STATIC:
			return
		State.PATH_DASH:
			_process_path_dash(delta)

	_check_damage()

	if extra_spin_speed != 0.0:
		rotation.y += extra_spin_speed * delta

	# Push rigid bodies — skip if nearly still
	if velocity.length_squared() > 0.1:
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			var collider := col.get_collider()
			if collider is RigidBody3D:
				var push_force := 0.2 * _speed_mult
				collider.apply_impulse(-col.get_normal() * push_force, col.get_position() - collider.global_position)


func _process_follow_spring(delta: float) -> void:
	if not _target_ready:
		return

	var current_stiffness = spring_stiffness
	var current_separation = separation_force
	var current_alignment = alignment_force
	var current_cohesion = cohesion_force
	if _is_showing_blob:
		current_stiffness = spring_stiffness * 4.0
		current_separation = 0.0
		current_alignment = 0.0
		current_cohesion = 0.0
	elif _unstuck_timer > 0.0:
		current_stiffness *= maxf(1.0, stuck_target_boost)
		current_cohesion *= 0.5
		current_alignment *= 0.75

	# Spring toward target — flatten Y so it doesn't bounce vertically
	var to_target := _target_position - global_position
	to_target.y *= 0.2
	_spring_velocity += to_target * current_stiffness * delta

	var sep_dist_sq := separation_dist * separation_dist
	var separation_vec := Vector3.ZERO
	var alignment_vec := Vector3.ZERO
	var cohesion_center := Vector3.ZERO
	var neighbor_count := 0
	# Separation + alignment + cohesion from neighbors
	if current_separation > 0.0 or current_alignment > 0.0 or current_cohesion > 0.0:
		for neighbor in _neighbors:
			if not is_instance_valid(neighbor):
				continue
			var nb := neighbor as Node3D
			if nb == null:
				continue
			neighbor_count += 1
			var diff: Vector3 = global_position - nb.global_position
			diff.y = 0.0
			var dist_sq: float = diff.length_squared()
			if dist_sq < sep_dist_sq and dist_sq > 0.000001:
				separation_vec += (diff / sqrt(dist_sq)) * ((separation_dist - sqrt(dist_sq)) / maxf(0.001, separation_dist))
			cohesion_center += nb.global_position
			if "velocity" in nb:
				var nb_vel: Vector3 = nb.velocity
				nb_vel.y = 0.0
				alignment_vec += nb_vel

	var boid_force := Vector3.ZERO
	if current_separation > 0.0 and separation_vec.length_squared() > 0.000001:
		boid_force += separation_vec.normalized() * current_separation
	if neighbor_count > 0:
		if current_alignment > 0.0 and alignment_vec.length_squared() > 0.000001:
			boid_force += alignment_vec.normalized() * current_alignment
		if current_cohesion > 0.0:
			var avg_center := cohesion_center / float(neighbor_count)
			var to_center := avg_center - global_position
			to_center.y = 0.0
			if to_center.length_squared() > 0.000001:
				boid_force += to_center.normalized() * current_cohesion
	if boid_max_force > 0.0 and boid_force.length_squared() > boid_max_force * boid_max_force:
		boid_force = boid_force.normalized() * boid_max_force
	_spring_velocity += boid_force * delta
	_spring_velocity += _compute_wall_avoidance(to_target) * delta

	# Framerate-independent damping
	_spring_velocity *= pow(damping, delta * 60.0)

	# Clamp horizontal speed
	var hvel_sq := _spring_velocity.x * _spring_velocity.x + _spring_velocity.z * _spring_velocity.z
	var eff_max := max_speed * _speed_mult
	if hvel_sq > eff_max * eff_max:
		var hvel: Vector2 = Vector2(_spring_velocity.x, _spring_velocity.z).normalized() * eff_max
		_spring_velocity.x = hvel.x
		_spring_velocity.z = hvel.y

	# Preserve gravity-driven vertical velocity, add spring horizontal
	velocity.x = _spring_velocity.x
	velocity.z = _spring_velocity.z
	if _should_block_edge(Vector2(velocity.x, velocity.z)):
		velocity.x = 0.0
		velocity.z = 0.0
		_spring_velocity.x = 0.0
		_spring_velocity.z = 0.0
	move_and_slide()
	# Sync spring velocity with collision response (horizontal only)
	_spring_velocity.x = velocity.x
	_spring_velocity.z = velocity.z
	_update_stuck_recovery(delta)

	# Face direction of travel (skip if spinning in combat)
	if extra_spin_speed == 0.0:
		var move_dir_sq := velocity.x * velocity.x + velocity.z * velocity.z
		if move_dir_sq > 0.16: # 0.4 * 0.4
			rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), 14.0 * delta)


func set_target(pos: Vector3) -> void:
	_target_position = pos
	_target_ready = true


func set_neighbors(n: Array) -> void:
	_neighbors = n


func _compute_wall_avoidance(to_target: Vector3) -> Vector3:
	if not wall_avoidance_enabled:
		return Vector3.ZERO
		
	var delta := get_physics_process_delta_time()
	_wall_check_timer -= delta
	if wall_check_interval > 0.0 and _wall_check_timer > 0.0:
		return _wall_steer_cached

	var world := get_world_3d()
	if world == null:
		return Vector3.ZERO
	var ss := world.direct_space_state

	var desired := Vector3(_spring_velocity.x, 0.0, _spring_velocity.z)
	if desired.length_squared() < 0.0001:
		desired = Vector3(to_target.x, 0.0, to_target.z)
	if desired.length_squared() < 0.0001:
		return Vector3.ZERO
	desired = desired.normalized()

	var origin := global_position + Vector3.UP * 0.22
	var dirs := [
		desired,
		desired.rotated(Vector3.UP, deg_to_rad(32.0)),
		desired.rotated(Vector3.UP, deg_to_rad(-32.0)),
	]
	var ranges := [
		wall_avoidance_probe_distance,
		wall_avoidance_side_probe_distance,
		wall_avoidance_side_probe_distance,
	]

	var steer := Vector3.ZERO
	for i in range(dirs.size()):
		var probe_dir: Vector3 = dirs[i]
		var probe_dist: float = maxf(0.05, ranges[i])
		var query := PhysicsRayQueryParameters3D.create(origin, origin + probe_dir * probe_dist)
		query.collision_mask = 8 # Walls
		query.exclude = [ self ]
		var hit := ss.intersect_ray(query)
		if hit.is_empty():
			continue

		var normal: Vector3 = hit.normal
		normal.y = 0.0
		if normal.length_squared() < 0.0001:
			continue
		normal = normal.normalized()

		var hit_pos: Vector3 = hit.position
		var dist_sq := origin.distance_squared_to(hit_pos)
		var proximity := clampf(1.0 - sqrt(dist_sq) / probe_dist, 0.0, 1.0)
		if proximity <= 0.0:
			continue

		# Push away from wall.
		steer += normal * (wall_avoidance_force * proximity)
		# Add tangent slide so rats prefer flowing around walls instead of braking.
		var tangent := normal.cross(Vector3.UP).normalized()
		if tangent.dot(desired) < 0.0:
			tangent = - tangent
		steer += tangent * (wall_avoidance_force * wall_avoidance_tangent_bias * proximity)

	_wall_steer_cached = steer
	_wall_check_timer = wall_check_interval
	return steer


func _update_stuck_recovery(delta: float) -> void:
	if not stuck_recovery_enabled:
		_stuck_time = 0.0
		return
	if _target_ready == false or state != State.FOLLOW:
		_stuck_time = 0.0
		return
	if is_carrier or is_anchored or _recall_boost_timer > 0.0:
		_stuck_time = 0.0
		return

	var to_target := _target_position - global_position
	to_target.y = 0.0
	var target_dist_sq := to_target.length_squared()
	if target_dist_sq < stuck_target_distance * stuck_target_distance:
		_stuck_time = 0.0
		return

	var hspeed_sq := velocity.x * velocity.x + velocity.z * velocity.z
	if hspeed_sq <= stuck_min_speed * stuck_min_speed:
		_stuck_time += delta
		if _stuck_time >= stuck_time_to_trigger:
			_unstuck_timer = maxf(_unstuck_timer, stuck_unblock_duration)
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


func _process_orbit(delta: float) -> void:
	orbit_angle += orbit_speed * delta

	var target_pos := player.global_position + Vector3(
		cos(orbit_angle) * orbit_radius,
		0.0,
		sin(orbit_angle) * orbit_radius
	)

	var current := global_position
	var new_pos := current.lerp(target_pos, lerp_speed * _speed_mult * delta)
	var lerp_vel: Vector3 = (new_pos - current) / max(delta, 0.001)
	velocity.x = lerp_vel.x
	velocity.z = lerp_vel.z
	if _should_block_edge(Vector2(velocity.x, velocity.z)):
		velocity.x = 0.0
		velocity.z = 0.0

	var forward_dir := Vector3(-sin(orbit_angle), 0.0, cos(orbit_angle))
	var target_angle := atan2(forward_dir.x, forward_dir.z)
	rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)

	move_and_slide()


func set_orbit(angle: float, radius: float = 4.0) -> void:
	orbit_angle = angle
	orbit_radius = radius
	state = State.ORBIT


func set_follow() -> void:
	state = State.FOLLOW


func set_wave(direction: Vector3, delay: float) -> void:
	wave_direction = direction.normalized()
	wave_timer = - delay
	state = State.WAVE


func _process_wave(delta: float) -> void:
	wave_timer += delta
	if wave_timer < 0.0:
		return # still in delay

	if wave_timer >= wave_duration:
		set_follow()
		return

	velocity.x = wave_direction.x * wave_speed * _speed_mult
	velocity.z = wave_direction.z * wave_speed * _speed_mult
	if _should_block_edge(Vector2(velocity.x, velocity.z)):
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()

	var target_angle := atan2(wave_direction.x, wave_direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)


func start_path_dash(path: PackedVector3Array, lateral_offset: float) -> void:
	_dash_path = path
	_dash_index = 0
	_dash_lateral_offset = lateral_offset
	state = State.PATH_DASH
	is_following_player = false
	_spring_velocity = Vector3.ZERO


func _process_path_dash(delta: float) -> void:
	if _dash_path.size() == 0 or _dash_index >= _dash_path.size():
		set_follow()
		return
		
	var p0 = _dash_path[_dash_index]
	var dir_forward := Vector3.FORWARD
	
	if _dash_path.size() > 1:
		if _dash_index < _dash_path.size() - 1:
			dir_forward = (_dash_path[_dash_index + 1] - p0).normalized()
		else:
			dir_forward = (p0 - _dash_path[_dash_index - 1]).normalized()
			
	dir_forward.y = 0.0
	if dir_forward.length_squared() < 0.000001:
		dir_forward = Vector3.FORWARD
		
	var lateral_dir := dir_forward.cross(Vector3.UP).normalized()
	var target = p0 + lateral_dir * _dash_lateral_offset
	target.y = global_position.y
	
	var dist_sq = global_position.distance_squared_to(target)
	if dist_sq < 0.64: # 0.8 * 0.8
		_dash_index += 1
		if _dash_index >= _dash_path.size():
			set_follow()
			return
			
	var to_target = target - global_position
	var dir := to_target.normalized()
	velocity.x = dir.x * dash_speed * _speed_mult
	velocity.z = dir.z * dash_speed * _speed_mult
	
	if _should_block_edge(Vector2(velocity.x, velocity.z)):
		velocity.x = 0.0
		velocity.z = 0.0
		
	move_and_slide()
	if velocity.x * velocity.x + velocity.z * velocity.z > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), lerp_speed * delta)


# Static cache for enemies to avoid multiple get_nodes_in_group calls per frame
static var _cached_enemies: Array = []
static var _cached_frame: int = -1

func _get_enemies_cached() -> Array:
	var f := Engine.get_frames_drawn()
	if _cached_frame != f:
		_cached_frame = f
		_cached_enemies = []
		var current_scene := get_tree().current_scene
		if current_scene != null and current_scene.has_method("get_nodes_in_current_level"):
			_cached_enemies.append_array(current_scene.get_nodes_in_current_level("enemies"))
			_cached_enemies.append_array(current_scene.get_nodes_in_current_level("bosses"))
		else:
			_cached_enemies = get_tree().get_nodes_in_group("enemies")
			_cached_enemies += get_tree().get_nodes_in_group("bosses")
	return _cached_enemies

func _check_damage() -> void:
	if attack_cooldown > 0.0:
		return
		
	var mgr = _mgr
	if mgr == null or not is_instance_valid(mgr):
		mgr = get_tree().get_first_node_in_group("rat_manager")
		
	var mgr_has_red = (mgr != null and "buff_red_timer" in mgr and mgr.buff_red_timer > 0.0)
	var is_red_rat = (default_rat_type == RatType.RED)
	var is_red = is_red_rat or mgr_has_red
	
	if not is_red:
		if mgr == null or (state != State.PATH_DASH):
			return
		
	if mgr != null and mgr.get("current_attack_mode") == 1: # BLOB mode
		return
		
	var enemies := _get_enemies_cached()
	
	var final_dmg = damage_per_hit
	var dmg_color = Color.WHITE
	
	if is_red:
		final_dmg *= 2.0
		dmg_color = Color(0.9, 0.1, 0.1)
	
	var hit_range_sq = hit_range * hit_range
	for enemy in enemies:
		var dist_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_sq < hit_range_sq:
			enemy.take_damage(final_dmg, get_instance_id(), global_position, dmg_color)
			attack_cooldown = 1.0
			break


func _process_travel_to_build(delta: float) -> void:
	# Use XZ-only distance so gravity doesn't prevent arrival
	var dx := build_target.x - global_position.x
	var dz := build_target.z - global_position.z
	var dist_sq := dx * dx + dz * dz
	_travel_timer += delta
	if travel_timeout > 0.0 and _travel_timer >= travel_timeout:
		state = State.WAITING_FOR_FORMATION
		global_position = build_target
		velocity = Vector3.ZERO
		# Restore floor collision
		set_collision_mask_value(1, true)
		return

	if dist_sq <= anchor_radius * anchor_radius:
		is_anchored = true

	# Disable floor collision while traveling so rats glide over platform edges
	# instead of clipping into them
	set_collision_mask_value(1, false)

	if dist_sq > 0.01:
		var dist := sqrt(dist_sq)
		var dir_x := dx / dist
		var dir_z := dz / dist
		velocity.x = dir_x * follow_speed * 2.0 * _speed_mult
		velocity.z = dir_z * follow_speed * 2.0 * _speed_mult
		# Smoothly lerp Y toward build target instead of instant snap
		global_position.y = lerpf(global_position.y, build_target.y, 5.0 * delta)
		var target_angle := atan2(dir_x, dir_z)
		rotation.y = lerp_angle(rotation.y, target_angle, lerp_speed * delta)
		move_and_slide()
	else:
		state = State.WAITING_FOR_FORMATION
		global_position = build_target
		velocity = Vector3.ZERO
		# Restore floor collision once placed
		set_collision_mask_value(1, true)


func activate_physics() -> void:
	if state == State.WAITING_FOR_FORMATION:
		state = State.STATIC
		set_collision_layer_value(1, true)
		set_physics_process(false)


func build_at(pos: Vector3) -> void:
	# Carrier rats must not be redirected to brush destinations
	if is_carrier:
		return
	if state == State.FOLLOW:
		state = State.TRAVEL_TO_BUILD
		build_target = pos
		_travel_timer = 0.0


func release_rat(with_boost: bool = false) -> void:
	if state == State.STATIC or state == State.TRAVEL_TO_BUILD or state == State.WAITING_FOR_FORMATION:
		state = State.FOLLOW
		is_anchored = false
		is_carrier = false
		_spring_velocity = Vector3.ZERO
		set_physics_process(true)
		if with_boost and player != null:
			var to_player := player.global_position - global_position
			to_player.y = 0.0
			if to_player.length_squared() > 0.000001:
				var dir := to_player.normalized()
				_spring_velocity.x = dir.x * release_boost_speed * _speed_mult
				_spring_velocity.z = dir.z * release_boost_speed * _speed_mult
				velocity.x = _spring_velocity.x
				velocity.z = _spring_velocity.z
			velocity.y = release_boost_up
			_recall_boost_timer = release_boost_time
		else:
			velocity.y = 5.0
		_travel_timer = 0.0
		# Lose solidity
		set_collision_layer_value(1, false)
		show_visuals()


func _teleport_to_player() -> void:
	_reset_to_follow()
	global_position = player.global_position + Vector3(
		randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)
	)


func _start_respawn() -> void:
	if is_fallen:
		return
	is_fallen = true
	_reset_to_follow()
	hide_visuals()
	set_physics_process(false)
	await get_tree().create_timer(respawn_time).timeout
	_respawn_at_spawn_point()


func _respawn_at_spawn_point() -> void:
	var spawn := _get_nearest_spawn(global_position)
	if spawn == null:
		_teleport_to_player()
		_finish_respawn()
		return
	if player == null:
		global_position = spawn.global_position + Vector3(
			randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6)
		)
		_finish_respawn()
		return
	global_position = spawn.global_position + Vector3(
		randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6)
	)
	if not respawn_near_player_when_near_spawn:
		_finish_respawn()
		return
	_wait_for_player_near_spawn(spawn)


func _wait_for_player_near_spawn(spawn: Node3D) -> void:
	while player != null and spawn != null:
		var player_dist_sq := _flat_distance_squared(player.global_position, spawn.global_position)
		if player_dist_sq <= spawn_player_distance * spawn_player_distance:
			global_position = player.global_position + Vector3(
				randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)
			)
			break
		await get_tree().process_frame
	_finish_respawn()


func force_respawn_near_player() -> void:
	if player == null:
		return
	_reset_to_follow()
	global_position = player.global_position + Vector3(
		randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)
	)
	_finish_respawn()


func force_respawn_at_position(pos: Vector3) -> void:
	_reset_to_follow()
	global_position = pos
	_finish_respawn()


func hard_recall_to_player() -> void:
	if player == null:
		return
	_reset_to_follow()
	
	# Teleport close to player unconditionally (for Spacebar recall)
	var offset = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)).normalized() * randf_range(0.5, 2.0)
	global_position = player.global_position + offset
	
	_travel_timer = 0.0
	_recall_boost_timer = 0.0
	is_fallen = false
	set_physics_process(true)
	show_visuals()

func soft_reset_state() -> void:
	if player == null:
		return
	_reset_to_follow()
	_travel_timer = 0.0
	_recall_boost_timer = 0.0
	is_fallen = false
	set_physics_process(true)
	# Keep current position — let FOLLOW spring physics move rats naturally
	show_visuals()


func _get_nearest_spawn(pos: Vector3) -> Node3D:
	var spawns: Array = []
	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("get_current_level_rat_spawns"):
		spawns = current_scene.get_current_level_rat_spawns()
	else:
		spawns = get_tree().get_nodes_in_group("rat_spawn")
	var best: Node3D = null
	var best_dist := INF
	for s in spawns:
		var n := s as Node3D
		if n == null:
			continue
		var d := _flat_distance_squared(n.global_position, pos)
		if d < best_dist:
			best_dist = d
			best = n
	return best


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return sqrt(_flat_distance_squared(a, b))


func _flat_distance_squared(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


func _finish_respawn() -> void:
	is_fallen = false
	show_visuals()
	set_physics_process(true)


func _reset_to_follow() -> void:
	is_anchored = false
	state = State.FOLLOW
	is_following_player = true
	_spring_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	set_collision_layer_value(1, false)
	# Restore floor collision in case it was disabled during TRAVEL_TO_BUILD
	set_collision_mask_value(1, true)
	show_visuals()


func hide_visuals() -> void:
	for m in _visual_meshes:
		if m:
			m.hide()
	_is_showing_blob = false
	if _blob_mesh:
		_blob_mesh.hide()


func show_visuals() -> void:
	for m in _visual_meshes:
		if m:
			m.show()
	if _blob_mesh:
		_blob_mesh.hide()


func set_wall_collision(enabled: bool) -> void:
	set_collision_mask_value(4, enabled)


func _should_block_edge(hvel: Vector2) -> bool:
	if not edge_avoidance_enabled:
		return false
	if _unstuck_timer > 0.0:
		return false
	if is_carrier:
		return false
	if _recall_boost_timer > 0.0:
		return false
	if is_anchored:
		return false
	if state == State.TRAVEL_TO_BUILD or state == State.WAITING_FOR_FORMATION or state == State.STATIC:
		return false
	if hvel.length_squared() < 0.0001:
		return false

	if edge_check_interval > 0.0 and _edge_check_timer > 0.0:
		return _edge_blocked_cached

	var forward := Vector3(hvel.x, 0.0, hvel.y).normalized()
	var probe_pos := global_position + forward * edge_probe_distance
	var blocked := not _has_floor_near(probe_pos, edge_max_drop)
	if edge_check_interval > 0.0:
		_edge_blocked_cached = blocked
		_edge_check_timer = edge_check_interval
	return blocked


func _has_floor_near(pos: Vector3, max_drop: float) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var ss := world.direct_space_state
	var origin := pos + Vector3.UP * 0.3
	var end := pos + Vector3.DOWN * (max_drop + 0.8)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 1 | (1 << 8) # Floor + RatStructures
	query.exclude = [ self ]
	var hit := ss.intersect_ray(query)
	if not hit:
		return false
	return hit.position.y >= global_position.y - max_drop

func die() -> void:
	var mgr = _mgr
	if mgr == null or not is_instance_valid(mgr):
		mgr = get_tree().get_first_node_in_group("rat_manager")
	if mgr != null and "buff_yellow_timer" in mgr and mgr.buff_yellow_timer > 0.0:
		return

	if DeathEffect:
		var eff = DeathEffect.instantiate()
		get_parent().add_child(eff)
		eff.global_position = global_position
		
	if mgr != null and "rats" in mgr:
		var idx = mgr.rats.find(self )
		if idx != -1:
			mgr.rats.remove_at(idx)
	queue_free()

func _make_type_material(r_type: RatType, wild_variant: bool = false) -> Material:
	match r_type:
		RatType.RED:
			var red := StandardMaterial3D.new()
			red.albedo_color = Color(0.5, 0.05, 0.05) if wild_variant else Color(0.9, 0.1, 0.1)
			return red
		RatType.GREEN:
			var green := StandardMaterial3D.new()
			green.albedo_color = Color(0.05, 0.5, 0.05) if wild_variant else Color(0.1, 0.9, 0.1)
			return green
		_:
			if wild_variant:
				var normal_wild := StandardMaterial3D.new()
				normal_wild.albedo_color = Color.BLACK
				return normal_wild
			return null


func set_rat_type(r_type: int) -> void:
	rat_type = r_type as RatType
	default_rat_type = rat_type
	_base_material = _get_shared_material(default_rat_type, false)
		
	if not is_wild:
		if _current_buff_material != _base_material:
			_current_buff_material = _base_material
			_apply_material_override(_base_material)

func set_wild(wild: bool) -> void:
	is_wild = wild
	if is_wild:
		add_to_group("wild_rats")
		_wild_timer = -1.0 if wild_lifespan <= 0.0 else wild_lifespan
		state = State.STATIC
		var mat := _get_shared_material(default_rat_type, true)
			
		if mat != _current_buff_material:
			_current_buff_material = mat
			_apply_material_override(mat)
	else:
		if is_in_group("wild_rats"):
			remove_from_group("wild_rats")
		state = State.FOLLOW
		_base_material = _get_shared_material(default_rat_type, false)
		if _current_buff_material != _base_material:
			_current_buff_material = _base_material
			_apply_material_override(_base_material)

func _cache_visual_meshes() -> void:
	_visual_meshes.clear()
	_visual_base_transforms.clear()
	_visual_phase.clear()
	var meshes: Array = find_children("*", "MeshInstance3D")
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi == null:
			continue
		if mi == _blob_mesh:
			continue
		if mi.name in ["Body", "Tail", "Head"]:
			continue
		_visual_meshes.append(mi)
		_visual_base_transforms[mi] = mi.transform
		_visual_phase[mi] = randf() * TAU

func _apply_material_override(mat: Material) -> void:
	for m in _visual_meshes:
		if m:
			m.material_override = mat


func _update_blob_visuals(delta: float) -> void:
	_blob_wobble_time += delta
	for m in _visual_meshes:
		if m == null:
			continue
		var base_t: Transform3D = _visual_base_transforms.get(m, m.transform)
		var phase: float = _visual_phase.get(m, 0.0)
		var t := _blob_wobble_time * _blob_wobble_speed + phase
		var s := 1.0 + sin(t) * _blob_wobble_amp
		var yaw := sin(t * 0.7) * _blob_wobble_rot
		var bob := sin(t * 1.3) * _blob_wobble_bob
		var basis := base_t.basis
		basis = basis.rotated(Vector3.UP, yaw)
		basis = basis.scaled(Vector3(s, s, s))
		var origin := base_t.origin + Vector3(0, bob, 0)
		m.transform = Transform3D(basis, origin)

func _reset_blob_visuals() -> void:
	for m in _visual_meshes:
		if m == null:
			continue
		if _visual_base_transforms.has(m):
			m.transform = _visual_base_transforms[m]

func _process_wild_physics(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * 50
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

	rotation.y += 0.5 * delta
	
	_recruit_timer -= delta
	if _recruit_timer > 0.0:
		return
	_recruit_timer = recruit_interval

	if player == null:
		return
		
	var mgr = _mgr
	if mgr == null or not is_instance_valid(mgr):
		mgr = get_tree().get_first_node_in_group("rat_manager")
	
	if mgr == null or mgr.get("combat_rmb_down") == true:
		return
		
	var dist_sq = _flat_distance_squared(global_position, player.global_position)
	var can_recruit = dist_sq <= recruitment_range * recruitment_range
	
	if not can_recruit and mgr.has_method("get_mouse_world"):
		var cursor_world: Vector3 = mgr.call("get_mouse_world")
		if cursor_world != Vector3.ZERO:
			can_recruit = _flat_distance_squared(global_position, cursor_world) <= recruitment_range * recruitment_range
			
	if not can_recruit and mgr != null and "wild_recruit_by_rats" in mgr and mgr.wild_recruit_by_rats:
		var chain_range := recruitment_range
		if "wild_recruit_by_rats_range" in mgr:
			chain_range = float(mgr.wild_recruit_by_rats_range)
		if "rats" in mgr:
			var chain_range_sq = chain_range * chain_range
			for r in mgr.rats:
				if not is_instance_valid(r):
					continue
				if _flat_distance_squared(global_position, r.global_position) <= chain_range_sq:
					can_recruit = true
					break
					
	if can_recruit:
		add_collision_exception_with(player)
		player.add_collision_exception_with(self )
		set_wild(false)
		if mgr.has_method("register_rat"):
			mgr.register_rat(self )
			if mgr.has_method("build_blob_offsets"):
				mgr.build_blob_offsets()

func _process_wild(delta: float) -> void:
	# This function is now mostly handled by _process and _process_wild_physics
	pass
