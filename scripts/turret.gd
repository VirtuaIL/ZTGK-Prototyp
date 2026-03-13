extends CharacterBody3D
class_name turret

@export var fire_rate: float = 1.0 # Seconds between shots
@export var projectile_speed: float = 15.0
@export var attack_range: float = 20.0
@export var turn_speed: float = 5.0
@export var carriers_required: int = 4
@export var fall_death_y: float = -1.0
@export var gravity_multiplier: float = 5.0

signal object_reset

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []
var _spawn_position: Vector3 = Vector3.ZERO

var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")
var player_node: player = null
var fire_timer: float = 0.0

@onready var fire_point: Vector3 = Vector3(0, 0.7, 0) # Adjust based on the turret mesh

func _ready() -> void:
	collision_layer = 4 # Layer 3: Movable
	collision_mask = 31  # Floor (1) + Player (2) + Movable (4) + Walls (8) + Barrier (16)
	_spawn_position = global_position
	# Find the player in the scene
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_node = players[0]
	else:
		# Fallback if not in group, though ideally player should be in group "player"
		player_node = get_node_or_null("/root/Main/Player")


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

func _process(delta: float) -> void:
	if not player_node:
		# Try to find player continuously if not found on ready
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
		return

	var dist_to_player = global_position.distance_to(player_node.global_position)
	if dist_to_player <= attack_range:
		_aim_at_player(delta)
		
		fire_timer -= delta
		if fire_timer <= 0:
			_shoot()
			fire_timer = fire_rate

func _aim_at_player(delta: float) -> void:
	var target_pos = player_node.global_position
	target_pos.y = global_position.y # Only rotate horizontally
	
	var dir = (target_pos - global_position).normalized()
	if dir.length() > 0.1:
		var target_angle = atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, turn_speed * delta)

func _shoot() -> void:
	if not projectile_scene:
		return
		
	var target_pos = player_node.global_position
	# Aim slightly above ground, at player's center
	target_pos.y += 0.5 
	
	var fire_origin = global_position + fire_point
	var dir = (target_pos - fire_origin).normalized()
	
	var proj = projectile_scene.instantiate()
	get_parent().add_child(proj)
	
	# Place slightly in front to avoid immediate self-collision
	proj.global_position = fire_origin + dir * 0.8
	proj.velocity = dir * projectile_speed


func set_highlight(enabled: bool) -> void:
	# Turrets might have multiple meshes, but let's try to find a main one or highlight all
	for child in get_children():
		if child is MeshInstance3D:
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
