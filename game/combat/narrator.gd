class_name Narrator
extends RefCounted
## Turns sim events into combat-log lines (GDD §5.6). Returns "" for events
## that would only be noise.

const SURFACE_NAMES := ["nothing", "water", "oil", "ice", "vines", "poison"]


## Describes a batch of events in order. Damage from the world (fire, falls,
## collisions) is summed per entity into one line at the end of the batch, so
## per-tick burn damage doesn't flood the log.
static func describe_all(state: SimState, events: Array[SimEvent]) -> Array[String]:
	var lines: Array[String] = []
	var world_damage := {}  # [entity id, element] -> total
	var xp := 0  # the party shares XP: one line, not one per member
	for e in events:
		if e.type == SimEvent.Type.XP_GAINED and xp == 0:
			xp = e.amount
			lines.append("The party gains %d XP." % xp)
		elif e.type == SimEvent.Type.XP_GAINED and e.amount != xp:
			xp = e.amount
			lines.append("The party gains %d XP." % xp)
		if e.type == SimEvent.Type.DAMAGED and e.other_id < 0:
			var key := [e.entity_id, e.element]
			world_damage[key] = world_damage.get(key, 0) + e.amount
			continue
		var line := describe(state, e)
		if line != "":
			lines.append(line)
	for key: Array in world_damage:
		var who := _name(state, key[0])
		if key[1] == EntityOps.Element.FIRE:
			lines.append("%s burns for %d." % [who, world_damage[key]])
		else:
			lines.append("%s takes %d damage." % [who, world_damage[key]])
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
			return "%s blinks." % who if e.entity_id == e.other_id else "%s teleports %s." % [other, who]
		SimEvent.Type.HEALED:
			return "%s heals %s for %d." % [other, who, e.amount] if e.other_id != e.entity_id else "%s heals for %d." % [who, e.amount]
		SimEvent.Type.FROZE:
			return ""
		SimEvent.Type.SHOVED:
			return "%s shoves %s." % [other, who]
		SimEvent.Type.COLLIDED:
			return "%s slams into %s." % [who, other if e.other_id >= 0 else "a wall"]
		SimEvent.Type.STOLEN:
			return "%s steals %s from %s." % [other, e.text, who]
		SimEvent.Type.SPOTTED:
			return "%s spots %s!" % [other, who]
		SimEvent.Type.COMBAT_STARTED:
			return "Combat!"
		SimEvent.Type.SLIPPED:
			return "%s slips on the ice and goes down." % who
		SimEvent.Type.QUEST_STARTED:
			return "New quest: %s." % (QuestRules.quests[e.text].title if QuestRules.quests.has(e.text) else e.text)
		SimEvent.Type.QUEST_ENDED:
			var entry := QuestRules.journal(state, e.text) if QuestRules.quests.has(e.text) else ["", ""]
			return "Quest ended: %s — %s" % [entry[0], entry[1]]
		SimEvent.Type.SUSPICIOUS:
			return "%s eyes %s suspiciously." % [who, other]
		SimEvent.Type.TURNED_HOSTILE:
			return "%s turns hostile!" % who
		SimEvent.Type.RECOGNIZED:
			return "%s recognizes the stolen goods on %s!" % [who, other]
		SimEvent.Type.PICKPOCKETED:
			return "%s lifts %s from %s." % [other, e.text, who]
		SimEvent.Type.SHOCKWAVE:
			return "%s slams the ground." % who
		SimEvent.Type.ITEM_USED:
			return "%s uses %s." % [other, e.text] if e.other_id == e.entity_id else "%s gives %s %s." % [other, who, e.text]
		SimEvent.Type.RESTED:
			return "The party rests and recovers."
		SimEvent.Type.TRADED:
			return "%s trades with %s (%s)." % [other, who, ("pays %d gold" % e.amount) if e.amount > 0 else ("gets %d gold" % -e.amount) if e.amount < 0 else "even"]
		SimEvent.Type.EQUIPPED:
			return "%s equips %s." % [who, e.text] if e.text != "" else ""
		SimEvent.Type.LEVELED_UP:
			return "%s reaches level %d!" % [who, e.amount]
		SimEvent.Type.XP_GAINED:
			return ""  # summed into one line by describe_all()
		SimEvent.Type.LOOTED:
			return "%s takes %s from %s." % [other, e.text, who]
		SimEvent.Type.UNLOCKED:
			return "%s unlocks %s with the %s." % [other, who, e.text]
		SimEvent.Type.GIVEN:
			return "%s gives %s to %s." % [other, e.text, who]
		SimEvent.Type.REVIVED:
			return "%s revives %s." % [other, who]
		SimEvent.Type.KNOCKED_DOWN:
			return "%s is knocked down!" % who
		SimEvent.Type.STOOD_UP:
			return "%s helps %s up." % [other, who] if e.other_id >= 0 else "%s gets up." % who
		SimEvent.Type.TURN_SKIPPED:
			return "%s can't act this turn." % who
		SimEvent.Type.FROZEN:
			return "%s freezes solid!" % who
		SimEvent.Type.THAWED:
			return "%s thaws." % who
		SimEvent.Type.BURNING:
			return "%s catches fire!" % who
		SimEvent.Type.SLOWED:
			return "%s is slowed down." % who
		SimEvent.Type.EXPLODED:
			return "The poison cloud explodes!"
		SimEvent.Type.PINNED:
			return "%s is pinned in place." % who
		SimEvent.Type.DISTRACTED:
			return "%s looks the other way." % who
		SimEvent.Type.LEARNED:
			return "%s learns %s." % [who, e.text]
		SimEvent.Type.GREW:
			return "Vines burst from the ground."
		SimEvent.Type.BLIGHTED:
			return "Rot spreads."
	return ""


static func _name(state: SimState, id: int) -> String:
	var e := state.get_entity(id)
	return e.name if e != null else "?"
