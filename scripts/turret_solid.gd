extends CharacterBody3D
class_name turret_solid

@export var fire_rate: float = 1.0 # Seconds between shots
@export var projectile_speed: float = 15.0
@export var fall_death_y: float = -1.0
@export var gravity_multiplier: float = 5.0
@export var fire_direction: Vector3 = Vector3.FORWARD # Local-space direction; set to (0,0,-1) to shoot forward

signal object_reset

var _spawn_position: Vector3 = Vector3.ZERO
var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")
var fire_timer: float = 0.0

@onready var fire_point: Vector3 = Vector3(0, 0.7, 0) # Adjust based on the turret mesh

func _ready() -> void:
	add_to_group("turrets")
	collision_layer = 4 # Layer 3: Movable
	collision_mask = 31 | (1 << 8)  # Floor (1) + Player (2) + Movable (4) + Walls (8) + Barrier (16) + RatStructures (9)
	_spawn_position = global_position

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
	fire_timer -= delta
	if fire_timer <= 0.0:
		_shoot()
		fire_timer = fire_rate

func _shoot() -> void:
	if not projectile_scene:
		return

	var local_dir = fire_direction
	if local_dir.length() < 0.001:
		local_dir = Vector3.FORWARD

	var dir = (global_transform.basis * local_dir).normalized()
	if dir.length() < 0.001:
		dir = -global_transform.basis.z

	var fire_origin = global_position + fire_point
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
