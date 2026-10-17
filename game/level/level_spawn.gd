@tool
class_name LevelSpawn
extends Marker3D
## Places a character in a level: a SimArchetypes role, a name and a side.
## Only x/z matter; the character lands on whatever floor is below.

enum Team { PLAYERS, ENEMIES }

@export var role := "thug":
	set(value):
		role = value
		_update_label()
@export var entity_name := "":
	set(value):
		entity_name = value
		_update_label()
@export var team: Team = Team.ENEMIES
@export var inventory: Array[String] = []
## Characters with the same pack join fights together. Empty: their parent
## node (group a pack under one node), or no pack if the parent is the
## level itself.
@export var pack := ""


func _ready() -> void:
	_update_label()


func faction() -> SimEntity.Faction:
	return SimEntity.Faction.PLAYERS if team == Team.PLAYERS else SimEntity.Faction.ENEMIES


func pack_name() -> String:
	if pack != "":
		return pack
	var parent := get_parent()
	return "" if parent == null or parent is GameLevel else String(parent.get_path())


func _update_label() -> void:
	if is_inside_tree() and Engine.is_editor_hint():
		name = (entity_name if entity_name != "" else role).validate_node_name()
