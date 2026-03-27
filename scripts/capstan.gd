extends StaticBody3D
class_name Capstan

@export var doorId: int = 0
@export var required_rotations: float = 12.0

signal object_reset

var _current_total_rotation: float = 0.0
var _max_rotation: float = 0.0

var is_surrounded: bool = false
var carrier_rats: Array[CharacterBody3D] = []
var carrier_available_max: int = 0
var carrier_brush_desired: int = 0

func _ready() -> void:
    _max_rotation = required_rotations * TAU
    add_to_group("capstan")


func _get_target_doors() -> Array[Node]:
    var result: Array[Node] = []
    var objects := get_tree().get_nodes_in_group("doors") + get_tree().get_nodes_in_group("bosses")
    for d in objects:
        if "doorId" in d and d.doorId == doorId:
            result.append(d)
    return result


func set_highlight(enabled: bool) -> void:
    var mesh1: CSGBox3D = get_node_or_null("Arm1")
    var mesh2: CSGBox3D = get_node_or_null("Arm2")
    var base: CSGCylinder3D = get_node_or_null("Base")
    
    var highlight_mat = StandardMaterial3D.new()
    highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    highlight_mat.albedo_color = Color.YELLOW
    highlight_mat.cull_mode = BaseMaterial3D.CULL_FRONT
    highlight_mat.no_depth_test = true
    highlight_mat.grow = true
    highlight_mat.grow_amount = 0.03
    
    if mesh1: mesh1.material_overlay = highlight_mat if enabled else null
    if mesh2: mesh2.material_overlay = highlight_mat if enabled else null
    if base: base.material_overlay = highlight_mat if enabled else null

func add_capstan_angle_diff(diff: float) -> void:
    var old_total = _current_total_rotation
    _current_total_rotation += diff
    
    if _current_total_rotation < 0.0:
        _current_total_rotation = 0.0
        rotation.y -= (diff - (_current_total_rotation - old_total))
    elif _current_total_rotation > _max_rotation:
        _current_total_rotation = _max_rotation
        rotation.y -= (diff - (_current_total_rotation - old_total))
    else:
        rotation.y += diff
    
    var progress = _current_total_rotation / _max_rotation
    
    for door in _get_target_doors():
        if door.has_method("set_progress"):
            door.set_progress(progress)

