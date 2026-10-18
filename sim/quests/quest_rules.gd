class_name QuestRules
extends RefCounted
## Quests as outcomes, not steps (CLAUDE.md rule 8, GDD 6). A quest
## (game/data/quests/*.quest) is known once a fact says so, and ends the first
## time one of its outcomes' predicates holds, however the world got there.
##
##   === quest bandits
##   title: The bandit problem
##   known: bandits_known
##   active: The bandits on the hill have the village scared.
##   outcome cleared: alive.Bandits == 0
##     The bandits on the hill are dead.
##   outcome turned: hostile.Village
##     The village turned on us.
##
## Indented lines after an outcome are its journal text. Progress lives in
## state.quests: id -> {"known": bool, "outcome": name or ""}.

## Quest id -> {id, title, known (expr), active (text), outcomes: [{name, when, text}]}.
static var quests := {}
## Ids in the order they were registered (journal order).
static var order: Array[String] = []
static var errors: Array[String] = []


static func register(text: String, source: String = "") -> void:
	var quest: Dictionary = {}
	var outcome: Dictionary = {}
	var number := 0
	for raw in text.split("\n"):
		number += 1
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("=== quest "):
			var id := line.trim_prefix("=== quest ").strip_edges()
			quest = {"id": id, "title": id, "known": null, "active": "", "outcomes": []}
			quests[id] = quest
			if not order.has(id):
				order.append(id)
			outcome = {}
			continue
		if quest.is_empty():
			errors.append("%s:%d: outside a quest" % [source, number])
			continue
		if raw.begins_with(" ") or raw.begins_with("\t"):
			if outcome.is_empty():
				errors.append("%s:%d: indented text outside an outcome" % [source, number])
			else:
				outcome.text = (outcome.text + " " + line).strip_edges()
			continue
		if line.begins_with("outcome "):
			var colon := line.find(":")
			var when: Variant = SimExpr.parse(line.substr(colon + 1)) if colon != -1 else null
			if when == null:
				errors.append("%s:%d: bad outcome (%s)" % [source, number, SimExpr.last_error])
				continue
			outcome = {"name": line.substr(8, colon - 8).strip_edges(), "when": when, "text": ""}
			quest.outcomes.append(outcome)
			continue
		var key := line.get_slice(":", 0).strip_edges()
		var value := line.substr(line.find(":") + 1).strip_edges()
		match key:
			"title":
				quest.title = value
			"active":
				quest.active = value
			"known":
				quest.known = SimExpr.parse(value)
				if quest.known == null:
					errors.append("%s:%d: bad known (%s)" % [source, number, SimExpr.last_error])
			_:
				errors.append("%s:%d: unknown key %s" % [source, number, key])


static func clear() -> void:
	quests.clear()
	order.clear()
	errors.clear()


## After every command and tick: quests become known, and end when an
## outcome holds.
static func step(state: SimState) -> void:
	for id in order:
		var quest: Dictionary = quests[id]
		var progress: Dictionary = state.quests.get(id, {"known": false, "outcome": ""})
		if progress.outcome != "":
			continue
		var changed := false
		if not progress.known and quest.known != null and SimExpr.holds(state, quest.known):
			progress.known = true
			changed = true
			var event := state.emit_event(SimEvent.Type.QUEST_STARTED)
			event.text = id
		for outcome: Dictionary in quest.outcomes:
			if SimExpr.holds(state, outcome.when):
				progress.outcome = outcome.name
				progress.known = true
				changed = true
				var event := state.emit_event(SimEvent.Type.QUEST_ENDED)
				event.text = id
				break
		if changed:
			state.quests[id] = progress


## quest.<id>.known / quest.<id>.<outcome> (see SimFacts).
static func fact(state: SimState, rest: String) -> int:
	var id := rest.get_slice(".", 0)
	var what := rest.substr(id.length() + 1)
	var progress: Dictionary = state.quests.get(id, {})
	if progress.is_empty():
		return 0
	if what == "known":
		return 1 if progress.known else 0
	if what == "done":
		return 1 if progress.outcome != "" else 0
	return 1 if progress.outcome == what else 0


## Journal text for a quest in this state: [title, text, ended].
static func journal(state: SimState, id: String) -> Array:
	var quest: Dictionary = quests[id]
	var progress: Dictionary = state.quests.get(id, {})
	if progress.get("outcome", "") != "":
		for outcome: Dictionary in quest.outcomes:
			if outcome.name == progress.outcome:
				return [quest.title, outcome.text, true]
	return [quest.title, quest.active, false]
