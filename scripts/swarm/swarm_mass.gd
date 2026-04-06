extends Node3D
class_name SwarmMass

## Carrion-style creature: central soft-body core + radiating tentacles.
## Tentacles reach toward nearby surfaces via raycasting.
## One unified procedural mesh wraps the entire creature.

signal leash_broken  # kept for API compat

# ── Movement ───────────────────────────────────────────────────────────────────
@export var move_speed: float = 12.0
@export var move_acceleration: float = 25.0

# ── Core Body ──────────────────────────────────────────────────────────────────
@export var core_particle_count: int = 12
@export var core_radius: float = 0.8
@export var core_spring_stiffness: float = 50.0
@export var core_damping: float = 0.88

# ── Tentacles ──────────────────────────────────────────────────────────────────
@export var tentacle_count: int = 7
@export var tentacle_segments: int = 6
@export var tentacle_segment_length: float = 0.5
@export var tentacle_damping: float = 0.90
@export var tentacle_gravity: float = 6.0
@export var tentacle_wave_speed: float = 3.0
@export var tentacle_wave_amplitude: float = 0.15
@export var tentacle_reach_speed: float = 8.0
@export var tentacle_surface_search_dist: float = 4.0

# ── Visual ─────────────────────────────────────────────────────────────────────
@export var core_mesh_segments: int = 20
@export var core_visual_radius: float = 1.0
@export var core_height: float = 0.5
@export var tentacle_base_width: float = 0.35
@export var tentacle_tip_width: float = 0.08
@export var tentacle_radial_segments: int = 6
@export var pulse_speed: float = 2.5
@export var pulse_amount: float = 0.08

# ── State ──────────────────────────────────────────────────────────────────────
var bard: Node3D = null
var rat_count: int = 40

var _center: Vector3 = Vector3.ZERO
var _target: Vector3 = Vector3.ZERO
var _center_velocity: Vector3 = Vector3.ZERO
var _initialized: bool = false

# Core soft-body
var _core_pts: PackedVector3Array = PackedVector3Array()
var _core_pts_old: PackedVector3Array = PackedVector3Array()
var _core_rest_offsets: PackedVector3Array = PackedVector3Array()

# Tentacles — each is an array of Vector3 (chain points)
var _tentacles: Array[PackedVector3Array] = []
var _tentacles_old: Array[PackedVector3Array] = []
var _tentacle_base_angles: PackedFloat32Array = PackedFloat32Array()
var _tentacle_targets: PackedVector3Array = PackedVector3Array()  # Surface target per tentacle
var _tentacle_has_target: Array[bool] = []

# Mesh
var _mesh_inst: MeshInstance3D = null
var _array_mesh: ArrayMesh = null
var _material: ShaderMaterial = null


func initialize(start_pos: Vector3) -> void:
	_center = start_pos + Vector3(0, 0.3, 0)
	_target = _center
	_center_velocity = Vector3.ZERO
	_init_core()
	_init_tentacles()
	_init_mesh()
	_initialized = true


func _physics_process(delta: float) -> void:
	if not _initialized:
		return
	_update_target()
	_move_center(delta)
	_simulate_core(delta)
	_simulate_tentacles(delta)
	_rebuild_mesh()


# ══════════════════════════════════════════════════════════════════════════════
# CORE SOFT-BODY — ring of particles around center
# ══════════════════════════════════════════════════════════════════════════════

func _init_core() -> void:
	_core_pts.resize(core_particle_count)
	_core_pts_old.resize(core_particle_count)
	_core_rest_offsets.resize(core_particle_count)

	for i in range(core_particle_count):
		var angle := float(i) / float(core_particle_count) * TAU
		var offset := Vector3(cos(angle) * core_radius, 0.0, sin(angle) * core_radius)
		_core_rest_offsets[i] = offset
		_core_pts[i] = _center + offset
		_core_pts_old[i] = _core_pts[i]


func _simulate_core(delta: float) -> void:
	for i in range(core_particle_count):
		var cur := _core_pts[i]
		var old := _core_pts_old[i]
		var vel := (cur - old) * core_damping

		# Spring toward rest position relative to center
		var rest_pos := _center + _core_rest_offsets[i]
		var to_rest := rest_pos - cur
		vel += to_rest * core_spring_stiffness * delta

		# Gravity
		vel.y -= 12.0 * delta

		_core_pts_old[i] = cur
		_core_pts[i] = cur + vel

		# Floor clamp
		if _core_pts[i].y < 0.05:
			_core_pts[i].y = 0.05


# ══════════════════════════════════════════════════════════════════════════════
# TENTACLES — Verlet chains radiating from core, reaching for surfaces
# ══════════════════════════════════════════════════════════════════════════════

