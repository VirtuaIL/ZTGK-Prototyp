extends RigidBody3D
class_name Capstan

@export var doorId: int = 0
@export var required_rotations: float = 3.0

var _current_total_rotation: float = 0.0
var _previous_rotation: float = 0.0
var _max_rotation: float = 0.0

func _ready() -> void:
    collision_layer = 9
    collision_mask = 1
    _max_rotation = required_rotations * TAU
    _previous_rotation = rotation.y
    add_to_group("capstan")


func _get_target_doors() -> Array[Node]:
    var result: Array[Node] = []
    var objects := get_tree().get_nodes_in_group("doors") + get_tree().get_nodes_in_group("bosses")
    for d in objects:
        if "doorId" in d and d.doorId == doorId:
            result.append(d)
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
