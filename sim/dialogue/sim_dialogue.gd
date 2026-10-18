class_name SimDialogue
extends RefCounted
## Conversations, written in a small ink-like format (game/data/dialogue/*.dlg)
## and run inside the sim, so they are deterministic and shared in co-op.
##
##   # comment
##   === merchant                         a knot: a named block
##   Merchant: Careful on the hill road.  a line (Name: text), or plain narration
##   {self.suspicious} Merchant: Hm.      {condition} in front of any statement
##   ~ bandits_known = 1                  an effect: name = / += / -= expression
##   ~ give Silver ring                   the NPC hands the talker an item it has
##   ~ take Gold                          the talker hands the NPC an item
##   * [Tell me about them.] -> knot      a choice; a block of them ends a page
##   * {cond} [Only sometimes.] -> knot
##   -> knot                              jump; -> END ends the conversation
##
## Knot names are global across files. NPCs start at the knot named in their
## LevelSpawn.dialogue. A running conversation is state.conversation: the
## lines of the current page and the choices (or none, at the end).
##
## The game layer reads the files and register()s their text; the sim only
## ever sees strings.

## Knot name -> Array of statements (see _parse_line()).
static var knots := {}
static var errors: Array[String] = []

const MAX_STEPS := 500  # guards against diverts that loop forever


## Parses a script and adds its knots (replacing ones with the same name).
static func register(text: String, source: String = "") -> void:
	var knot := ""
	var number := 0
	for raw in text.split("\n"):
		number += 1
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("==="):
			knot = line.trim_prefix("===").strip_edges()
			knots[knot] = []
			continue
		if knot == "":
			errors.append("%s:%d: statement outside a knot" % [source, number])
			continue
		var statement: Variant = _parse_line(line)
		if statement == null:
			errors.append("%s:%d: %s (%s)" % [source, number, line, SimExpr.last_error])
			continue
		knots[knot].append(statement)


static func clear() -> void:
	knots.clear()
	errors.clear()


## {kind, cond, ...}: "line" (speaker, text), "set" (name, op, expr), "give" /
## "take" (item), "choice" (text, target), "goto" (target).
static func _parse_line(line: String) -> Variant:
	var cond: Variant = null
	var is_choice := line.begins_with("*")
	if is_choice:
		line = line.trim_prefix("*").strip_edges()
	if line.begins_with("{"):
		var close := line.find("}")
		if close == -1:
			return null
		cond = SimExpr.parse(line.substr(1, close - 1))
		if cond == null:
			return null
		line = line.substr(close + 1).strip_edges()
	if is_choice:
		var open := line.find("[")
		var shut := line.find("]")
		var arrow := line.find("->")
		if open != 0 or shut == -1 or arrow == -1:
			return null
		return {"kind": "choice", "cond": cond, "text": line.substr(1, shut - 1),
				"target": line.substr(arrow + 2).strip_edges()}
	if line.begins_with("->"):
		return {"kind": "goto", "cond": cond, "target": line.trim_prefix("->").strip_edges()}
	if line.begins_with("~"):
		var effect := line.trim_prefix("~").strip_edges()
		for verb in ["give", "take"]:
			if effect.begins_with(verb + " "):
				return {"kind": verb, "cond": cond, "item": effect.substr(verb.length() + 1).strip_edges()}
		for op in ["+=", "-=", "="]:
			var at := effect.find(op)
			if at > 0:
				var expr: Variant = SimExpr.parse(effect.substr(at + op.length()))
				if expr == null:
					return null
				return {"kind": "set", "cond": cond, "name": effect.substr(0, at).strip_edges(), "op": op, "expr": expr}
		return null
	# "Name: text" when the part before the colon looks like a name (short, at
	# most two words); otherwise the whole line is narration.
	var colon := line.find(":")
	if colon > 0 and colon <= 20 and line.substr(0, colon).count(" ") <= 1:
		return {"kind": "line", "cond": cond, "speaker": line.substr(0, colon).strip_edges(), "text": line.substr(colon + 1).strip_edges()}
	return {"kind": "line", "cond": cond, "speaker": "", "text": line}


## Starts a conversation between `talker` (party) and `npc` at `knot`.
static func start(state: SimState, talker: SimEntity, npc: SimEntity, knot: String) -> void:
	state.conversation = {"talker": talker.id, "npc": npc.id, "lines": [], "choices": []}
	talker.travel.clear()
	npc.travel.clear()
	npc.facing = SimPerception.facing_toward(npc.cell, talker.cell, npc.facing)
	state.emit_event(SimEvent.Type.TALK_STARTED, npc.cell, npc.id, talker.id)
	_run(state, knot)


## The talker picks choice `index` of the current page.
static func choose(state: SimState, index: int) -> void:
	var convo := state.conversation
	var choice: Dictionary = convo.choices[index]
	convo.lines = [["", choice.text, true]]  # the player's line, then the reply
	_run(state, choice.target)


static func end(state: SimState) -> void:
	var convo := state.conversation
	state.emit_event(SimEvent.Type.TALK_ENDED, Vector3i.ZERO, convo.get("npc", -1), convo.get("talker", -1))
	state.conversation = {}


## Runs from `knot` until a block of choices (the page waits there) or the
## end of the conversation.
static func _run(state: SimState, knot: String) -> void:
	var convo := state.conversation
	var context := {"npc": convo.npc}
	var choices: Array = []
	var current := knot
	var i := 0
	var steps := 0
	while steps < MAX_STEPS:
		steps += 1
		if current == "END" or not knots.has(current):
			break
		var block: Array = knots[current]
		if i >= block.size():
			if not choices.is_empty():
				break
			current = "END"
			continue
		var s: Dictionary = block[i]
		i += 1
		if s.kind != "choice" and not choices.is_empty():
			break  # a block of choices ended: the page waits on them
		if s.cond != null and not SimExpr.holds(state, s.cond, context):
			continue
		match s.kind:
			"line":
				convo.lines.append([s.speaker, s.text, false])
			"choice":
				choices.append({"text": s.text, "target": s.target})
			"goto":
				current = s.target
				i = 0
			"set":
				var v := SimExpr.eval(state, s.expr, context)
				var old: int = state.facts.get(s.name, 0)
				SimFacts.set_fact(state, s.name, v if s.op == "=" else (old + v if s.op == "+=" else old - v))
			"give":
				_hand_over(state, state.get_entity(convo.npc), state.get_entity(convo.talker), s.item)
			"take":
				_hand_over(state, state.get_entity(convo.talker), state.get_entity(convo.npc), s.item)
	convo.choices = choices
	state.emit_event(SimEvent.Type.TALK_PAGE, Vector3i.ZERO, convo.npc, convo.talker)
	QuestRules.step(state)


static func _hand_over(state: SimState, from: SimEntity, to: SimEntity, item: String) -> void:
	var index := from.inventory.find(item)
	if index == -1:
		return
	CrimeRules.move_item(from, to, index)
	var event := state.emit_event(SimEvent.Type.GIVEN, to.cell, to.id, from.id)
	event.text = item


## Whether a conversation has nothing more to say (its last page).
static func at_end(state: SimState) -> bool:
	return not state.conversation.is_empty() and state.conversation.choices.is_empty()
