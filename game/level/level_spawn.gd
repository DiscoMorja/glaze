@tool
class_name LevelSpawn
extends Marker3D
## Places a character in a level: a SimArchetypes role, a name and a side.
## Only x/z matter; the character lands on whatever floor is below. Its
## rotation sets which way it faces (its vision cone points along -Z, the
## marker's forward arrow), snapped to 8 directions.

## NEUTRAL: townsfolk, who only fight if a crime turns them hostile.
enum Team { PLAYERS, ENEMIES, NEUTRAL }

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
## Party members: the co-op player who controls this character (0 = host,
## 1 = guest). Playing alone, the host controls everyone.
@export_range(0, 1) var player := 0
## Characters with the same pack join fights together. Empty: their parent
## node (group a pack under one node), or no pack if the parent is the
## level itself.
@export var pack := ""
## Dialogue knot (game/data/dialogue/*.dlg) talking to this character starts
## at; empty = nothing to say.
@export var dialogue := ""
## Items worn from the start (each in its own slot, see EquipRules). A
## weapon here replaces the role's.
@export var equipment: Array[String] = []
## Gold pieces carried.
@export var gold := 0
## Townsfolk who buy and sell (offer it in their dialogue with "~ trade").
@export var trades := false


func _ready() -> void:
	_update_label()


func faction() -> SimEntity.Faction:
	match team:
		Team.PLAYERS:
			return SimEntity.Faction.PLAYERS
		Team.NEUTRAL:
			return SimEntity.Faction.NEUTRAL
	return SimEntity.Faction.ENEMIES


## SimPerception.FACINGS index the marker points to (index 0 = north, -Z).
func facing() -> int:
	var forward := -global_basis.z
	return posmod(roundi(atan2(forward.x, -forward.z) / (PI / 4.0)), 8)


## The group name facts use (alive.<Group>): the pack, or the parent node's name.
func group_name() -> String:
	if pack != "":
		return pack
	var parent := get_parent()
	return "" if parent == null or parent is GameLevel else String(parent.name)


func pack_name() -> String:
	if pack != "":
		return pack
	var parent := get_parent()
	return "" if parent == null or parent is GameLevel else String(parent.get_path())


func _update_label() -> void:
	if is_inside_tree() and Engine.is_editor_hint():
		name = (entity_name if entity_name != "" else role).validate_node_name()
