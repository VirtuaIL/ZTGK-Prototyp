# note_hud.gd
extends CanvasLayer

var rat_manager: Node = null
var note_system: Node = null
var player: Node = null

var _mode_panel: PanelContainer
var _mode_label: Label

var _seq_root: VBoxContainer
var _seq_panel: PanelContainer
var _seq_hbox: HBoxContainer
var _seq_hint: Label
var _seq_matches_hbox: HBoxContainer  # podpowiedzi pasujących mocy

var _abilities_panel: PanelContainer
var _abilities_vbox: VBoxContainer

var _orbit_panel: PanelContainer
var _orbit_bar: ProgressBar
var _orbit_label: Label

var _current_sequence: Array[String] = []
var _matching_abilities: Array = []
var _instrument_active: bool = false
var _current_mode: String = "combat"

const ABILITY_INFO := {
	"wave":   {"icon": "〰", "name": "Fala",  "seq": ["L","L"], "color": Color(0.3, 0.75, 1.0)},
	"direct": {"icon": "⚡", "name": "Szarża","seq": ["P","P"], "color": Color(1.0, 0.65, 0.2)},
	"circle": {"icon": "🌀", "name": "Krąg",  "seq": ["L","P"], "color": Color(0.55, 0.35, 1.0)},
}
const COMBO_INFO := {
	"fast_wave":      {"icon": "💨", "name": "Szybka Fala",   "color": Color(0.2, 1.0, 0.8)},
	"moving_circle":  {"icon": "🌪", "name": "Ruchomy Krąg",  "color": Color(0.9, 0.3, 1.0)},
	"charging_circle":{"icon": "🐀", "name": "Ładujący Krąg", "color": Color(1.0, 0.7, 0.1)},
}

# note_hud.gd — dodaj słownik nazw puzzle i zmodyfikuj _build_ability_reference oraz set_mode

# Dodaj stałą z nazwami mocy w trybie puzzle
const ABILITY_INFO_PUZZLE := {
	"wave":   {"icon": "💨", "name": "Odpychanie", "seq": ["L","L"], "color": Color(0.3, 0.75, 1.0)},
	"direct": {"icon": "🧲", "name": "Przyciąg",   "seq": ["P","P"], "color": Color(1.0, 0.65, 0.2)},
	"circle": {"icon": "🤲", "name": "Przenoszenie","seq": ["L","P"], "color": Color(0.55, 0.35, 1.0)},
}

# Zmienna przechowująca aktualny tryb (już masz _current_mode)
# Dodaj referencję do panelu legendy żeby móc go odświeżyć
var _reference_panel: PanelContainer
var _reference_vbox: VBoxContainer   # VBoxContainer wewnątrz panelu legendy

const C_BG          := Color(0.05, 0.04, 0.06, 0.88)
const C_BORDER      := Color(0.25, 0.20, 0.30, 0.6)
const C_TEXT        := Color(0.90, 0.85, 0.75)
const C_DIM         := Color(0.40, 0.38, 0.36)
const C_COMBAT      := Color(0.95, 0.35, 0.25)
const C_PUZZLE      := Color(0.25, 0.80, 0.55)
const C_NOTE_L      := Color(0.30, 0.70, 1.00)
const C_NOTE_P      := Color(1.00, 0.55, 0.20)
const C_NOTE_EMPTY  := Color(0.22, 0.20, 0.24)
const C_NOTE_INACTIVE := Color(0.30, 0.28, 0.32)

func _ready() -> void:
	_build_mode_panel()
	_build_seq_panel()
	_build_abilities_panel()
	_build_orbit_panel()
	_build_ability_reference()

