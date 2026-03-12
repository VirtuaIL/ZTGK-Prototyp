# main.gd — z podpięciem note_hud
extends Node3D

const RAT_COUNT := 40
var rat_scene: PackedScene = preload("res://scenes/rat.tscn")

@onready var player: CharacterBody3D = $Player
@onready var rat_manager: Node3D = $RatManager
@onready var note_system: Node = $NoteSystem
@onready var note_hud: CanvasLayer = $NoteHUD   # <-- zmień nazwę węzła w scenie
@onready var puzzle_manager: Node    = $PuzzleManager

var _c_held: bool = false
var _instrument_held: bool = false

func _ready() -> void:
	_setup_input_map()
	_init_game()

func _init_game() -> void:
	for i in range(RAT_COUNT):
		var rat := rat_scene.instantiate()
		var angle := (TAU / RAT_COUNT) * i
		rat.position = player.position + Vector3(cos(angle) * 2.0, 0, sin(angle) * 2.0)
		rat.player = player
		add_child(rat)
		rat_manager.register_rat(rat)

	puzzle_manager.player = player 
	player.fell_into_void.connect(_on_player_fell)

	# Podepnij referencje do HUD
	note_hud.rat_manager = rat_manager
	note_hud.note_system  = note_system
	note_hud.player       = player

	# Sygnały note_system
	note_system.ability_activated.connect(_on_ability_activated)
	note_system.combo_activated.connect(_on_combo_activated)
	note_system.sequence_failed.connect(_on_sequence_failed)
	note_system.note_input.connect(_on_note_input)

	# Sygnały player
	player.mode_changed.connect(_on_mode_changed)

func _setup_input_map() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back",    KEY_S)
	_add_key_action("move_left",    KEY_A)
	_add_key_action("move_right",   KEY_D)

func _add_key_action(name: String, key: Key) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name)
		var e := InputEventKey.new()
		e.keycode = key
		InputMap.action_add_event(name, e)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.keycode == KEY_SPACE and not ke.echo:
			if ke.pressed and not _instrument_held:
				_instrument_held = true
				note_system.set_listening(true)
				player.set_playing_instrument(true)
				note_hud.set_instrument_active(true)
			elif not ke.pressed:
				_instrument_held = false
				note_system.set_listening(false)
				player.set_playing_instrument(false)
				note_hud.set_instrument_active(false)
			get_viewport().set_input_as_handled()
			return

		if ke.keycode == KEY_C and not ke.echo:
			_c_held = ke.pressed
			get_viewport().set_input_as_handled()
			return

		if ke.keycode == KEY_CTRL and ke.pressed and not ke.echo:
			rat_manager.recall_all_rats()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and player.is_puzzle_mode():
			if _c_held:
				rat_manager.set_draw_mouse_down(mb.pressed)
				get_viewport().set_input_as_handled()
				return
		if _instrument_held and mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				note_system.add_note("L")
				get_viewport().set_input_as_handled()
				return
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				note_system.add_note("P")
				get_viewport().set_input_as_handled()
				return

func _on_mode_changed(mode: String) -> void:
	note_hud.set_mode(mode)
	puzzle_manager.set_puzzle_active(mode == "puzzle")
	if mode == "combat":
		rat_manager.recall_all_rats()

func _on_ability_activated(ability_id: String, mouse_pos: Vector2) -> void:
	note_hud.on_ability_activated(ability_id)
	if player.is_combat_mode():
		rat_manager.on_ability_activated(ability_id, mouse_pos)
	else:
		puzzle_manager.handle_ability(ability_id, mouse_pos)

func _on_combo_activated(combo_id: String, mouse_pos: Vector2) -> void:
	note_hud.on_combo_activated(combo_id)
	# Combo TYLKO w trybie walki
	if player.is_combat_mode():
		rat_manager.on_combo_activated(combo_id, mouse_pos)
	# W puzzle — ignoruj combo całkowicie

func _on_sequence_failed() -> void:
	note_hud.on_sequence_failed()

func _on_note_input(_note: String, sequence: Array, matching: Array) -> void:
	note_hud.on_note_added(sequence, matching)

func _on_player_fell() -> void:
	# Recall szczurów
	rat_manager.recall_all_rats()
	# Krótkie zamrożenie + respawn
	await get_tree().create_timer(0.6).timeout
	player.respawn()
	# Resetuj moce
	puzzle_manager.on_exit_puzzle_mode()

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and player:
		var offset := Vector3(10, 12, 10)
		cam.position = cam.position.lerp(player.position + offset, 0.05)
		cam.look_at(player.position)
