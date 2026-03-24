extends CharacterBody3D
class_name bossTurret

# The ID used by buttons to target this entity
@export var doorId: int = 0

enum State { IDLE, LASER_SWEEP, PROJECTILE_BARRAGE, ENEMY_DEPLOY, RETREAT_HEAL, DEAD }

var current_state: State = State.IDLE

@export var is_active: bool = false

@export var mode_switch_time: float = 2.0
@export var sweep_speed: float = 2.0 # radians per sec
@export var damage_per_second: float = 34.0
@export var attack_range: float = 50.0

@export var barrage_wait_time: float = 1.0
@export var barrage_points_count: int = 4
@export var barrage_fire_rate: float = 0.4
@export var projectile_speed: float = 20.0
@export var fly_speed: float = 8.0 # Units per second
@export var y_move_speed: float = 3.0
@export var turn_speed: float = 5.0

@export var deploy_wait_time: float = 1.0
@export var deploy_enemy_count: int = 3

@export var max_health: float = 1000.0
var health: float = max_health

var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")
var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")

var mode_timer: float = 0.0

# Laser Sweep State
var sweep_rotation_accumulated: float = 0.0
var laser_mesh_front: MeshInstance3D = null
var laser_mesh_back: MeshInstance3D = null
var target_y: float = 0.0
var original_y: float = 0.0
var original_position: Vector3 = Vector3.ZERO
var sweep_phase: int = 0

# Barrage State
var barrage_phase: int = 0
var barrage_points_visited: int = 0
var barrage_wait_timer: float = 0.0
var barrage_fire_timer: float = 0.0
var current_nav_node: Node3D = null
var nav_nodes: Array[Node] = []

# Deploy State
var deploy_phase: int = 0
var deploy_wait_timer: float = 0.0
var deploy_nodes: Array[Node] = []
var current_deploy_node: Node3D = null

# Retreat State
var retreat_phase: int = 0
var current_retreat_target: Node3D = null
var retreat_timeout_timer: float = 0.0
var heal_cooldown: float = 0.0
var _last_health: float = 0.0

# Health UI
var canvas_layer: CanvasLayer
var boss_hp_bar: ProgressBar

var player_node: Node3D = null

@onready var fire_point: Vector3 = Vector3(0, 0.7, 0)
@onready var original_laser_mesh: MeshInstance3D = $LaserMesh

var next_state: State = State.LASER_SWEEP
var _was_active: bool = false

func _ready() -> void:
	add_to_group("bosses")
	collision_layer = 4
	collision_mask = 31
	
	original_position = global_position
	original_y = original_position.y
	
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_node = players[0]
	else:
		player_node = get_node_or_null("/root/Main/Player")
		
	health = max_health
	_create_boss_hp_ui()
		
	# Setup NAV nodes
	find_nav_nodes(get_tree().current_scene)
	
	# Laser setup
	laser_mesh_front = original_laser_mesh
	if laser_mesh_front:
		laser_mesh_front.visible = false
		
		laser_mesh_back = laser_mesh_front.duplicate()
		laser_mesh_back.name = "LaserMeshBack"
		add_child(laser_mesh_back)
		laser_mesh_back.visible = false
	
	mode_timer = mode_switch_time
	current_state = State.IDLE

func open() -> void:
	print("BOSS ACTIVATED")
	self.is_active = true
	
func close() -> void:
	pass
	
func find_nav_nodes(node: Node) -> void:
	if not node: return
	if node is bossNavNode:
		nav_nodes.append(node)
	if node is bossEnemyDeployPoint:
		deploy_nodes.append(node)
	for child in node.get_children():
		find_nav_nodes(child)

func _physics_process(delta: float) -> void:
	if not is_active:
		return
		
	# Fall safe check
	if global_position.y < -50.0:
		global_position = original_position
		
	if not player_node:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
		return

	if not _was_active:
		_was_active = true
		if canvas_layer:
			canvas_layer.visible = true

	if heal_cooldown > 0.0:
		heal_cooldown -= delta

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.LASER_SWEEP:
			_process_laser_sweep(delta)
		State.PROJECTILE_BARRAGE:
			_process_projectile_barrage(delta)
		State.ENEMY_DEPLOY:
			_process_enemy_deploy(delta)
		State.RETREAT_HEAL:
			_process_retreat_heal(delta)