func _make_panel_style(radius: float = 8.0, bg: Color = C_BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = C_BORDER
	s.border_width_left = 1; s.border_width_right = 1
	s.border_width_top  = 1; s.border_width_bottom = 1
	s.corner_radius_top_left    = int(radius)
	s.corner_radius_top_right   = int(radius)
	s.corner_radius_bottom_left = int(radius)
	s.corner_radius_bottom_right= int(radius)
	s.content_margin_left = 12; s.content_margin_right  = 12
	s.content_margin_top  = 8;  s.content_margin_bottom = 8
	return s

# ── Pasek trybu ───────────────────────────────────────────
func _build_mode_panel() -> void:
	_mode_panel = PanelContainer.new()
	_mode_panel.add_theme_stylebox_override("panel", _make_panel_style(20.0))
	_mode_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mode_panel.position = Vector2(0, 16)

	_mode_label = Label.new()
	_mode_label.text = "⚔  WALKA"
	_mode_label.add_theme_font_size_override("font_size", 15)
	_mode_label.add_theme_color_override("font_color", C_COMBAT)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_panel.add_child(_mode_label)
	add_child(_mode_panel)

# ── Sekwencja nut + podpowiedzi (dół-środek) ─────────────
func _build_seq_panel() -> void:
	_seq_root = VBoxContainer.new()
	# Zamiast PRESET_CENTER_BOTTOM użyj ręcznych anchorów
	_seq_root.anchor_left   = 0.5
	_seq_root.anchor_right  = 0.5
	_seq_root.anchor_top    = 1.0
	_seq_root.anchor_bottom = 1.0
	_seq_root.offset_left   = -120.0
	_seq_root.offset_right  =  120.0
	_seq_root.offset_top    = -160.0   # <-- tu regulujesz wysokość od dołu ekranu
	_seq_root.offset_bottom = -60.0
	_seq_root.add_theme_constant_override("separation", 6)
	_seq_root.alignment = BoxContainer.ALIGNMENT_CENTER
	_seq_root.visible = false

	# reszta bez zmian...
	_seq_hint = Label.new()
	_seq_hint.text = "SPACJA + LPM = L    PPM = P"
	_seq_hint.add_theme_font_size_override("font_size", 11)
	_seq_hint.add_theme_color_override("font_color", C_DIM)
	_seq_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seq_root.add_child(_seq_hint)

	_seq_panel = PanelContainer.new()
	_seq_panel.add_theme_stylebox_override("panel", _make_panel_style(12.0))
	_seq_hbox = HBoxContainer.new()
	_seq_hbox.add_theme_constant_override("separation", 10)
	_seq_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_seq_panel.add_child(_seq_hbox)
	_seq_root.add_child(_seq_panel)

	_seq_matches_hbox = HBoxContainer.new()
	_seq_matches_hbox.add_theme_constant_override("separation", 12)
	_seq_matches_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_seq_root.add_child(_seq_matches_hbox)

	add_child(_seq_root)

# ── Panel aktywnych mocy (lewy-dół) ──────────────────────
func _build_abilities_panel() -> void:
	_abilities_panel = PanelContainer.new()
	_abilities_panel.add_theme_stylebox_override("panel", _make_panel_style(8.0))
	_abilities_panel.anchor_left   = 0.0
	_abilities_panel.anchor_right  = 0.0
	_abilities_panel.anchor_top    = 1.0
	_abilities_panel.anchor_bottom = 1.0
	_abilities_panel.offset_left   = 16.0
	_abilities_panel.offset_right  = 226.0
	_abilities_panel.offset_top    = -180.0   # <-- reguluj wg potrzeby
	_abilities_panel.offset_bottom = -16.0
	_abilities_panel.custom_minimum_size = Vector2(210, 0)
	_abilities_panel.visible = false

	_abilities_vbox = VBoxContainer.new()
	_abilities_vbox.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "AKTYWNE"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", C_DIM)
	_abilities_vbox.add_child(title)

	_abilities_panel.add_child(_abilities_vbox)
	add_child(_abilities_panel)

# ── Pasek orbity (góra-lewo) ──────────────────────────────
func _build_orbit_panel() -> void:
	_orbit_panel = PanelContainer.new()
	_orbit_panel.add_theme_stylebox_override("panel", _make_panel_style(8.0))
	_orbit_panel.position = Vector2(16, 16)
	_orbit_panel.custom_minimum_size = Vector2(200, 0)
	_orbit_panel.visible = false

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)

	_orbit_label = Label.new()
	_orbit_label.text = "🌀  Krąg aktywny"
	_orbit_label.add_theme_font_size_override("font_size", 13)
	_orbit_label.add_theme_color_override("font_color", Color(0.55, 0.35, 1.0))
	vb.add_child(_orbit_label)

	_orbit_bar = ProgressBar.new()
	_orbit_bar.custom_minimum_size = Vector2(180, 10)
	_orbit_bar.max_value = 1.0; _orbit_bar.value = 1.0
	_orbit_bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.12, 0.18)
	for prop in ["corner_radius_top_left","corner_radius_top_right","corner_radius_bottom_left","corner_radius_bottom_right"]:
		bg.set(prop, 5)
	_orbit_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.35, 1.0)
	for prop in ["corner_radius_top_left","corner_radius_top_right","corner_radius_bottom_left","corner_radius_bottom_right"]:
		fill.set(prop, 5)
	_orbit_bar.add_theme_stylebox_override("fill", fill)
	vb.add_child(_orbit_bar)
	_orbit_panel.add_child(vb)
	add_child(_orbit_panel)

