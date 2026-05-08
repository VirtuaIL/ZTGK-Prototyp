extends Area3D

@onready var ui_layer = $CanvasLayer
@onready var cheese_label = $CanvasLayer/Panel/VBox/CheeseLabel
@onready var btn_red = $CanvasLayer/Panel/VBox/HBox/BtnRed
@onready var btn_green = $CanvasLayer/Panel/VBox/HBox/BtnGreen
@onready var btn_electric = $CanvasLayer/Panel/VBox/HBox/BtnElectric

var rat_mgr = null
var is_player_in_range = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	btn_red.pressed.connect(func(): _buy_rats(1)) # Red
	btn_green.pressed.connect(func(): _buy_rats(2)) # Green
	btn_electric.pressed.connect(func(): _buy_rats(3)) # Electric
	
	# Wait one frame and recolor the mesh to gold
	call_deferred("_recolor_mesh_to_gold")

func _recolor_mesh_to_gold() -> void:
	var visual = $Visual
	if visual:
		# Find mesh instance inside fbx and override its material
		_recursive_set_material(visual)

func _recursive_set_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.84, 0.0) # Gold
		mat.metallic = 0.8
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.8, 0.0)
		mat.emission_energy_multiplier = 0.5
		
		# Set override for all surfaces
		if node.mesh:
			for i in range(node.mesh.get_surface_count()):
				node.set_surface_override_material(i, mat)
		node.material_override = mat
	for child in node.get_children():
		_recursive_set_material(child)

func _process(_delta: float) -> void:
	if is_player_in_range and ui_layer.visible:
		_update_ui()

func _update_ui() -> void:
	cheese_label.text = "Sklep serow jest wylaczony"
	btn_red.disabled = true
	btn_green.disabled = true
	btn_electric.disabled = true

func _buy_rats(rat_type: int) -> void:
	_update_ui()

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_in_range = true
		ui_layer.visible = true
		_update_ui()

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_in_range = false
		ui_layer.visible = false
