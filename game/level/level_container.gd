@tool
class_name LevelContainer
extends Marker3D
## Places a chest (or crate, box...) holding items, optionally locked: it
## opens for whoever carries the item named in `key`, or breaks open when
## destroyed. Put it under a group's node (e.g. "Village") to make it theirs:
## taking from it while they are neutral is theft. See LootCommand.

@export var display_name := "Chest"
## How it looks (PropLooks): chest, barrel, crate, crate_large, basket, pot.
@export_enum("chest", "barrel", "crate", "crate_large", "basket", "pot") var look := "chest"
@export var items: Array[String] = []
## Item that unlocks it (e.g. "Camp key"); empty = no key.
@export var key := ""
## Thievery rank (with a lockpick) that opens it; 0 = can't be picked.
@export_range(0, 5) var lock_level := 0
@export var hp := 8


## The owning group's pack name, like LevelSpawn.pack_name(): the parent node,
## or none if the parent is the level itself.
func pack_name() -> String:
	var parent := get_parent()
	return "" if parent == null or parent is GameLevel else String(parent.get_path())


func group_name() -> String:
	var parent := get_parent()
	return "" if parent == null or parent is GameLevel else String(parent.name)
