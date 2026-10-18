class_name GiveCommand
extends SimCommand
## Outside combat: a party member hands an item to another party member (any
## distance, like passing it in the inventory). Stolen items stay stolen.

const TYPE := "give"

var from_id: int
var to_id: int
var index: int


func _init(p_from_id: int = -1, p_to_id: int = -1, p_index: int = 0) -> void:
	from_id = p_from_id
	to_id = p_to_id
	index = p_index


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return from_id


func validate(state: SimState) -> bool:
	var from := state.get_entity(from_id)
	var to := state.get_entity(to_id)
	if state.combat.active or from == null or to == null or from == to:
		return false
	if from.faction != SimEntity.Faction.PLAYERS or to.faction != SimEntity.Faction.PLAYERS:
		return false
	return from.is_alive() and to.is_alive() and index >= 0 and index < from.inventory.size()


func execute(state: SimState) -> void:
	var from := state.get_entity(from_id)
	var to := state.get_entity(to_id)
	var item := CrimeRules.move_item(from, to, index)
	var event := state.emit_event(SimEvent.Type.GIVEN, to.cell, to.id, from.id)
	event.text = item


func to_dict() -> Dictionary:
	return {"type": TYPE, "from_id": from_id, "to_id": to_id, "index": index}


static func from_dict(data: Dictionary) -> GiveCommand:
	return GiveCommand.new(data.from_id, data.to_id, data.index)