func _init_tentacles() -> void:
	_tentacles.clear()
	_tentacles_old.clear()
	_tentacle_base_angles.resize(tentacle_count)
	_tentacle_targets.resize(tentacle_count)
	_tentacle_has_target.clear()

	for ti in range(tentacle_count):
		var angle := float(ti) / float(tentacle_count) * TAU + randf_range(-0.2, 0.2)
		_tentacle_base_angles[ti] = angle

		var chain := PackedVector3Array()
		var chain_old := PackedVector3Array()
		chain.resize(tentacle_segments)
		chain_old.resize(tentacle_segments)

		var dir := Vector3(cos(angle), 0.0, sin(angle))
		for si in range(tentacle_segments):
			var pt := _center + dir * (core_radius + float(si) * tentacle_segment_length)
			pt.y = _center.y
			chain[si] = pt
			chain_old[si] = pt

		_tentacles.append(chain)
		_tentacles_old.append(chain_old)
		_tentacle_targets[ti] = Vector3.ZERO
		_tentacle_has_target.append(false)


func _simulate_tentacles(delta: float) -> void:
	var time := float(Time.get_ticks_msec()) * 0.001
	var world := get_world_3d()
	var ss: PhysicsDirectSpaceState3D = null
	if world:
		ss = world.direct_space_state

	for ti in range(tentacle_count):
		var chain := _tentacles[ti]
		var chain_old := _tentacles_old[ti]
		var base_angle := _tentacle_base_angles[ti]

		# Pin base to core edge
		var base_dir := Vector3(cos(base_angle), 0.0, sin(base_angle))
		chain[0] = _center + base_dir * core_radius
		chain[0].y = maxf(chain[0].y, 0.1)

		# Search for nearby surface to reach toward
		if ss and not _tentacle_has_target[ti]:
			_search_surface(ti, ss, base_dir)

		# Verlet integration for chain segments
		for si in range(1, tentacle_segments):
			var cur := chain[si]
			var old := chain_old[si]
			var vel := (cur - old) * tentacle_damping

			# Gravity
			vel.y -= tentacle_gravity * delta

			# Waviness for organic movement
			var wave_offset := sin(time * tentacle_wave_speed + float(si) * 1.5 + float(ti) * 2.0) * tentacle_wave_amplitude
			var perp := Vector3(-base_dir.z, 0.0, base_dir.x)
			vel += perp * wave_offset * delta * 3.0

			# If we have a surface target, tip reaches toward it
			if _tentacle_has_target[ti] and si == tentacle_segments - 1:
				var to_target := _tentacle_targets[ti] - cur
				vel += to_target.normalized() * tentacle_reach_speed * delta
				# Release target if too far or if we reached it
				if to_target.length() < 0.2 or to_target.length() > tentacle_surface_search_dist * 1.5:
					_tentacle_has_target[ti] = false

			chain_old[si] = cur
			chain[si] = cur + vel

		# Distance constraints
		for _iter in range(3):
			chain[0] = _center + base_dir * core_radius
			chain[0].y = maxf(chain[0].y, 0.1)

			for si in range(tentacle_segments - 1):
				var a := chain[si]
				var b := chain[si + 1]
				var diff := b - a
				var dist := diff.length()
				if dist < 0.001:
					continue
				if dist > tentacle_segment_length:
					var correction := diff * (1.0 - tentacle_segment_length / dist) * 0.5
					if si > 0:
						chain[si] = chain[si] + correction
					chain[si + 1] = chain[si + 1] - correction

		# Floor constraint
		for si in range(tentacle_segments):
			chain[si].y = maxf(chain[si].y, 0.03)

		_tentacles[ti] = chain
		_tentacles_old[ti] = chain_old


func _search_surface(ti: int, ss: PhysicsDirectSpaceState3D, base_dir: Vector3) -> void:
	# Raycast outward from tentacle base to find a surface to reach for
	var origin := _center + base_dir * core_radius
	origin.y = _center.y

	# Cast in the tentacle's general direction
	var ray_end := origin + base_dir * tentacle_surface_search_dist
	# Also cast slightly downward to find the floor edge
	ray_end.y -= 0.5

	var query := PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collision_mask = 1 | 8  # Floor + Walls
	query.collide_with_areas = false
	var hit := ss.intersect_ray(query)

	if hit:
		_tentacle_targets[ti] = hit.position as Vector3
		_tentacle_has_target[ti] = true
	else:
		# Random chance to just wave around
		if randf() < 0.02:
			_tentacle_has_target[ti] = false


# ══════════════════════════════════════════════════════════════════════════════
# MOUSE TARGET
# ══════════════════════════════════════════════════════════════════════════════