# ── Legenda (prawy-dół) ───────────────────────────────────
func _build_ability_reference() -> void:
	_reference_panel = PanelContainer.new()
	_reference_panel.add_theme_stylebox_override("panel", _make_panel_style(8.0, Color(0.04, 0.03, 0.05, 0.75)))
	_reference_panel.anchor_left   = 1.0
	_reference_panel.anchor_right  = 1.0
	_reference_panel.anchor_top    = 1.0
	_reference_panel.anchor_bottom = 1.0
	_reference_panel.offset_left   = -220.0
	_reference_panel.offset_right  = -16.0
	_reference_panel.offset_top    = -280.0
	_reference_panel.offset_bottom = -16.0

	_reference_vbox = VBoxContainer.new()
	_reference_vbox.add_theme_constant_override("separation", 5)
	_reference_panel.add_child(_reference_vbox)
	add_child(_reference_panel)

	_rebuild_reference_for_mode("combat")

# note_hud.gd — nowa funkcja odbudowująca legendę
func _rebuild_reference_for_mode(mode: String) -> void:
	for child in _reference_vbox.get_children():
		child.queue_free()

	var ability_map: Dictionary = ABILITY_INFO if mode == "combat" else ABILITY_INFO_PUZZLE

	var t1 := Label.new()
	t1.text = "SEKWENCJE"
	t1.add_theme_font_size_override("font_size", 10)
	t1.add_theme_color_override("font_color", C_DIM)
	_reference_vbox.add_child(t1)

	for ab_id in ability_map:
		var info: Dictionary = ability_map[ab_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var ic := Label.new()
		ic.text = info["icon"]
		ic.add_theme_font_size_override("font_size", 14)
		ic.custom_minimum_size = Vector2(22, 0)
		row.add_child(ic)

		var nm := Label.new()
		nm.text = info["name"]
		nm.add_theme_font_size_override("font_size", 12)
		nm.add_theme_color_override("font_color", info["color"])
		nm.custom_minimum_size = Vector2(85, 0)
		row.add_child(nm)

		var sh := HBoxContainer.new()
		sh.add_theme_constant_override("separation", 3)
		for note in info["seq"]:
			var n := Label.new()
			n.text = note
			n.add_theme_font_size_override("font_size", 13)
			n.add_theme_color_override("font_color", C_NOTE_L if note == "L" else C_NOTE_P)
			sh.add_child(n)
		row.add_child(sh)
		_reference_vbox.add_child(row)

	# Combo tylko w walce
	if mode == "combat":
		var t2 := Label.new()
		t2.text = "COMBOS"
		t2.add_theme_font_size_override("font_size", 10)
		t2.add_theme_color_override("font_color", C_DIM)
		_reference_vbox.add_child(t2)

		for co_id in COMBO_INFO:
			var info: Dictionary = COMBO_INFO[co_id]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var ic := Label.new()
			ic.text = info["icon"]
			ic.add_theme_font_size_override("font_size", 14)
			ic.custom_minimum_size = Vector2(22, 0)
			row.add_child(ic)
			var nm := Label.new()
			nm.text = info["name"]
			nm.add_theme_font_size_override("font_size", 12)
			nm.add_theme_color_override("font_color", info["color"])
			row.add_child(nm)
			_reference_vbox.add_child(row)
# ══════════════════════════════════════════════════════════
#  API
# ══════════════════════════════════════════════════════════

func set_mode(mode: String) -> void:
	_current_mode = mode
	if mode == "combat":
		_mode_label.text = "⚔  WALKA"
		_mode_label.add_theme_color_override("font_color", C_COMBAT)
	else:
		_mode_label.text = "🧩  PUZZLE"
		_mode_label.add_theme_color_override("font_color", C_PUZZLE)
	# Odbuduj legendę dla nowego trybu
	_rebuild_reference_for_mode(mode)
	var tween := create_tween()
	tween.tween_property(_mode_panel, "modulate", Color(2, 2, 2), 0.08)
	tween.tween_property(_mode_panel, "modulate", Color(1, 1, 1), 0.25)

func set_instrument_active(active: bool) -> void:
	_instrument_active = active
	_seq_root.visible = active
	if active:
		_current_sequence.clear()
		_matching_abilities.clear()
		_refresh_seq_display()
	else:
		_current_sequence.clear()
		_matching_abilities.clear()
		_refresh_seq_display()

# Sygnał note_input teraz niesie też matching_abilities
func on_note_added(sequence: Array, matching: Array) -> void:
	_current_sequence = sequence.duplicate()
	_matching_abilities = matching.duplicate()
	_refresh_seq_display()
	_refresh_matches_display()

func on_sequence_failed() -> void:
	for child in _seq_hbox.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	var tween := create_tween()
	tween.tween_interval(0.25)
	tween.tween_callback(func():
		_current_sequence.clear()
		_matching_abilities.clear()
		_refresh_seq_display()
		_refresh_matches_display()
	)

func on_ability_activated(_ability_id: String) -> void:
	for child in _seq_hbox.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	var tween := create_tween()
	tween.tween_interval(0.2)
	tween.tween_callback(func():
		_current_sequence.clear()
		_matching_abilities.clear()
		_refresh_seq_display()
		_refresh_matches_display()
	)
	_refresh_abilities_panel()

func on_combo_activated(_combo_id: String) -> void:
	_refresh_abilities_panel()
	if _abilities_panel.visible:
		var tween := create_tween()
		tween.tween_property(_abilities_panel, "modulate", Color(2, 2, 2), 0.1)
		tween.tween_property(_abilities_panel, "modulate", Color(1, 1, 1), 0.35)

# ══════════════════════════════════════════════════════════
#  PROCESS
# ══════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	_update_orbit_bar()
	if note_system != null and note_system.get_active_abilities().size() > 0:
		_refresh_abilities_panel()

func _update_orbit_bar() -> void:
	if rat_manager == null:
		return
	if rat_manager.orbit_active:
		_orbit_panel.visible = true
		var progress: float = rat_manager.get_orbit_progress()
		_orbit_bar.value = progress
		var fill_style: StyleBoxFlat = _orbit_bar.get_theme_stylebox("fill")
		if progress > 0.5:
			fill_style.bg_color = Color(0.55, 0.35, 1.0)
		elif progress > 0.2:
			fill_style.bg_color = Color(0.9, 0.55, 0.2)
		else:
			fill_style.bg_color = Color(0.9, 0.2, 0.2)
	else:
		_orbit_panel.visible = false

# ══════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════

func _refresh_seq_display() -> void:
	for child in _seq_hbox.get_children():
		child.queue_free()

	for i in range(3):
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.custom_minimum_size = Vector2(42, 42)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

		if i < _current_sequence.size():
			var note: String = _current_sequence[i]
			lbl.text = note
			lbl.add_theme_color_override("font_color",
				C_NOTE_L if note == "L" else C_NOTE_P)
		else:
			lbl.text = "·"
			lbl.add_theme_color_override("font_color", C_NOTE_EMPTY)

		_seq_hbox.add_child(lbl)

# Pokazuje pasujące moce pod slotami nut
func _refresh_matches_display() -> void:
	for child in _seq_matches_hbox.get_children():
		child.queue_free()

	if _current_sequence.is_empty() or _matching_abilities.is_empty():
		return

	for ab_id in ABILITY_INFO:
		var info: Dictionary = ABILITY_INFO[ab_id]
		var is_matching: bool = _matching_abilities.has(ab_id)

		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)

		var ic := Label.new()
		ic.text = info["icon"]
		ic.add_theme_font_size_override("font_size", 14)
		chip.add_child(ic)

		var nm := Label.new()
		nm.text = info["name"]
		nm.add_theme_font_size_override("font_size", 12)

		# Aktywne podpowiedzi jasne, nieaktywne wygaszone
		if is_matching:
			nm.add_theme_color_override("font_color", info["color"])
			# Pogrubienie przez skalę
			chip.modulate = Color(1, 1, 1, 1.0)
		else:
			nm.add_theme_color_override("font_color", C_NOTE_INACTIVE)
			chip.modulate = Color(1, 1, 1, 0.35)

		chip.add_child(nm)
		_seq_matches_hbox.add_child(chip)

