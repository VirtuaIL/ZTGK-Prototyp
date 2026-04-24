extends Node3D
class_name ScriptedEnemySpawner

enum EnemyType {
	BASIC_ENEMY,
	FLAMETHROWER_ENEMY,
	BOMBER_ENEMY,
	SNIPER_ENEMY,
	MORTAR_ENEMY,
	CUSTOM_SCENE
}

@export var enemy_type: EnemyType = EnemyType.BOMBER_ENEMY
@export var custom_scene: PackedScene
@export_node_path("Area3D") var trigger_node_path: NodePath
@export var spawn_once: bool = true

var _has_spawned: bool = false


func _ready() -> void:
	# Attempt to establish an automatic connection if a valid trigger node is assigned
	if not trigger_node_path.is_empty():
		var trigger = get_node_or_null(trigger_node_path)
		if trigger != null and trigger.has_signal("player_entered"):
			trigger.connect("player_entered", _on_trigger_activated)


func _on_trigger_activated() -> void:
	activate()


func activate() -> void:
	if spawn_once and _has_spawned:
		return
		
	var scene := _get_scene()
	if scene != null:
		var inst = scene.instantiate()
		var main_scene = get_tree().current_scene
		if main_scene != null:
			main_scene.add_child(inst)
			
			# Align physical positioning natively
			if inst is Node3D:
				inst.global_position = self.global_position
				inst.global_rotation = self.global_rotation
			
			# Forward level id metadata if the main scene manages bounds
			if main_scene.get("current_level_id") != null:
				inst.set_meta("level_id", main_scene.get("current_level_id"))
				
			_has_spawned = true


func _get_scene() -> PackedScene:
	match enemy_type:
		EnemyType.BASIC_ENEMY:
			return preload("res://scenes/enemies/enemy.tscn")
		EnemyType.FLAMETHROWER_ENEMY:
			return preload("res://scenes/enemies/flamethrower_enemy.tscn")
		EnemyType.BOMBER_ENEMY:
			return preload("res://scenes/enemies/bomber_enemy.tscn")
		EnemyType.SNIPER_ENEMY:
			return preload("res://scenes/enemies/sniper_enemy.tscn")
		EnemyType.MORTAR_ENEMY:
			return preload("res://scenes/enemies/mortar_enemy.tscn")
		EnemyType.CUSTOM_SCENE:
			return custom_scene
	return null
