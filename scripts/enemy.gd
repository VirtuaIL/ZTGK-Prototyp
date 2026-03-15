extends StaticBody3D

@export var max_health: float = 100.0
@export var respawn_time: float = 3.0
var health: float = max_health

var hp_bar_bg: MeshInstance3D
var hp_bar_fill: MeshInstance3D
var hp_bar_fill_mat: StandardMaterial3D
var hp_label: Label3D

var _spawn_transform: Transform3D
var _is_dead: bool = false
var _collision_layer: int
var _collision_mask: int

var damage_cooldowns: Dictionary = {}


func _ready() -> void:
	add_to_group("enemies")
	_spawn_transform = global_transform
	_collision_layer = collision_layer
	_collision_mask = collision_mask
	health = max_health
	# HP Bar (billboard above enemy)
	_create_hp_bar()
	_create_hp_label()
	_update_hp_bar()


func _create_hp_bar() -> void:
	var bar_width: float = 1.0
	var bar_height: float = 0.08

	# Background (dark)
	hp_bar_bg = MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(bar_width, bar_height)
	hp_bar_bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.15, 0.15, 0.9)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 1
	hp_bar_bg.material_override = bg_mat
	hp_bar_bg.position.y = 2.2
	add_child(hp_bar_bg)

	# Fill (green -> red)
	hp_bar_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(bar_width, bar_height)
	hp_bar_fill.mesh = fill_mesh
	hp_bar_fill_mat = StandardMaterial3D.new()
	hp_bar_fill_mat.albedo_color = Color(0.2, 0.9, 0.3)
	hp_bar_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hp_bar_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_bar_fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hp_bar_fill_mat.no_depth_test = true
	hp_bar_fill_mat.render_priority = 2
	hp_bar_fill.material_override = hp_bar_fill_mat
	hp_bar_fill.position.y = 2.2
	add_child(hp_bar_fill)

func _create_hp_label() -> void:
	hp_label = Label3D.new()
	hp_label.text = str(int(health))
	hp_label.position.y = 2.4
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.pixel_size = 0.01
	hp_label.outline_size = 6
	hp_label.outline_modulate = Color(0, 0, 0, 0.9)
	add_child(hp_label)

func _process(delta: float) -> void:
	if _is_dead:
		return
	# Tick cooldowns
	var to_remove: Array = []
	for key in damage_cooldowns:
		damage_cooldowns[key] -= delta
		if damage_cooldowns[key] <= 0.0:
			to_remove.append(key)
	for key in to_remove:
		damage_cooldowns.erase(key)


func take_damage(amount: float, source_id: int = -1) -> void:
	if _is_dead:
		return
	# Per-source cooldown to prevent damage spam
	if source_id >= 0:
		if damage_cooldowns.has(source_id):
			return
		damage_cooldowns[source_id] = 0.3 # 0.3s cooldown per rat

	health -= amount
	health = maxf(health, 0.0)
	_update_hp_bar()

	# Flash white on hit
	_flash_hit()

	if health <= 0.0:
		_die()


func _update_hp_bar() -> void:
	var ratio: float = health / max_health

	# Scale fill bar
	hp_bar_fill.scale.x = ratio
	# Offset to keep left-aligned
	hp_bar_fill.position.x = - (1.0 - ratio) * 0.5

	# Color: green -> yellow -> red
	if ratio > 0.5:
		hp_bar_fill_mat.albedo_color = Color(0.2, 0.9, 0.3)
	elif ratio > 0.25:
		hp_bar_fill_mat.albedo_color = Color(0.9, 0.8, 0.2)
	else:
		hp_bar_fill_mat.albedo_color = Color(0.9, 0.2, 0.15)

	if hp_label:
		hp_label.text = str(int(ceil(health)))


func _flash_hit() -> void:
	# Quick white flash on body
	var body: MeshInstance3D = get_child(0) as MeshInstance3D
	if body and body.material_override:
		var original_color: Color = Color(0.8, 0.15, 0.15)
		body.material_override.albedo_color = Color(1.0, 1.0, 1.0)
		var tween := create_tween()
		tween.tween_property(body.material_override, "albedo_color", original_color, 0.15)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	damage_cooldowns.clear()
	collision_layer = 0
	collision_mask = 0

	# Shrink and disappear
	var tween := create_tween()
	tween.tween_property(self , "scale", Vector3(0, 0, 0), 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		visible = false
	)

	await get_tree().create_timer(respawn_time).timeout
	_respawn()


func _respawn() -> void:
	_is_dead = false
	visible = true
	scale = Vector3.ONE
	global_transform = _spawn_transform
	health = max_health
	_update_hp_bar()
	collision_layer = _collision_layer
	collision_mask = _collision_mask
