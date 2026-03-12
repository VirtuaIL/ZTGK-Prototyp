# puzzle_manager.gd — kompletna przepisana wersja
extends Node

var player: Node3D = null
var carried_object: RigidBody3D = null
var ability_range: float = 8.0
var _last_highlighted: RigidBody3D = null
var _puzzle_mode_active: bool = false

func _ready() -> void:
	pass

func set_puzzle_active(active: bool) -> void:
	_puzzle_mode_active = active
	if not active:
		on_exit_puzzle_mode()

# ── Wywoływane z main.gd ─────────────────────────────────
# BRAK combo w trybie puzzle — tylko 3 podstawowe moce
# Tymczasowy debug — dodaj na początku handle_ability
func handle_ability(ability_id: String, _mouse_pos: Vector2) -> void:
	print("[puzzle] handle_ability called: ", ability_id, " | active: ", _puzzle_mode_active)
	if not _puzzle_mode_active:
		print("[puzzle] BLOCKED — puzzle mode not active")
		return
	var target := _get_nearest_in_range()
	print("[puzzle] target: ", target, " | objects in group: ", get_tree().get_nodes_in_group("puzzle_objects").size())
	if target == null:
		print("[puzzle] NO TARGET — player pos: ", player.global_position if player else "NO PLAYER")
		return
	print("[puzzle] applying ", ability_id, " to ", target.name)
	match ability_id:
		"wave":   target.apply_push(player.global_position)
		"direct": target.apply_pull(player.global_position)
		"circle": _toggle_carry(target)

func on_exit_puzzle_mode() -> void:
	if carried_object != null:
		carried_object.stop_carry()
		carried_object = null
	# Wyłącz podświetlenie
	if _last_highlighted != null and is_instance_valid(_last_highlighted):
		_last_highlighted.set_highlight(false)
	_last_highlighted = null

# ── Carry toggle ─────────────────────────────────────────
func _toggle_carry(target: RigidBody3D) -> void:
	# Jeśli niesiemy TEN SAM obiekt — upuść
	if carried_object != null:
		var was_carrying := carried_object
		carried_object = null
		was_carrying.stop_carry()
		# Jeśli kliknęliśmy ten sam — tylko upuść
		if was_carrying == target:
			return
	# Podnieś nowy obiekt
	carried_object = target
	if not target.released.is_connected(_on_carried_released):
		target.released.connect(_on_carried_released)
	target.start_carry(player)

func _release_carried() -> void:
	if carried_object == null:
		return
	carried_object.stop_carry()
	carried_object = null

func _on_carried_released() -> void:
	carried_object = null

func _process(_delta: float) -> void:
	if player == null or not _puzzle_mode_active:
		if _last_highlighted != null and is_instance_valid(_last_highlighted):
			_last_highlighted.set_highlight(false)
			_last_highlighted = null
		return

	# Podświetlenie (tylko gdy nic nie niesiemy)
	if carried_object == null:
		var nearest := _get_nearest_in_range()
		if nearest != _last_highlighted:
			if _last_highlighted != null and is_instance_valid(_last_highlighted):
				_last_highlighted.set_highlight(false)
			if nearest != null:
				nearest.set_highlight(true)
			_last_highlighted = nearest
	else:
		# Wyłącz highlight gdy niesiemy
		if _last_highlighted != null and is_instance_valid(_last_highlighted):
			_last_highlighted.set_highlight(false)
			_last_highlighted = null

		# Szczury zawsze pod obiektem — aktualizuj każdą klatkę
		if is_instance_valid(carried_object):
			_update_rats_under_object(carried_object.global_position)

func _update_rats_under_object(obj_pos: Vector3) -> void:
	var rat_manager := get_tree().get_first_node_in_group("rat_manager")
	if rat_manager == null:
		return
	var rats: Array = rat_manager.rats
	var count := rats.size()
	if count == 0:
		return
	# Małe kółko szczurów pod obiektem, aktualizowane co klatkę
	for i in range(count):
		var rat = rats[i]
		var angle: float = (TAU / count) * i
		var offset := Vector3(cos(angle) * 0.35, 0.0, sin(angle) * 0.35)
		var target_pos := Vector3(obj_pos.x + offset.x, 0.0, obj_pos.z + offset.z)
		# Szczury w trybie STATIC lub FOLLOW kieruj do nowej pozycji
		if rat.state == rat.State.FOLLOW or rat.state == rat.State.STATIC:
			rat.build_at(target_pos)
		elif rat.state == rat.State.TRAVEL_TO_BUILD:
			# Aktualizuj cel w locie
			rat.build_target = target_pos

func _send_rats_under_object(obj_pos: Vector3) -> void:
	# Znajdź rat_manager przez grupę lub referencję
	var rat_manager := get_tree().get_first_node_in_group("rat_manager")
	if rat_manager == null:
		return
	# Wyślij szczury w krąg pod obiektem
	var rats: Array = rat_manager.rats
	var count := rats.size()
	for i in range(count):
		var rat = rats[i]
		if rat.state == rat.State.FOLLOW or rat.state == rat.State.STATIC:
			var angle: float = (TAU / count) * i
			var offset := Vector3(cos(angle) * 0.4, 0.0, sin(angle) * 0.4)
			rat.build_at(obj_pos + offset)

# ── Znajdź najbliższy obiekt puzzle w zasięgu gracza ─────
# NIE używamy raycasta z kursorem — kamera izometryczna
# sprawia że kursor wskazuje inne miejsce niż obiekt 3D.
# Zamiast tego: zawsze działamy na najbliższy obiekt w zasięgu.
func _get_nearest_in_range() -> RigidBody3D:
	if player == null:
		return null
	var objects := get_tree().get_nodes_in_group("puzzle_objects")
	var best: RigidBody3D = null
	var best_dist := ability_range
	for obj in objects:
		if not (obj is RigidBody3D):
			continue
		var rigid_obj := obj as RigidBody3D
		var d: float = rigid_obj.global_position.distance_to(player.global_position)
		if d < best_dist:
			best_dist = d
			best = rigid_obj
	return best

# # ── Podświetlenie najbliższego obiektu ───────────────────
# func _process(_delta: float) -> void:
# 	if player == null or not _puzzle_mode_active:
# 		# Wyłącz podświetlenie gdy nie jesteśmy w puzzle
# 		if _last_highlighted != null and is_instance_valid(_last_highlighted):
# 			_last_highlighted.set_highlight(false)
# 			_last_highlighted = null
# 		return
#
# 	var nearest := _get_nearest_in_range()
# 	if nearest != _last_highlighted:
# 		if _last_highlighted != null and is_instance_valid(_last_highlighted):
# 			_last_highlighted.set_highlight(false)
# 		if nearest != null:
# 			nearest.set_highlight(true)
# 		_last_highlighted = nearest
