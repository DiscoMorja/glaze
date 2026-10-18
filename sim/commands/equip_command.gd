class_name EquipCommand
extends SimCommand
## Outside combat: a party member wears an item from their inventory in the
## slot its "slot" property names (weapon or armour); what they wore goes back
## in the bag. index -1 takes off whatever is in `slot` instead. Damage and
## armour come from the item's properties (SimItems).

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


func validate(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	if state.combat.active or e == null or not e.is_alive() or e.faction != SimEntity.Faction.PLAYERS:
		return false
	if index == UNEQUIP:
		return worn(e, slot) != ""
	return index >= 0 and index < e.inventory.size() and SimItems.slot_of(e.inventory[index]) != ""


## What `e` wears in `slot` ("" = nothing).
static func worn(e: SimEntity, p_slot: String) -> String:
	match p_slot:
		"weapon":
			return e.weapon
		"armor":
			return e.armor_item
	return ""


func execute(state: SimState) -> void:
	var e := state.get_entity(entity_id)
	var item := ""
	var target_slot := slot
	if index != UNEQUIP:
		item = e.inventory[index]
		e.inventory.remove_at(index)
		target_slot = SimItems.slot_of(item)
	var old := worn(e, target_slot)
	if old != "":
		e.inventory.append(old)
	match target_slot:
		"weapon":
			e.weapon = item
			e.weapon_damage = SimItems.amount(item, "damage")
		"armor":
			e.armor_item = item
			e.armor = SimItems.amount(item, "armor")
	var event := state.emit_event(SimEvent.Type.EQUIPPED, e.cell, e.id)
	event.text = item if item != "" else old


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "index": index, "slot": slot}


static func from_dict(data: Dictionary) -> EquipCommand:
	return EquipCommand.new(data.entity_id, data.index, data.slot)
