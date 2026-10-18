class_name UseItemCommand
extends SimCommand
## A character uses (eats, drinks, applies) an item from their inventory on
## themselves or an ally next to them. What it does comes from the item's
## properties (SimItems: heal, temperature), so any item with them works.
## Costs AP_COST in combat, on the user's turn; free outside.

const TYPE := "use_item"
const AP_COST := 1

var user_id: int
var index: int
var target_id: int


func _init(p_user_id: int = -1, p_index: int = 0, p_target_id: int = -1) -> void:
	user_id = p_user_id
	index = p_index
	target_id = p_target_id if p_target_id >= 0 else p_user_id


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return user_id


func validate(state: SimState) -> bool:
	var user := state.get_entity(user_id)
	var target := state.get_entity(target_id)
	if not CombatRules.can_act(state, user, AP_COST) or target == null or not target.is_alive() or not target.takes_turns():
		return false
	if index < 0 or index >= user.inventory.size() or not SimItems.is_usable(user.inventory[index]):
		return false
	if target != user and (target.faction != user.faction or not SimAbilities.is_adjacent(user.cell, target.cell)):
		return false
	return true


func execute(state: SimState) -> void:
	var user := state.get_entity(user_id)
	var target := state.get_entity(target_id)
	CombatRules.spend(state, user, AP_COST)
	var item: String = user.inventory[index]
	user.inventory.remove_at(index)
	var tag := user.stolen.find_custom(func(t: String) -> bool: return t.get_slice(":", 1) == item)
	if tag >= 0 and not user.inventory.has(item):
		user.stolen.remove_at(tag)
	var used := state.emit_event(SimEvent.Type.ITEM_USED, target.cell, target.id, user.id)
	used.text = item
	var heal := SimItems.amount(item, "heal")
	if heal > 0:
		EntityOps.heal(state, target, heal, user.id)
	var warmth := SimItems.amount(item, "temperature")
	if warmth != 0:
		EntityOps.change_temperature(state, target, warmth, user.id)


func to_dict() -> Dictionary:
	return {"type": TYPE, "user_id": user_id, "index": index, "target_id": target_id}


static func from_dict(data: Dictionary) -> UseItemCommand:
	return UseItemCommand.new(data.user_id, data.index, data.target_id)
