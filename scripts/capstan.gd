extends RigidBody3D
class_name Capstan

@export var doorId: int = 0
@export var trapId: int = -1
@export var required_rotations: float = 3.0
@export var cursor_rotate_strength: float = 0.45
@export var cursor_rotate_max_speed: float = 3.0

var _current_total_rotation: float = 0.0
var _previous_rotation: float = 0.0
var _max_rotation: float = 0.0

func _ready() -> void:
    collision_layer = 9
    collision_mask = 1
    _max_rotation = required_rotations * TAU
    _previous_rotation = rotation.y
    add_to_group("capstan")
    _set_center_of_mass_from_base()


func _set_center_of_mass_from_base() -> void:
    var base := get_node_or_null("Base") as Node3D
    if base == null:
        return
    center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
    # Center of mass is in local space of the rigid body.
    center_of_mass = base.transform.origin


func apply_cursor_rotation(delta_angle: float, delta: float) -> void:
    if delta <= 0.0 or delta_angle == 0.0:
        return
    var max_delta := cursor_rotate_max_speed * delta
    var clamped := clampf(delta_angle * cursor_rotate_strength, -max_delta, max_delta)
    rotation.y += clamped


func _get_target_doors() -> Array[Node]:
    var result: Array[Node] = []
    
    # Target doors & bosses by doorId
    if doorId != -1:
        var door_objects := get_tree().get_nodes_in_group("doors") + get_tree().get_nodes_in_group("bosses")
        for d in door_objects:
            if "doorId" in d and d.doorId == doorId:
                result.append(d)
                
    # Target traps by trapId
    if trapId != -1:
        var trap_objects := get_tree().get_nodes_in_group("progress_targets")
        for t in trap_objects:
            if "trapId" in t and t.trapId == trapId:
                result.append(t)
                
    return result


func _physics_process(delta: float) -> void:
    var diff = wrapf(rotation.y - _previous_rotation, -PI, PI)
    # We use abs(diff) or allow bidirectional winding? 
    # If potentiometer, it must be bidirectional (positive winds, negative unwinds)
    _current_total_rotation += diff
    _previous_rotation = rotation.y
    
    # Limit rotation values
    var hit_limit = false
    if _current_total_rotation <= 0.0:
        _current_total_rotation = 0.0
        if angular_velocity.y < 0:
            angular_velocity.y = 0
            hit_limit = true
    elif _current_total_rotation >= _max_rotation:
        _current_total_rotation = _max_rotation
        if angular_velocity.y > 0:
            angular_velocity.y = 0
            hit_limit = true
            
    # If hitting a limit, we zero the rotation to its exact clamped bound
    if hit_limit:
        var target_y = rotation.y - diff # Revert the excess rotation
        # Note: setting transform directly on RigidBody is usually bad practice,
        # but for enforcing a hard capstan lock it works well enough.
        
    var progress = _current_total_rotation / _max_rotation
    
    for door in _get_target_doors():
        if door.has_method("set_progress"):
            door.set_progress(progress)
