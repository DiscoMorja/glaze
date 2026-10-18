class_name SortItemCommand
extends SimCommand
## Moves an item to another slot in the same character's inventory (dragging
## it in the inventory). Free, at any time. The order matters a little: a
## pickpocket lifts the first item.

const TYPE := "sort_item"

var entity_id: int
var from_index: int
var to_index: int


func _init(p_entity_id: int = -1, p_from_index: int = 0, p_to_index: int = 0) -> void:
	entity_id = p_entity_id
	from_index = p_from_index
	to_index = p_to_index


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return entity_id


func validate(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	if e == null or not e.is_alive() or e.faction != SimEntity.Faction.PLAYERS:
		return false
	var size := e.inventory.size()
	return from_index >= 0 and from_index < size and to_index >= 0 and to_index < size and from_index != to_index


func execute(state: SimState) -> void:
	var e := state.get_entity(entity_id)
	var item: String = e.inventory[from_index]
	e.inventory.remove_at(from_index)
	e.inventory.insert(to_index, item)


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "from_index": from_index, "to_index": to_index}


static func from_dict(data: Dictionary) -> SortItemCommand:
	return SortItemCommand.new(data.entity_id, data.from_index, data.to_index)