func _process_idle(delta: float) -> void:
	_aim_at_player(delta)
	mode_timer -= delta
	if mode_timer <= 0:
		if health < max_health * 0.7 and heal_cooldown <= 0.0:
			var crystals = get_tree().get_nodes_in_group("healing_crystals")
			if crystals.size() > 0:
				var closest_crystal: Node3D = null
				var closest_dist: float = INF
				for c in crystals:
					var d = global_position.distance_to(c.global_position)
					if d < closest_dist:
						closest_dist = d
						closest_crystal = c
				
				if closest_crystal:
					current_retreat_target = closest_crystal
					current_state = State.RETREAT_HEAL
					retreat_phase = 0
					retreat_timeout_timer = 4.0 # Max 4 seconds waiting for heal
					return
					
		_transition_to_next_mode()

func _transition_to_next_mode() -> void:
	if next_state == State.LASER_SWEEP:
		current_state = State.LASER_SWEEP
		next_state = State.PROJECTILE_BARRAGE
		_start_laser_sweep()
	elif next_state == State.PROJECTILE_BARRAGE:
		current_state = State.PROJECTILE_BARRAGE
		next_state = State.ENEMY_DEPLOY
		_start_projectile_barrage()
	elif next_state == State.ENEMY_DEPLOY:
		current_state = State.ENEMY_DEPLOY
		next_state = State.LASER_SWEEP
		_start_enemy_deploy()

# --- LASER SWEEP ---
func _start_laser_sweep() -> void:
	sweep_phase = 0
	sweep_rotation_accumulated = 0.0
	target_y = player_node.global_position.y
	if laser_mesh_front: laser_mesh_front.visible = false
	if laser_mesh_back: laser_mesh_back.visible = false

func _process_laser_sweep(delta: float) -> void:
	if sweep_phase == 0: # Descending
		var step = y_move_speed * delta
		global_position.y = move_toward(global_position.y, target_y, step)
		if is_equal_approx(global_position.y, target_y):
			sweep_phase = 1 # Start sweeping
	elif sweep_phase == 1: # Sweeping
		var rot_step = sweep_speed * delta
		rotation.y += rot_step
		sweep_rotation_accumulated += rot_step
		
		var front_dir = -global_transform.basis.z.normalized()
		var back_dir = global_transform.basis.z.normalized()
		
		_process_laser(delta, laser_mesh_front, front_dir)
		_process_laser(delta, laser_mesh_back, back_dir)
		
		if sweep_rotation_accumulated >= 2 * PI:
			if laser_mesh_front: laser_mesh_front.visible = false
			if laser_mesh_back: laser_mesh_back.visible = false
			sweep_phase = 2 # Ascending
			rotation.y = fmod(rotation.y, 2 * PI) # normalize
	elif sweep_phase == 2: # Ascending
		var step = y_move_speed * delta
		global_position.y = move_toward(global_position.y, original_y, step)
		if is_equal_approx(global_position.y, original_y):
			current_state = State.IDLE
			mode_timer = mode_switch_time

func _process_laser(delta: float, mesh: MeshInstance3D, dir: Vector3) -> void:
	if not mesh: return
	var space_state := get_world_3d().direct_space_state
	
	var start_pos = global_position + fire_point
	start_pos += dir * 0.01
	var ray_end = start_pos + dir * attack_range
	
	var query := PhysicsRayQueryParameters3D.create(start_pos, ray_end)
	query.collision_mask = 15 | (1 << 8) # Floor (1) + Player (2) + Movable (4) + Walls (8) + RatStructures (9)
	query.exclude = [self.get_rid()]
	
	var hit := space_state.intersect_ray(query)
	
	if hit:
		var hit_pos: Vector3 = hit.position
		_update_laser_visuals(mesh, start_pos, hit_pos)
		if hit.collider.has_method("receive_laser"):
			hit.collider.receive_laser(delta)
		elif hit.collider.has_method("die"):
			hit.collider.die()
	else:
		_update_laser_visuals(mesh, start_pos, ray_end)

func _update_laser_visuals(mesh: MeshInstance3D, start_pos: Vector3, end_pos: Vector3) -> void:
	mesh.visible = true
	var distance = start_pos.distance_to(end_pos)
	
	if distance < 0.001:
		return
		
	var mid_point = start_pos.lerp(end_pos, 0.5)
	mesh.global_position = mid_point
	mesh.basis = Basis()
	
	var dir = (end_pos - start_pos).normalized()
	var up = Vector3.UP
	if abs(dir.y) > 0.99:
		up = Vector3.RIGHT
		
	mesh.look_at(end_pos, up)
	mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	mesh.scale = Vector3(1.0, distance / 2.0, 1.0)

# --- PROJECTILE BARRAGE ---
func _start_projectile_barrage() -> void:
	barrage_phase = 0
	barrage_points_visited = 0
	current_nav_node = null
	_pick_next_nav_node()