func _update_target() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mp := get_viewport().get_mouse_position()
	var ro := cam.project_ray_origin(mp)
	var rd := cam.project_ray_normal(mp)
	var world := get_world_3d()
	if world == null:
		return
	var ss := world.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ro, ro + rd * 200.0)
	query.collision_mask = 1 | 8
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := ss.intersect_ray(query)
	if hit:
		_target = hit.position as Vector3 + Vector3(0, 0.3, 0)
	elif abs(rd.y) > 0.001:
		var t := -ro.y / rd.y
		if t > 0.0:
			_target = ro + rd * t + Vector3(0, 0.3, 0)


func _move_center(delta: float) -> void:
	var to_target := _target - _center
	var dist := to_target.length()
	if dist > 0.05:
		var desired := to_target.normalized() * move_speed
		_center_velocity = _center_velocity.lerp(desired, 1.0 - exp(-move_acceleration * delta))
	else:
		_center_velocity = _center_velocity.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
	_center += _center_velocity * delta
	_center.y = maxf(_center.y, 0.3)


# ══════════════════════════════════════════════════════════════════════════════
# MESH GENERATION — core blob + tentacle tubes = one mesh
# ══════════════════════════════════════════════════════════════════════════════

func _init_mesh() -> void:
	_material = ShaderMaterial.new()
	_material.shader = _create_shader()
	_array_mesh = ArrayMesh.new()
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = _array_mesh
	_mesh_inst.material_override = _material
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_mesh_inst.top_level = true
	add_child(_mesh_inst)


func _create_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back;

uniform vec3 flesh_dark : source_color = vec3(0.15, 0.08, 0.06);
uniform vec3 flesh_mid : source_color = vec3(0.35, 0.18, 0.12);
uniform vec3 flesh_light : source_color = vec3(0.50, 0.25, 0.18);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.7;
uniform float time_val = 0.0;

