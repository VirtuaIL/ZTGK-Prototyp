# note_system.gd
extends Node

signal ability_activated(ability_id: String, mouse_pos: Vector2)
signal combo_activated(combo_id: String, mouse_pos: Vector2)
signal note_input(note: String, sequence: Array, matching_abilities: Array)
signal sequence_failed()
signal sequence_cleared()

const NOTE_L := "L"
const NOTE_P := "P"

var abilities: Array[Dictionary] = [
	{"id": "wave",   "name": "Fala Szczurów",    "sequence": [NOTE_L, NOTE_L], "desc": "Fala w stronę kursora"},
	{"id": "direct", "name": "Bezpośredni Atak", "sequence": [NOTE_P, NOTE_P], "desc": "Szczur za szczurem atakuje punkt"},
	{"id": "circle", "name": "Krąg Szczurów",    "sequence": [NOTE_L, NOTE_P], "desc": "Krąg atakuje obszar"},
]

# Combos: zamiast "zastąp moce" — "wzmocnij aktywną moc nową"
# modifier = moc która wzmacnia; base = moc która jest wzmacniana
# Efekt: base pozostaje aktywna, ale zmienia zachowanie
var combos: Array[Dictionary] = [
	{
		"id": "fast_wave",
		"name": "Szybka Fala",
		"requires": ["wave", "direct"],
		"desc": "Fala + Szarża = 2x szybsza fala",
		"keeps": []   # obie moce wygasają, zastępuje je combo
	},
	{
		"id": "moving_circle",
		"name": "Ruchomy Krąg",
		"requires": ["wave", "circle"],
		"desc": "Fala + Krąg = krąg porusza się w kierunku",
		"keeps": []
	},
	{
		"id": "charging_circle",   # <-- nowe: krąg + szarża
		"name": "Ładujący Krąg",
		"requires": ["direct", "circle"],
		"desc": "Szarża + Krąg = krąg pędzi do celu",
		"keeps": []
	},
]

var current_sequence: Array[String] = []
var is_listening: bool = false
var note_timeout: float = 1.5
var time_since_last_note: float = 0.0
var max_sequence_length: int = 3

var active_abilities: Array[String] = []
var ability_timers: Dictionary = {}
var ability_duration: float = 8.0

# Aktywne combos (osobny timer)
var active_combos: Array[String] = []
var combo_timers: Dictionary = {}
var combo_duration: float = 6.0

func _ready() -> void:
	pass

func set_listening(active: bool) -> void:
	is_listening = active
	if not active:
		_clear_sequence()

func _process(delta: float) -> void:
	if is_listening and current_sequence.size() > 0:
		time_since_last_note += delta
		if time_since_last_note > note_timeout:
			_clear_sequence()
			sequence_failed.emit()

	# Tick mocy
	var to_remove: Array[String] = []
	for ab_id in ability_timers:
		ability_timers[ab_id] -= delta
		if ability_timers[ab_id] <= 0.0:
			to_remove.append(ab_id)
	for ab_id in to_remove:
		ability_timers.erase(ab_id)
		active_abilities.erase(ab_id)

	# Tick combo
	var combos_to_remove: Array[String] = []
	for co_id in combo_timers:
		combo_timers[co_id] -= delta
		if combo_timers[co_id] <= 0.0:
			combos_to_remove.append(co_id)
	for co_id in combos_to_remove:
		combo_timers.erase(co_id)
		active_combos.erase(co_id)

func add_note(note: String) -> void:
	if not is_listening:
		return

	current_sequence.append(note)
	time_since_last_note = 0.0

	# Oblicz pasujące moce (do podświetlenia w HUD)
	var matching := _get_matching_abilities()
	note_input.emit(note, current_sequence.duplicate(), matching)

	var matched := _check_sequence()
	if matched != "":
		_activate_ability(matched)
		_clear_sequence()
	elif current_sequence.size() >= max_sequence_length:
		sequence_failed.emit()
		_clear_sequence()

# Zwraca id mocy których sekwencja zaczyna się od current_sequence
func _get_matching_abilities() -> Array:
	var result: Array = []
	var input_len := current_sequence.size()
	for ab in abilities:
		var seq: Array = ab["sequence"]
		if input_len > seq.size():
			continue
		var partial := true
		for i in range(input_len):
			if current_sequence[i] != seq[i]:
				partial = false
				break
		if partial:
			result.append(ab["id"])
	return result

func _check_sequence() -> String:
	for ab in abilities:
		var seq: Array = ab["sequence"]
		if seq.size() != current_sequence.size():
			continue
		var is_match := true
		for i in range(seq.size()):
			if current_sequence[i] != seq[i]:
				is_match = false
				break
		if is_match:
			return ab["id"]
	return ""

func _activate_ability(ability_id: String) -> void:
	if not active_abilities.has(ability_id):
		active_abilities.append(ability_id)
	ability_timers[ability_id] = ability_duration

	var triggered_combo := _check_combo_with(ability_id)

	if triggered_combo != "":
		var combo_data := _get_combo_data(triggered_combo)
		var reqs: Array = combo_data["requires"]
		for req in reqs:
			active_abilities.erase(req)
			ability_timers.erase(req)
		if not active_combos.has(triggered_combo):
			active_combos.append(triggered_combo)
		combo_timers[triggered_combo] = combo_duration
		# Przekaż aktualną pozycję myszy razem z combo
		var mouse_pos := get_viewport().get_mouse_position()
		combo_activated.emit(triggered_combo, mouse_pos)
	else:
		# Przekaż aktualną pozycję myszy razem z mocą
		var mouse_pos := get_viewport().get_mouse_position()
		ability_activated.emit(ability_id, mouse_pos)

# _check_combo_with — teraz wszystkie moce są już w active_abilities
func _check_combo_with(new_ability_id: String) -> String:
	for combo in combos:
		var reqs: Array = combo["requires"]
		if not reqs.has(new_ability_id):
			continue
		var all_met := true
		for req in reqs:
			if not active_abilities.has(req):   # sprawdza WSZYSTKIE, włącznie z nową
				all_met = false
				break
		if all_met:
			return combo["id"]
	return ""

func _get_combo_data(combo_id: String) -> Dictionary:
	for combo in combos:
		if combo["id"] == combo_id:
			return combo
	return {}

func _clear_sequence() -> void:
	current_sequence.clear()
	time_since_last_note = 0.0
	sequence_cleared.emit()

func get_abilities() -> Array[Dictionary]:
	return abilities

func get_active_abilities() -> Array[String]:
	return active_abilities

func get_active_combos() -> Array[String]:
	return active_combos

func is_combo_active(combo_id: String) -> bool:
	return active_combos.has(combo_id)