func _pick_next_nav_node() -> void:
	if nav_nodes.size() > 0:
		current_nav_node = nav_nodes.pick_random()
	barrage_wait_timer = barrage_wait_time

func _process_projectile_barrage(delta: float) -> void:
	if nav_nodes.is_empty():
		current_state = State.IDLE
		mode_timer = mode_switch_time
		return
		
	if barrage_phase == 0:
		var target_pos = original_position
		if current_nav_node:
			target_pos = current_nav_node.global_position
			
		var dist = global_position.distance_to(target_pos)
		
		if dist > 0.1:
			var step = fly_speed * delta
			global_position = global_position.move_toward(target_pos, step)
		else:
			global_position = target_pos
			barrage_wait_timer -= delta
			if barrage_wait_timer <= 0:
				barrage_points_visited += 1
				if barrage_points_visited >= barrage_points_count:
					barrage_phase = 1 # Return home
					current_nav_node = null
				else:
					_pick_next_nav_node()
					
		_aim_at_player(delta)
		barrage_fire_timer -= delta
		if barrage_fire_timer <= 0:
			_shoot()
			barrage_fire_timer = barrage_fire_rate
			
	elif barrage_phase == 1:
		var target_pos = original_position
		var dist = global_position.distance_to(target_pos)
		
		if dist > 0.1:
			var step = fly_speed * delta
			global_position = global_position.move_toward(target_pos, step)
			
			_aim_at_player(delta)
			barrage_fire_timer -= delta
			if barrage_fire_timer <= 0:
				_shoot()
				barrage_fire_timer = barrage_fire_rate
		else:
			global_position = target_pos
			current_state = State.IDLE
			mode_timer = mode_switch_time

func _aim_at_player(delta: float) -> void:
	var target_pos = player_node.global_position
	target_pos.y = global_position.y
	
	var dir = (target_pos - global_position).normalized()
	if dir.length() > 0.1:
		var target_angle = atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)

func _shoot() -> void:
	if not projectile_scene:
		return
		
	var target_pos = player_node.global_position
	target_pos.y += 0.5 
	
	var fire_origin = global_position + fire_point
	var dir = (target_pos - fire_origin).normalized()
	
	var proj = projectile_scene.instantiate()
	get_parent().add_child(proj)
	

	
	proj.global_position = fire_origin + dir * 0.8
	proj.velocity = dir * projectile_speed

func set_highlight(enabled: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			if child.name == "LaserMesh" or child.name == "LaserMeshBack": continue
			
			if enabled:
				if child.material_overlay: continue
				var highlight_mat = StandardMaterial3D.new()
				highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				highlight_mat.albedo_color = Color.YELLOW
				highlight_mat.cull_mode = BaseMaterial3D.CULL_FRONT
				highlight_mat.no_depth_test = true
				highlight_mat.grow = true
				highlight_mat.grow_amount = 0.03
				child.material_overlay = highlight_mat
			else:
				child.material_overlay = null

func take_damage(amount: float, source_id: int = -1, hit_pos: Vector3 = Vector3.ZERO) -> void:
	if current_state == State.DEAD:
		return
		
	health -= amount
	health = maxf(health, 0.0)
	
	if boss_hp_bar:
		boss_hp_bar.value = health
		boss_hp_bar.max_value = max_health
		
	if amount > 0:
		_flash_hit()
	
	if health <= 0.0:
		_die()

func _flash_hit() -> void:
	var body: MeshInstance3D = $Body as MeshInstance3D
	if body and body.material_overlay == null:
		var flash_mat = StandardMaterial3D.new()
		flash_mat.albedo_color = Color(1.0, 1.0, 1.0) # White flash
		flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		body.material_overlay = flash_mat
		var tween = create_tween()
		tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.15)
		tween.tween_callback(func(): body.material_overlay = null)

