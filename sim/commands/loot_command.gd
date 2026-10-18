class_name LootCommand
extends SimCommand
## Outside combat: a party member takes an item (index), or everything
## (index -1), from something next to them that holds items and isn't a
## living character: a chest, a broken crate, a corpse. A locked one needs its
## key (`lock` names the item) in the looter's pack; the first take unlocks it
## for good. Bashing or burning it open works too (a destroyed container keeps
## its contents). Taking what belongs to townsfolk who are still neutral is
## theft: the items are tagged stolen and witnesses react (CrimeRules).

const TYPE := "loot"
const ALL := -1

var looter_id: int
var container_id: int
var index: int


func _init(p_looter_id: int = -1, p_container_id: int = -1, p_index: int = ALL) -> void:
	looter_id = p_looter_id
	container_id = p_container_id
	index = p_index


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return looter_id


## Why `looter` can't open `container` right now ("" = it can). The UI shows
## it; validate() also needs something to take.
static func blocker(state: SimState, looter: SimEntity, container: SimEntity) -> String:
	if looter == null or container == null or looter == container:
		return "Nothing to open"
	if not is_container(container):
		return "Nothing to open"
	if state.combat.active:
		return "Not during a fight"
	if looter.faction != SimEntity.Faction.PLAYERS or not looter.is_alive() or not looter.takes_turns():
		return "Can't do that"
	if container.lock != "" and container.is_alive() and not looter.inventory.has(container.lock):
		return "Locked — needs %s" % container.lock
	if not SimAbilities.is_adjacent(looter.cell, container.cell) and looter.cell != container.cell:
		return "Too far"
	return ""


## Something that holds items and can be looted: not a living character, and
## not one of the party (their own things move with Give).
static func is_container(e: SimEntity) -> bool:
	if e == null or e.faction == SimEntity.Faction.PLAYERS:
		return false
	if e.takes_turns() and e.is_alive():
		return false
	return not e.inventory.is_empty() or e.lock != ""


func validate(state: SimState) -> bool:
	var looter := state.get_entity(looter_id)
	var container := state.get_entity(container_id)
	if blocker(state, looter, container) != "":
		return false
	if index == ALL:
		return not container.inventory.is_empty()
	return index >= 0 and index < container.inventory.size()


func execute(state: SimState) -> void:
	var looter := state.get_entity(looter_id)
	var container := state.get_entity(container_id)
	if container.lock != "" and container.is_alive():
		var unlocked := state.emit_event(SimEvent.Type.UNLOCKED, container.cell, container.id, looter.id)
		unlocked.text = container.lock
		container.lock = ""
	container.lock = ""  # (a broken one has no lock left either)
	var owner_pack := neutral_owner(state, container)
	var count := container.inventory.size() if index == ALL else 1
	for _i in count:
		var item := CrimeRules.move_item(container, looter, 0 if index == ALL else index)
		if owner_pack != 0 and not CrimeRules.is_stolen(looter, item):
			CrimeRules.mark_stolen(looter, item, owner_pack)
		var event := state.emit_event(SimEvent.Type.LOOTED, container.cell, container.id, looter.id)
		event.text = item
	if owner_pack != 0:
		CrimeRules.commit(state, looter, container, CrimeRules.Severity.PETTY)


## The pack whose things these are, if anyone in it is still neutral (taking
## them is theft), else 0.
static func neutral_owner(state: SimState, container: SimEntity) -> int:
	if container.pack <= 0:
		return 0
	for e in state.entities:
		if e.pack == container.pack and e.faction == SimEntity.Faction.NEUTRAL and e.is_alive():
			return container.pack
	return 0


func to_dict() -> Dictionary:
	return {"type": TYPE, "looter_id": looter_id, "container_id": container_id, "index": index}


static func from_dict(data: Dictionary) -> LootCommand:
	return LootCommand.new(data.looter_id, data.container_id, data.index)
