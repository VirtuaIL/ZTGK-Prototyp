extends Node3D

const RAT_COUNT := 12

var rat_scene: PackedScene = preload("res://scenes/rat.tscn")
var player: CharacterBody3D
var rat_manager: Node3D
var stratagem_system: Node
var stratagem_hud: CanvasLayer


func _ready() -> void:
	_setup_input_map()
	_setup_environment()
	_setup_player()
	_setup_rats()
	_setup_enemies()
	_setup_stratagem_system()


func _setup_environment() -> void:
	# Floor
	var floor_body := StaticBody3D.new()
	add_child(floor_body)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25, 0.22, 0.2)
	floor_mesh.material_override = floor_mat
	floor_body.add_child(floor_mesh)

	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40, 0.1, 40)
	floor_col.shape = floor_shape
	floor_col.position.y = -0.05
	floor_body.add_child(floor_col)

	# Camera (isometric)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.0
	camera.position = Vector3(10, 12, 10)
	camera.look_at(Vector3.ZERO)
	add_child(camera)

	# Directional light
	var light := DirectionalLight3D.new()
	light.position = Vector3(5, 10, 5)
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)

	# Ambient + background
	var env := Environment.new()
	env.ambient_light_color = Color(0.3, 0.28, 0.35)
	env.ambient_light_energy = 0.5
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.08, 0.12)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _setup_player() -> void:
	var player_scene := preload("res://scenes/player.tscn")
	player = player_scene.instantiate()
	player.position = Vector3(0, 0, 0)
	add_child(player)


func _setup_rats() -> void:
	rat_manager = Node3D.new()
	rat_manager.set_script(preload("res://scripts/rat_manager.gd"))
	add_child(rat_manager)

	for i in range(RAT_COUNT):
		var rat := rat_scene.instantiate()
		var angle := (TAU / RAT_COUNT) * i
		rat.position = player.position + Vector3(
			cos(angle) * 2.0,
			0,
			sin(angle) * 2.0
		)
		rat.player = player
		add_child(rat)
		rat_manager.register_rat(rat)


func _setup_enemies() -> void:
	var enemy_scene := preload("res://scenes/enemy.tscn")
	var enemy := enemy_scene.instantiate()
	enemy.position = Vector3(5, 0, 3)
	add_child(enemy)


func _setup_stratagem_system() -> void:
	stratagem_system = Node.new()
	stratagem_system.set_script(preload("res://scripts/stratagem_system.gd"))
	add_child(stratagem_system)

	var hud_scene := preload("res://scenes/ui/stratagem_hud.tscn")
	stratagem_hud = hud_scene.instantiate()
	add_child(stratagem_hud)

	# Connect signals
	stratagem_system.stratagem_menu_toggled.connect(_on_stratagem_menu_toggled)
	stratagem_system.stratagem_input_received.connect(_on_stratagem_input)
	stratagem_system.stratagem_completed.connect(_on_stratagem_completed)
	stratagem_system.stratagem_failed.connect(_on_stratagem_failed)

	# Ability timer HUD
	var ability_hud := CanvasLayer.new()
	ability_hud.set_script(preload("res://scripts/ui/ability_timer_hud.gd"))
	ability_hud.rat_manager = rat_manager
	add_child(ability_hud)


func _setup_input_map() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)


func _add_action(action_name: String, key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event := InputEventKey.new()
		event.keycode = key
		InputMap.action_add_event(action_name, event)


func _on_stratagem_menu_toggled(active: bool) -> void:
	player.set_stratagem_mode(active)
	if active:
		stratagem_hud.show_menu(stratagem_system.get_stratagems())
	else:
		stratagem_hud.hide_menu()


func _on_stratagem_input(input_index: int, matching_strat_indices: Array) -> void:
	stratagem_hud.highlight_direction(input_index, matching_strat_indices)


func _on_stratagem_completed(stratagem_id: String) -> void:
	stratagem_hud.flash_success()
	rat_manager.on_stratagem_activated(stratagem_id)


func _on_stratagem_failed() -> void:
	stratagem_hud.flash_fail()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		var offset := Vector3(10, 12, 10)
		cam.position = cam.position.lerp(player.position + offset, 0.05)
		cam.look_at(player.position)
