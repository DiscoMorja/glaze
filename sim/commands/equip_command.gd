class_name EquipCommand
extends SimCommand
## Outside combat: a party member wears an item from their bag in an
## equipment slot (EquipRules.SLOTS; "" = the item's own slot, for rings the
## first free one). Whatever was there, and anything in the way of a
## two-handed weapon, goes back in the bag. index UNEQUIP takes off what is
## in `slot` instead. Stats come from the items' properties (SimItems).

const TYPE := "equip"
const UNEQUIP := -1

var entity_id: int
var index: int
var slot: String


func _init(p_entity_id: int = -1, p_index: int = 0, p_slot: String = "") -> void:
	entity_id = p_entity_id
	index = p_index
	slot = p_slot


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return entity_id


func _target_slot(e: SimEntity) -> String:
	if slot != "" or index == UNEQUIP:
		return slot
	return EquipRules.default_slot(e, e.inventory[index])


func validate(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	if state.combat.active or e == null or not e.is_alive() or e.faction != SimEntity.Faction.PLAYERS:
		return false
	if index == UNEQUIP:
		return EquipRules.SLOTS.has(slot) and EquipRules.worn(e, slot) != ""
	if index < 0 or index >= e.inventory.size():
		return false
	return EquipRules.fits(_target_slot(e), e.inventory[index])


func execute(state: SimState) -> void:
	var e := state.get_entity(entity_id)
	var target := _target_slot(e)
	var item := ""
	if index != UNEQUIP:
		item = e.inventory[index]
		e.inventory.remove_at(index)
	var removed := EquipRules.put(e, target, item)
	e.inventory.append_array(removed)
	var event := state.emit_event(SimEvent.Type.EQUIPPED, e.cell, e.id)
	event.text = item  # "" = took something off


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "index": index, "slot": slot}


static func from_dict(data: Dictionary) -> EquipCommand:
	return EquipCommand.new(data.entity_id, data.index, data.slot)
