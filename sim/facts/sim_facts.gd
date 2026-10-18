class_name SimFacts
extends RefCounted
## World facts that dialogue and quests read. Most are worked out from the
## world as it is (so they can't drift from it); the rest are remembered facts
## that dialogue effects set (state.facts, integers, 0 when never set).
##
## Worked out:
##   alive.<Group>        living members of a group (LevelSpawn pack / parent)
##   dead.<Group>         fallen members
##   hostile.<Group>      1 if any living member is hostile (an enemy)
##   has.<Item>           how many the party carries (_ for spaces: has.Silver_ring)
##   combat               1 during a fight
##   quest.<id>.known     1 once the quest is known
##   quest.<id>.<outcome> 1 if it ended that way
##   self.<x>             the NPC being talked to: self.suspicious, self.hostile,
##                        self.alive, self.has.<Item>
## Anything else is a remembered fact.


static func value(state: SimState, name: String, context: Dictionary = {}) -> int:
	if name.begins_with("self."):
		var npc: SimEntity = state.get_entity(context.get("npc", -1))
		return _of_entity(npc, name.trim_prefix("self.")) if npc != null else 0
	var head := name.get_slice(".", 0)
	var rest := name.substr(head.length() + 1)
	match head:
		"alive":
			return _count(state, rest, func(e: SimEntity) -> bool: return e.is_alive())
		"dead":
			return _count(state, rest, func(e: SimEntity) -> bool: return not e.is_alive())
		"hostile":
			return 1 if _count(state, rest, func(e: SimEntity) -> bool:
				return e.is_alive() and e.faction == SimEntity.Faction.ENEMIES) > 0 else 0
		"has":
			var item := rest.replace("_", " ")
			var total := 0
			for e in state.entities:
				if e.faction == SimEntity.Faction.PLAYERS:
					total += e.inventory.count(item)
			return total
		"combat":
			return 1 if state.combat.active else 0
		"quest":
			return QuestRules.fact(state, rest)
	return state.facts.get(name, 0)


static func set_fact(state: SimState, name: String, value: int) -> void:
	state.facts[name] = value


static func _count(state: SimState, group: String, test: Callable) -> int:
	var n := 0
	for e in state.entities:
		if e.group == group and e.takes_turns() and test.call(e):
			n += 1
	return n


static func _of_entity(e: SimEntity, what: String) -> int:
	if what.begins_with("has."):
		return e.inventory.count(what.trim_prefix("has.").replace("_", " "))
	match what:
		"suspicious":
			return 1 if e.suspicious else 0
		"hostile":
			return 1 if e.faction == SimEntity.Faction.ENEMIES else 0
		"alive":
			return 1 if e.is_alive() else 0
	return 0