void fragment() {
	// Procedural noise for fleshy variation
	float n1 = fract(sin(dot(VERTEX.xz * 7.0, vec2(12.9898, 78.233))) * 43758.5453);
	float n2 = fract(sin(dot(VERTEX.xz * 15.0 + 5.1, vec2(39.346, 11.135))) * 23421.631);

	vec3 col = mix(flesh_dark, flesh_mid, smoothstep(0.2, 0.8, n1));
	col = mix(col, flesh_light, smoothstep(0.6, 0.95, n2) * 0.4);

	// Wet/slimy fresnel sheen
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col = mix(col, flesh_light * 1.3, fresnel * 0.3);

	// Animate subtle color shifts
	float pulse = sin(time_val * 2.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0) * 0.02;
	col += vec3(pulse, pulse * 0.5, 0.0);

	ALBEDO = col;
	ROUGHNESS = roughness_val * (1.0 - fresnel * 0.3);
	METALLIC = fresnel * 0.15;
	EMISSION = flesh_dark * 0.08 * (1.0 + fresnel * 0.5);
}
"""
	return shader


func _rebuild_mesh() -> void:
	var time := float(Time.get_ticks_msec()) * 0.001
	if _material:
		_material.set_shader_parameter("time_val", time)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()

	# ── 1. Core blob mesh (dome on floor) ──
	_build_core_mesh(verts, norms, indices, time)

	# ── 2. Tentacle tube meshes ──
	for ti in range(tentacle_count):
		_build_tentacle_mesh(ti, verts, norms, indices, time)

	if verts.size() < 3:
		return

	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = indices

	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


func _build_core_mesh(verts: PackedVector3Array, norms: PackedVector3Array,
		indices: PackedInt32Array, time: float) -> void:
	var base_idx := verts.size()
	var segs := core_mesh_segments

	var cx := _center.x
	var cz := _center.z
	var floor_y := maxf(_center.y - core_height * 0.5, 0.03)

	# Compute per-angle radius from core particles
	var angle_radii: PackedFloat32Array = PackedFloat32Array()
	angle_radii.resize(segs)
	for si in range(segs):
		var angle := float(si) / float(segs) * TAU
		var best_r := core_visual_radius
		for pi in range(core_particle_count):
			var p_rel := _core_pts[pi] - _center
			var p_angle := atan2(p_rel.z, p_rel.x)
			var angle_diff := absf(fmod(angle - p_angle + PI * 3.0, TAU) - PI)
			if angle_diff < PI / float(core_particle_count) * 2.0:
				var p_r := Vector2(p_rel.x, p_rel.z).length()
				best_r = maxf(best_r, p_r + 0.3)
		angle_radii[si] = best_r + sin(time * pulse_speed + angle * 2.0) * pulse_amount

	# Hemisphere dome: 5 latitude rings + 1 pole vertex on top
	var lat_count := 5  # Number of latitude rings (not counting pole)
	# lat 0 = bottom edge, lat 4 = near top, then pole vertex

	# Generate ring vertices
	for lat in range(lat_count):
		var t := float(lat) / float(lat_count)  # 0=bottom, 1=near top
		# Height follows a hemisphere curve
		var y := floor_y + sin(t * PI * 0.5) * core_height
		# Width shrinks toward top (hemisphere profile)
		var width_mult := cos(t * PI * 0.5)
		# Make the bottom slightly narrower than mid for a rounded base
		if lat == 0:
			width_mult *= 0.85

		for si in range(segs):
			var angle := float(si) / float(segs) * TAU
			var r := angle_radii[si] * width_mult

			var vx := cx + cos(angle) * r
			var vz := cz + sin(angle) * r

			# Normal: blend outward + up based on latitude
			var outward := Vector3(cos(angle), 0.0, sin(angle))
			var normal := (outward * (1.0 - t) + Vector3.UP * t).normalized()

			verts.append(Vector3(vx, y, vz))
			norms.append(normal)

	# Pole vertex at the very top
	var pole_idx := verts.size()
	verts.append(Vector3(cx, floor_y + core_height, cz))
	norms.append(Vector3.UP)

	# Side triangles between latitude rings
	for lat in range(lat_count - 1):
		for si in range(segs):
			var nxt := (si + 1) % segs
			var a := base_idx + lat * segs + si
			var b := base_idx + lat * segs + nxt
			var c := base_idx + (lat + 1) * segs + si
			var d := base_idx + (lat + 1) * segs + nxt
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)

	# Top cap: triangles from last ring to pole vertex
	var top_ring_base := base_idx + (lat_count - 1) * segs
	for si in range(segs):
		var nxt := (si + 1) % segs
		indices.append(top_ring_base + si)
		indices.append(pole_idx)
		indices.append(top_ring_base + nxt)

	# Bottom cap: flat circle at floor level
	var bot_center_idx := verts.size()
	verts.append(Vector3(cx, floor_y, cz))
	norms.append(Vector3.DOWN)
	for si in range(segs):
		var nxt := (si + 1) % segs
		indices.append(bot_center_idx)
		indices.append(base_idx + nxt)
		indices.append(base_idx + si)


func _build_tentacle_mesh(ti: int, verts: PackedVector3Array, norms: PackedVector3Array,
		indices: PackedInt32Array, time: float) -> void:
	var chain := _tentacles[ti]
	if chain.size() < 2:
		return

	var base_idx := verts.size()
	var rs := tentacle_radial_segments

	for si in range(chain.size()):
		var pt := chain[si]
		var t := float(si) / float(chain.size() - 1)

		# Width tapers from base to tip
		var width := lerpf(tentacle_base_width, tentacle_tip_width, t)
		# Organic pulse
		width += sin(time * pulse_speed * 1.5 + t * 4.0 + float(ti) * 2.0) * 0.03

		# Tangent direction
		var tangent: Vector3
		if si == 0:
			tangent = (chain[1] - chain[0])
		elif si == chain.size() - 1:
			tangent = (chain[si] - chain[si - 1])
		else:
			tangent = (chain[si + 1] - chain[si - 1])
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()

		var ref_up := Vector3.UP
		if absf(tangent.dot(ref_up)) > 0.95:
			ref_up = Vector3.RIGHT
		var right := ref_up.cross(tangent).normalized()
		var up := tangent.cross(right).normalized()

		for ri in range(rs):
			var angle := float(ri) / float(rs) * TAU
			var local_dir := (right * cos(angle) + up * sin(angle))

			# Bumpy surface
			var bump := sin(angle * 3.0 + time * 2.0 + t * 8.0) * 0.02
			var r := width + bump

			verts.append(pt + local_dir * r)
			norms.append(local_dir.normalized())

	# Side triangles
	for si in range(chain.size() - 1):
		for ri in range(rs):
			var nxt := (ri + 1) % rs
			var a := base_idx + si * rs + ri
			var b := base_idx + si * rs + nxt
			var c := base_idx + (si + 1) * rs + ri
			var d := base_idx + (si + 1) * rs + nxt
			indices.append(a)
			indices.append(c)
			indices.append(b)
			indices.append(b)
			indices.append(c)
			indices.append(d)

	# Tip cap
	var tip_center := verts.size()
	var last_pt := chain[chain.size() - 1]
	verts.append(last_pt)
	var tip_normal := (chain[chain.size() - 1] - chain[chain.size() - 2]).normalized()
	norms.append(tip_normal)
	var tip_base := base_idx + (chain.size() - 1) * rs
	for ri in range(rs):
		var nxt := (ri + 1) % rs
		indices.append(tip_center)
		indices.append(tip_base + ri)
		indices.append(tip_base + nxt)


# ══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ══════════════════════════════════════════════════════════════════════════════

func get_rat_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for pt in _core_pts:
		positions.append(pt)
	for chain in _tentacles:
		for pt in chain:
			positions.append(pt)
	return positions


func get_head_position() -> Vector3:
	return _center
