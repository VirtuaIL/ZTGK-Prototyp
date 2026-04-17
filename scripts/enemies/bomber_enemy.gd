extends "res://scripts/enemies/enemy.gd"

const BombScene = preload("res://scenes/projectiles/bomb_projectile.tscn")

@export var bomb_range: float = 40.0
@export var bomb_min_range: float = 8.0
@export var bomb_cooldown: float = 5.0
@export var bomb_windup: float = 1.2
@export var bomb_flight_time: float = 1.1
@export var bomb_arc_height: float = 9.0
@export var bomb_blast_radius: float = 3.5

var _bomb_timer: float = 0.0
var _pending_bomb_target: Vector3 = Vector3.ZERO
var _telegraph_marker: MeshInstance3D = null
var _telegraph_time_total: float = 0.0
var _telegraph_time_left: float = 0.0

func _ready() -> void:
	super._ready()
	attack_range = bomb_range
	attack_cooldown = bomb_cooldown
	attack_delay = bomb_windup
	movement_pattern = MovePattern.KITE
	kite_preferred_range = bomb_min_range + 2.0
	strafe_bias = 0.6
	wall_avoidance_force = 3.6

func _process_attack(delta: float) -> void:
	# Override melee logic: bomber keeps distance and throws bombs at rats.
	var mgr = get_tree().get_first_node_in_group("rat_manager")
	if mgr == null or mgr.rats.is_empty():
		_clear_telegraph()
		current_attack = AttackType.NONE
		if attack_marker:
			attack_marker.visible = false
		ai_state = AIState.WANDER
		return

	var target_rat = _pick_target_rat(mgr)
	if target_rat == null:
		_clear_telegraph()
		current_attack = AttackType.NONE
		if attack_marker:
			attack_marker.visible = false
		ai_state = AIState.WANDER
		return

	var target_pos := _get_ground_target(target_rat.global_position)
	var dist := global_position.distance_to(target_pos)
	if dist < bomb_min_range:
		_clear_telegraph()
		current_attack = AttackType.NONE
		if attack_marker:
			attack_marker.visible = false
		# Too close: keep chasing to maintain distance
		ai_state = AIState.CHASE
		return

	_bomb_timer -= delta
	_update_telegraph_color(delta)
	if _bomb_timer <= 0.0:
		_pending_bomb_target = target_pos
		_create_telegraph(_pending_bomb_target, bomb_windup + bomb_flight_time)
		attack_prepare_timer = attack_delay
		_bomb_timer = bomb_cooldown

	if attack_prepare_timer > 0.0:
		attack_prepare_timer -= delta
		if attack_prepare_timer <= 0.0:
			_throw_bomb(_pending_bomb_target)

func _throw_bomb(target_pos: Vector3) -> void:
	if BombScene == null:
		return
	var bomb = BombScene.instantiate()
	get_parent().add_child(bomb)
	var start_pos := global_position + Vector3(0, 1.6, 0)
	if bomb.has_method("setup"):
		bomb.setup(start_pos, target_pos)
	bomb.arc_height = bomb_arc_height
	bomb.blast_radius = bomb_blast_radius
	bomb.flight_time = bomb_flight_time

func _create_telegraph(pos: Vector3, duration: float) -> void:
	_clear_telegraph()
	_telegraph_marker = MeshInstance3D.new()
	_telegraph_marker.layers = 2
	var mesh := CylinderMesh.new()
	mesh.top_radius = bomb_blast_radius
	mesh.bottom_radius = bomb_blast_radius
	mesh.height = 0.05
	_telegraph_marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_telegraph_marker.material_override = mat
	var world_pos := pos
	world_pos.y += 0.02
	_telegraph_marker.global_position = world_pos
	var current_scene := get_tree().current_scene
	if current_scene:
		current_scene.add_child(_telegraph_marker)
	else:
		add_child(_telegraph_marker)
	_telegraph_time_total = max(0.01, duration)
	_telegraph_time_left = _telegraph_time_total

func _clear_telegraph() -> void:
	if _telegraph_marker:
		_telegraph_marker.queue_free()
		_telegraph_marker = null
	_telegraph_time_total = 0.0
	_telegraph_time_left = 0.0

func _update_telegraph_color(delta: float) -> void:
	if _telegraph_marker == null:
		return
	if _telegraph_time_total <= 0.0:
		return
	_telegraph_time_left = max(0.0, _telegraph_time_left - delta)
	var t := 1.0 - (_telegraph_time_left / _telegraph_time_total) # 0->1
	var col := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.2, 0.1), t)
	var pulse := 1.0 + sin(t * TAU * 2.0) * 0.08
	_telegraph_marker.scale = Vector3(pulse, 1.0, pulse)
	var mat := _telegraph_marker.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(col.r, col.g, col.b, 0.45 + 0.25 * t)
	if _telegraph_time_left <= 0.0:
		_clear_telegraph()

func _pick_target_rat(mgr: Node) -> Node3D:
	var rats = mgr.rats
	if rats.is_empty():
		return null
	return rats[randi() % rats.size()]

func _get_ground_target(pos: Vector3) -> Vector3:
	var origin := pos + Vector3.UP * 5.0
	var end := pos + Vector3.DOWN * 15.0
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = 1 | (1 << 8)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	return pos
