extends Node

signal stratagem_completed(stratagem_id: String)
signal stratagem_input_received(input_index: int, matching_strat_indices: Array)
signal stratagem_failed()
signal stratagem_menu_toggled(active: bool)

const DIR_UP := "up"
const DIR_DOWN := "down"
const DIR_LEFT := "left"
const DIR_RIGHT := "right"

var stratagems: Array[Dictionary] = []
var current_input: Array[String] = []
var is_active: bool = false
var input_timeout: float = 2.0
var time_since_last_input: float = 0.0


func _ready() -> void:
	register_stratagem({
		"id": "rat_orbit",
		"name": "Szczurza Orbita",
		"sequence": [DIR_UP, DIR_DOWN, DIR_UP, DIR_RIGHT],
	})
	register_stratagem({
		"id": "rat_wave",
		"name": "Szczurza Fala",
		"sequence": [DIR_UP, DIR_UP, DIR_RIGHT, DIR_DOWN],
	})


func register_stratagem(data: Dictionary) -> void:
	stratagems.append(data)


func _process(delta: float) -> void:
	var ctrl_held := Input.is_key_pressed(KEY_CTRL)

	if ctrl_held and not is_active:
		_activate()
	elif not ctrl_held and is_active:
		_deactivate()

	if is_active and current_input.size() > 0:
		time_since_last_input += delta
		if time_since_last_input > input_timeout:
			_reset_input()
			stratagem_failed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_active:
		return

	var key_event := event as InputEventKey
	if key_event == null:
		return

	if not key_event.pressed or key_event.echo:
		return

	var direction := ""
	match key_event.keycode:
		KEY_W:
			direction = DIR_UP
		KEY_S:
			direction = DIR_DOWN
		KEY_A:
			direction = DIR_LEFT
		KEY_D:
			direction = DIR_RIGHT

	if direction == "":
		return

	# Consume the event so it doesn't trigger movement
	get_viewport().set_input_as_handled()

	current_input.append(direction)
	time_since_last_input = 0.0

	# Check against all stratagems
	var matching_indices: Array[int] = []
	var input_len := current_input.size()

	for strat_idx in range(stratagems.size()):
		var seq: Array = stratagems[strat_idx]["sequence"]

		if input_len > seq.size():
			continue

		var partial_match := true
		for i in range(input_len):
			if current_input[i] != seq[i]:
				partial_match = false
				break

		if partial_match:
			matching_indices.append(strat_idx)

			if input_len == seq.size():
				stratagem_input_received.emit(input_len - 1, matching_indices as Array)
				stratagem_completed.emit(stratagems[strat_idx]["id"])
				_reset_input()
				return

	if matching_indices.size() > 0:
		stratagem_input_received.emit(input_len - 1, matching_indices as Array)
	else:
		stratagem_input_received.emit(input_len - 1, [] as Array)
		stratagem_failed.emit()
		_reset_input()


func _activate() -> void:
	is_active = true
	current_input.clear()
	time_since_last_input = 0.0
	stratagem_menu_toggled.emit(true)


func _deactivate() -> void:
	is_active = false
	current_input.clear()
	stratagem_menu_toggled.emit(false)


func _reset_input() -> void:
	current_input.clear()
	time_since_last_input = 0.0


func get_stratagems() -> Array[Dictionary]:
	return stratagems
