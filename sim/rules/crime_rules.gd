class_name CrimeRules
extends RefCounted
## Crime and its witnesses. Neutral NPCs (Faction.NEUTRAL) who see the party
## commit a crime react: a first petty crime they see (a pickpocket) makes
## them suspicious; seen again, or a violent crime, and their whole group
## turns hostile (Faction.ENEMIES) and fights. Stolen items
## remember whose they were: a suspicious NPC who later sees someone carrying
## its group's goods turns hostile too.

enum Severity { PETTY, VIOLENT }


## A crime by `culprit` against `victim`: everyone neutral who sees it reacts.
## A violent crime against a neutral turns the victim's group hostile even
## if nobody else saw (they know who hit them).
static func commit(state: SimState, culprit: SimEntity, victim: SimEntity, severity: Severity) -> void:
	if culprit == null or culprit.faction != SimEntity.Faction.PLAYERS:
		return
	if severity == Severity.VIOLENT and victim != null and victim.faction == SimEntity.Faction.NEUTRAL:
		turn_hostile(state, victim, culprit)
	for watcher in _witnesses(state, culprit):
		if severity == Severity.VIOLENT or watcher.suspicious:
			turn_hostile(state, watcher, culprit)
		else:
			watcher.suspicious = true
			state.emit_event(SimEvent.Type.SUSPICIOUS, watcher.cell, watcher.id, culprit.id)


## Neutral NPCs who can see `culprit` now.
static func _witnesses(state: SimState, culprit: SimEntity) -> Array[SimEntity]:
	var result: Array[SimEntity] = []
	for e in state.entities:
		if e.faction == SimEntity.Faction.NEUTRAL and e.is_alive() and e.takes_turns() and SimPerception.can_see(state, e, culprit):
			result.append(e)
	return result


## Turns a neutral NPC and its group hostile; outside combat this starts a
## fight (they spotted the culprit), during one they join it.
static func turn_hostile(state: SimState, e: SimEntity, culprit: SimEntity = null) -> void:
	if e.faction != SimEntity.Faction.NEUTRAL:
		return
	var group: Array[SimEntity] = []
	for other in state.entities:
		if other.faction == SimEntity.Faction.NEUTRAL and other.is_alive() and (other == e or (e.pack > 0 and other.pack == e.pack)):
			group.append(other)
	for member in group:
		member.faction = SimEntity.Faction.ENEMIES
		member.suspicious = false
		member.sight = maxi(member.sight, SimArchetypes.ENEMY_SIGHT)
		state.emit_event(SimEvent.Type.TURNED_HOSTILE, member.cell, member.id, culprit.id if culprit != null else -1)
		if state.combat.active:
			CombatRules.join(state, member)
		else:
			member.in_combat = true
	if not state.combat.active:
		state.provoked = true
		if culprit != null:
			culprit.in_combat = true


## Real time: suspicious NPCs who see someone carrying their group's stolen
## goods turn hostile.
static func step(state: SimState) -> void:
	if state.combat.active:
		return
	for watcher in state.entities:
		if watcher.faction != SimEntity.Faction.NEUTRAL or not watcher.suspicious or not watcher.is_alive():
			continue
		for e in state.entities:
			if e.faction == SimEntity.Faction.PLAYERS and e.is_alive() and carries_goods_of(e, watcher.pack) \
					and SimPerception.can_see(state, watcher, e):
				state.emit_event(SimEvent.Type.RECOGNIZED, watcher.cell, watcher.id, e.id)
				turn_hostile(state, watcher, e)
				break


## Stolen items are tagged "pack:item" in `stolen` (the item itself stays in
## the inventory as usual).
static func mark_stolen(e: SimEntity, item: String, from_pack: int) -> void:
	e.stolen.append("%d:%s" % [from_pack, item])


static func is_stolen(e: SimEntity, item: String) -> bool:
	for tag in e.stolen:
		if tag.get_slice(":", 1) == item:
			return true
	return false


static func carries_goods_of(e: SimEntity, pack: int) -> bool:
	for tag in e.stolen:
		if int(tag.get_slice(":", 0)) == pack and e.inventory.has(tag.get_slice(":", 1)):
			return true
	return false


## Moves an item between characters, with its stolen tag if it has one.
static func move_item(from: SimEntity, to: SimEntity, index: int) -> String:
	var item: String = from.inventory[index]
	from.inventory.remove_at(index)
	to.inventory.append(item)
	for i in from.stolen.size():
		if from.stolen[i].get_slice(":", 1) == item:
			to.stolen.append(from.stolen[i])
			from.stolen.remove_at(i)
			break
	return item
