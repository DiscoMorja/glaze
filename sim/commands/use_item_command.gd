class_name UseItemCommand
extends SimCommand
## A character uses (eats, drinks, applies) an item from their inventory on
## themselves or an ally next to them. What it does comes from the item's
## properties (SimItems: heal, temperature), so any item with them works.
## A tome ("teaches") is read by its owner outside combat and teaches its
## skill, if the reader's rank in its school is high enough.
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
	var skill := SimItems.teaches(user.inventory[index])
	if skill >= 0:
		return target == user and not state.combat.active and not user.abilities.has(skill) and SimAbilities.has_rank(user, skill)
	return true


## Why `user` can't read the tome at `index` ("" = it can, or it isn't one).
static func cant_learn(state: SimState, user: SimEntity, item: String) -> String:
	var skill := SimItems.teaches(item)
	if skill < 0:
		return ""
	if user.abilities.has(skill):
		return "Already known"
	if not SimAbilities.has_rank(user, skill):
		return SimAbilities.lacks(user, skill)
	if state.combat.active:
		return "Not during a fight"
	return ""


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
	var skill := SimItems.teaches(item)
	if skill >= 0:
		user.abilities.append(skill)
		var learned := state.emit_event(SimEvent.Type.LEARNED, user.cell, user.id, -1, skill)
		learned.text = SimAbilities.NAMES[skill]


func to_dict() -> Dictionary:
	return {"type": TYPE, "user_id": user_id, "index": index, "target_id": target_id}


static func from_dict(data: Dictionary) -> UseItemCommand:
	return UseItemCommand.new(data.user_id, data.index, data.target_id)
