extends Resource
class_name WaveGroup

## Typ wroga do zespawnowania
@export var spawn_kind: MainSpawner.SpawnKind = MainSpawner.SpawnKind.BASIC_ENEMY

## Minimalna ilość wrogów
@export var count_min: int = 1

## Maksymalna ilość wrogów
@export var count_max: int = 3

## Scena do użycia gdy spawn_kind == CUSTOM_SCENE
@export var custom_scene: PackedScene
