@tool
extends EditorPlugin

const RAY_LENGTH := 2000.0

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return false
		
	var controller := _get_selected_controller()
	if controller == null:
		return false
	if not controller.paint_enabled:
		return false
	
	if controller.pattern_mode != HeatGrateController.PatternMode.INDICES:
		controller.pattern_mode = HeatGrateController.PatternMode.INDICES
	
	var world := camera.get_world_3d()
	if world == null:
		return false
	var origin := camera.project_ray_origin(mb.position)
	var dir := camera.project_ray_normal(mb.position)
	var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * RAY_LENGTH)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = 0xFFFFFFFF
	
	var hit := world.direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return false
	
	var collider := hit.get("collider")
	var grate := collider as HeatGrate
	if grate == null:
		return false
	
	var grates := controller.get_grates_editor()
	var idx := grates.find(grate)
	if idx < 0:
		return false
	
	var pattern_idx := maxi(controller.paint_pattern_index, 0)
	if mb.shift_pressed:
		controller.set_pattern_index_active(pattern_idx, idx, true)
	elif mb.ctrl_pressed or mb.meta_pressed:
		controller.set_pattern_index_active(pattern_idx, idx, false)
	else:
		var is_active := controller.is_index_active(pattern_idx, idx)
		controller.set_pattern_index_active(pattern_idx, idx, not is_active)
	
	return true

func _get_selected_controller() -> HeatGrateController:
	var sel := get_editor_interface().get_selection()
	if sel == null:
		return null
	var nodes := sel.get_selected_nodes()
	for n in nodes:
		var c := n as HeatGrateController
		if c:
			return c
	return null
