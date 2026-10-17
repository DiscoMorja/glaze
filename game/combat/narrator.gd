class_name Narrator
extends RefCounted
## Turns sim events into combat-log lines (GDD §5.6). Returns "" for events
## that would only be noise.

const SURFACE_NAMES := ["nothing", "water", "oil", "ice"]


## Describes a batch of events in order. Damage from the world (fire, falls,
## collisions) is summed per entity into one line at the end of the batch, so
## per-tick burn damage doesn't flood the log.
static func describe_all(state: SimState, events: Array[SimEvent]) -> Array[String]:
	var lines: Array[String] = []
	var world_damage := {}  # entity id -> total
	for e in events:
		if e.type == SimEvent.Type.DAMAGED and e.other_id < 0:
			world_damage[e.entity_id] = world_damage.get(e.entity_id, 0) + e.amount
			continue
		var line := describe(state, e)
		if line != "":
			lines.append(line)
	for id: int in world_damage:
		lines.append("%s takes %d damage from the environment." % [_name(state, id), world_damage[id]])
	return lines


static func describe(state: SimState, e: SimEvent) -> String:
	var who := _name(state, e.entity_id)
	var other := _name(state, e.other_id)
	match e.type:
		SimEvent.Type.TURN_STARTED:
			return "— Round %d: %s —" % [state.combat.round_number, "your turn" if e.amount == SimEntity.Faction.PLAYERS else "enemy turn"]
		SimEvent.Type.COMBAT_ENDED:
			return "Victory!" if e.amount == SimEntity.Faction.PLAYERS else "Defeat."
		SimEvent.Type.CAST:
			return "%s casts %s." % [who, SimAbilities.NAMES[e.amount]]
		SimEvent.Type.ATTACKED:
			return "%s hits %s." % [other, who]
		SimEvent.Type.DAMAGED:
			return "%s takes %d damage." % [who, e.amount]
		SimEvent.Type.DIED:
			var entity := state.get_entity(e.entity_id)
			return "%s dies." % who if entity != null and entity.takes_turns() else "%s breaks." % who
		SimEvent.Type.SPILLED:
			return "%s spills %s everywhere." % [who, SURFACE_NAMES[e.amount]]
		SimEvent.Type.FELL:
			return "%s falls %d level%s." % [who, e.amount, "" if e.amount == 1 else "s"] if e.amount > 1 else ""
		SimEvent.Type.TELEPORTED:
			return "%s teleports %s." % [other, who]
		SimEvent.Type.SHOVED:
			return "%s shoves %s." % [other, who]
		SimEvent.Type.COLLIDED:
			return "%s slams into %s." % [who, other if e.other_id >= 0 else "a wall"]
		SimEvent.Type.STOLEN:
			return "%s steals %s from %s." % [other, e.text, who]
		SimEvent.Type.SLIPPED:
			return "%s slips on the ice and goes down." % who
	return ""


static func _name(state: SimState, id: int) -> String:
	var e := state.get_entity(id)
	return e.name if e != null else "?"