func _refresh_abilities_panel() -> void:
	if note_system == null:
		return

	var active_ab: Array  = note_system.get_active_abilities()
	var active_co: Array  = note_system.get_active_combos()
	var all_active := active_ab + active_co

	# Wyczyść wiersze (zostaw tytuł — index 0)
	var children := _abilities_vbox.get_children()
	for i in range(1, children.size()):
		children[i].queue_free()

	if all_active.is_empty():
		_abilities_panel.visible = false
		return

	_abilities_panel.visible = true

	for id in all_active:
		var info: Dictionary = ABILITY_INFO.get(id, COMBO_INFO.get(id, {}))
		if info.is_empty():
			continue

		var is_combo: bool = COMBO_INFO.has(id)
		var timer_val: float
		var max_t: float
		if is_combo:
			timer_val = note_system.combo_timers.get(id, 0.0)
			max_t     = note_system.combo_duration
		else:
			timer_val = note_system.ability_timers.get(id, 0.0)
			max_t     = note_system.ability_duration

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var ic := Label.new()
		ic.text = info.get("icon", "?")
		ic.add_theme_font_size_override("font_size", 16)
		ic.custom_minimum_size = Vector2(22, 0)
		row.add_child(ic)

		var nm := Label.new()
		nm.text = info.get("name", id)
		nm.add_theme_font_size_override("font_size", 13)
		nm.add_theme_color_override("font_color", info.get("color", C_TEXT))
		nm.custom_minimum_size = Vector2(90, 0)
		row.add_child(nm)

		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(50, 6)
		bar.max_value = 1.0
		bar.value = timer_val / max(max_t, 0.001)
		bar.show_percentage = false
		var bg2 := StyleBoxFlat.new()
		bg2.bg_color = Color(0.15, 0.12, 0.18)
		for prop in ["corner_radius_top_left","corner_radius_top_right","corner_radius_bottom_left","corner_radius_bottom_right"]:
			bg2.set(prop, 3)
		bar.add_theme_stylebox_override("background", bg2)
		var fill2 := StyleBoxFlat.new()
		fill2.bg_color = info.get("color", C_TEXT)
		for prop in ["corner_radius_top_left","corner_radius_top_right","corner_radius_bottom_left","corner_radius_bottom_right"]:
			fill2.set(prop, 3)
		bar.add_theme_stylebox_override("fill", fill2)
		row.add_child(bar)

		# Odznaka COMBO
		if is_combo:
			var badge := Label.new()
			badge.text = "COMBO"
			badge.add_theme_font_size_override("font_size", 9)
			badge.add_theme_color_override("font_color", info.get("color", C_TEXT))
			row.add_child(badge)

		_abilities_vbox.add_child(row)
