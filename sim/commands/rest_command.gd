class_name RestCommand
extends SimCommand
## The party camps: outside combat, with something to rest on (an item with
## the "rest" property, e.g. a Bedroll) somewhere in the party's packs, and no
## hostile fighter within SAFE_RADIUS cells of anyone. Everyone standing heals
## to full and shakes off statuses and cooldowns; the fallen stay down (Revive
## them first). The item is kept.

const TYPE := "rest"
const SAFE_RADIUS := 12

var resting_id: int


func _init(p_resting_id: int = -1) -> void:
	resting_id = p_resting_id


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return resting_id


## Why the party can't rest now ("" = it can). The UI shows it.
static func blocker(state: SimState, e: SimEntity) -> String:
	if e == null or e.faction != SimEntity.Faction.PLAYERS or not e.is_alive():
		return "Can't rest"
	if state.combat.active:
		return "Not during a fight"
	var party := _party(state)
	var has_bed := party.any(func(p: SimEntity) -> bool:
		return p.inventory.any(func(item: String) -> bool: return SimItems.has_property(item, "rest")))
	if not has_bed:
		return "Needs a bedroll"
	for other in state.entities:
		if other.faction == SimEntity.Faction.ENEMIES and other.is_alive() and other.takes_turns():
			for p in party:
				if maxi(absi(other.cell.x - p.cell.x), absi(other.cell.z - p.cell.z)) <= SAFE_RADIUS:
					return "Enemies are near"
	return ""


static func _party(state: SimState) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	for p in state.entities:
		if p.faction == SimEntity.Faction.PLAYERS and p.takes_turns():
			result.append(p)
	return result


func validate(state: SimState) -> bool:
	return blocker(state, state.get_entity(resting_id)) == ""


func execute(state: SimState) -> void:
	for p in _party(state):
		if not p.is_alive():
			continue
		EntityOps.heal(state, p, p.max_hp - p.hp, resting_id)
		p.temperature = 0
		p.temp_turns = 0
		p.slowed = 0
		p.stagger = 0
		p.knocked_down = false
		p.knocked_skipping = false
		p.cooldowns.fill(0)
		p.travel.clear()
	state.emit_event(SimEvent.Type.RESTED, state.get_entity(resting_id).cell, resting_id)


func to_dict() -> Dictionary:
	return {"type": TYPE, "resting_id": resting_id}


static func from_dict(data: Dictionary) -> RestCommand:
	return RestCommand.new(data.resting_id)