func _die() -> void:
	current_state = State.DEAD
	collision_layer = 0
	collision_mask = 0
	if canvas_layer:
		canvas_layer.queue_free()
	if laser_mesh_front:
		laser_mesh_front.visible = false
	if laser_mesh_back:
		laser_mesh_back.visible = false
		
	# Explode visually
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.5).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func _create_boss_hp_ui() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	add_child(canvas_layer)
	
	canvas_layer.visible = is_active
	
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_left", 200)
	margin.add_theme_constant_override("margin_right", 200)
	canvas_layer.add_child(margin)
	
	boss_hp_bar = ProgressBar.new()
	boss_hp_bar.custom_minimum_size = Vector2(0, 30)
	boss_hp_bar.show_percentage = false
	boss_hp_bar.max_value = max_health
	boss_hp_bar.value = health
	
	var style_box_bg = StyleBoxFlat.new()
	style_box_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	style_box_bg.border_width_left = 2
	style_box_bg.border_width_top = 2
	style_box_bg.border_width_right = 2
	style_box_bg.border_width_bottom = 2
	style_box_bg.border_color = Color(0, 0, 0, 1)
	
	var style_box_fill = StyleBoxFlat.new()
	style_box_fill.bg_color = Color(0.8, 0.15, 0.15, 1.0) # Red
	
	boss_hp_bar.add_theme_stylebox_override("background", style_box_bg)
	boss_hp_bar.add_theme_stylebox_override("fill", style_box_fill)
	
	margin.add_child(boss_hp_bar)
	
	var label = Label.new()
	label.text = "BOSS"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	boss_hp_bar.add_child(label)

# --- ENEMY DEPLOY ---
func _start_enemy_deploy() -> void:
	deploy_phase = 0
	current_deploy_node = null
	if deploy_nodes.size() > 0:
		current_deploy_node = deploy_nodes.pick_random()
	deploy_wait_timer = deploy_wait_time

func _process_enemy_deploy(delta: float) -> void:
	if deploy_nodes.is_empty():
		current_state = State.IDLE
		mode_timer = mode_switch_time
		return
		
	if deploy_phase == 0:
		var target_pos = original_position
		if current_deploy_node:
			target_pos = current_deploy_node.global_position
			
		var dist = global_position.distance_to(target_pos)
		if dist > 0.1:
			var step = fly_speed * delta
			global_position = global_position.move_toward(target_pos, step)
			_aim_at_player(delta)
		else:
			global_position = target_pos
			deploy_wait_timer -= delta
			if deploy_wait_timer <= 0:
				_spawn_enemies()
				deploy_phase = 1 # Return home
	
	elif deploy_phase == 1:
		var target_pos = original_position
		var dist = global_position.distance_to(target_pos)
		
		if dist > 0.1:
			var step = fly_speed * delta
			global_position = global_position.move_toward(target_pos, step)
			_aim_at_player(delta)
		else:
			global_position = target_pos
			current_state = State.IDLE
			mode_timer = mode_switch_time

func _spawn_enemies() -> void:
	if not enemy_scene or not current_deploy_node:
		return
		
	var parent = get_parent()
	var center_pos = global_position
	
	for i in range(deploy_enemy_count):
		var enemy = enemy_scene.instantiate()
		parent.add_child(enemy)
		
		# Scatter them in a circle around the deploy point
		var angle = (float(i) / deploy_enemy_count) * 2.0 * PI
		var radius = 2.0
		var offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		
		var spawn_pos = center_pos + offset
		spawn_pos.y = center_pos.y # Strictly same Y-level as turret's height there
		enemy.global_position = spawn_pos

# --- RETREAT HEAL ---
func _process_retreat_heal(delta: float) -> void:
	if retreat_phase < 2 and (not current_retreat_target or not is_instance_valid(current_retreat_target)):
		retreat_phase = 2 # Crystal destroyed, return to fight or abort
		
	if retreat_phase == 0: # Moving to crystal
		if current_retreat_target:
			var target_pos = current_retreat_target.global_position
			target_pos.y = original_position.y # Try to maintain normal flight height if possible
			var dist = global_position.distance_to(target_pos)
			
			if dist > 3.0: 
				var step = fly_speed * delta
				global_position = global_position.move_toward(target_pos, step)
				_aim_at_player(delta)
			else:
				retreat_phase = 1 # Reached, now we wait
				_last_health = health
				retreat_timeout_timer = 4.0
			
	elif retreat_phase == 1: # Waiting for heal
		_aim_at_player(delta)
		
		# Reset timeout if being healed
		if health > _last_health:
			retreat_timeout_timer = 4.0
		else:
			retreat_timeout_timer -= delta
			
		_last_health = health
		
		if health >= max_health - 1.0 or retreat_timeout_timer <= 0.0:
			retreat_phase = 2 # fully healed or timed out, returning
			
	elif retreat_phase == 2: # Returning home
		var target_pos = original_position
		var dist = global_position.distance_to(target_pos)
		
		if dist > 0.1:
			var step = fly_speed * delta
			global_position = global_position.move_toward(target_pos, step)
			_aim_at_player(delta)
		else:
			global_position = target_pos
			current_state = State.IDLE
			heal_cooldown = 15.0 # Don't try to heal again immediately
			current_retreat_target = null
			mode_timer = mode_switch_time
