class_name SimState
extends RefCounted
## Authoritative simulation state: grid, entities, combat, RNG, tick counter and
## pending events. Everything outside the sim mutates it only through
## apply_command() (CLAUDE.md rule 2).

var grid: SimGrid
var entities: Array[SimEntity] = []
var combat := SimCombat.new()
var rng: SimRng
var tick: int = 0
## Set when a fighter is hurt by the other side outside combat; starts combat.
var provoked := false
## Remembered facts (SimFacts), set by dialogue: name -> int.
var facts := {}
## Quest progress (QuestRules): id -> {"known": bool, "outcome": String}.
var quests := {}
## The conversation in progress (SimDialogue), or empty.
var conversation := {}

var _next_entity_id := 1
var _events: Array[SimEvent] = []


func _init(p_grid: SimGrid, seed_value: int = 1) -> void:
	grid = p_grid
	rng = SimRng.new(seed_value)


## Validates and executes a command. Returns false (and changes nothing) if invalid.
func apply_command(command: SimCommand) -> bool:
	if not command.validate(self):
		return false
	command.execute(self)
	CombatRules.check_end(self)
	CombatRules.check_start(self)
	if combat.active and not conversation.is_empty():
		SimDialogue.end(self)  # a fight breaks off any talk
	QuestRules.step(self)
	return true


## Advances the simulation by one tick. The pass order is part of the rules.
func step() -> void:
	LiquidRules.step(self)
	GasRules.step(self)
	FireRules.step(self)
	ThermalRules.step(self)
	EntityRules.step(self)
	tick += 1
	CombatRules.check_start(self)
	if combat.active and not conversation.is_empty():
		SimDialogue.end(self)
	QuestRules.step(self)


func step_ticks(count: int) -> void:
	for _i in count:
		step()


# --- Entities ------------------------------------------------------------------

## Adds an entity (level setup) and assigns its id. It settles onto the ground.
## A fighter added during combat takes part in it.
func add_entity(e: SimEntity) -> SimEntity:
	if combat.active and e.takes_turns():
		e.in_combat = true
	e.id = _next_entity_id
	_next_entity_id += 1
	entities.append(e)
	EntityOps.settle(self, e)
	return e


func get_entity(id: int) -> SimEntity:
	for e in entities:
		if e.id == id:
			return e
	return null


## The fallen character lying in a cell (dead, turn-taking), or null.
func corpse_at(c: Vector3i) -> SimEntity:
	for e in entities:
		if e.cell == c and not e.is_alive() and e.takes_turns():
			return e
	return null


## Whatever is at a cell: the living occupant, else remains lying there (a
## corpse, a broken chest), or null.
func thing_at(c: Vector3i) -> SimEntity:
	var remains: SimEntity = null
	for e in entities:
		if e.cell == c:
			if e.is_alive():
				return e
			if remains == null:
				remains = e
	return remains


## The living entity occupying a cell, or null.
func entity_at(c: Vector3i) -> SimEntity:
	for e in entities:
		if e.cell == c and e.is_alive():
			return e
	return null


# --- Events --------------------------------------------------------------------

func emit_event(type: SimEvent.Type, cell: Vector3i = Vector3i.ZERO, entity_id: int = -1, other_id: int = -1, amount: int = 0) -> SimEvent:
	var event := SimEvent.new(type, cell, entity_id, other_id, amount)
	_events.append(event)
	return event


## Returns and clears all events emitted since the last drain.
func drain_events() -> Array[SimEvent]:
	var drained := _events.duplicate()
	_events.clear()
	return drained


# --- Copies & hashing ----------------------------------------------------------

## Independent copy for previews and AI lookahead. Pending events are not copied.
func duplicate_state() -> SimState:
	var copy := SimState.new(grid.duplicate_grid())
	for e in entities:
		copy.entities.append(e.duplicate_entity())
	copy.combat = combat.duplicate_combat()
	copy.rng.state = rng.state
	copy.tick = tick
	copy.provoked = provoked
	copy.facts = facts.duplicate(true)
	copy.quests = quests.duplicate(true)
	copy.conversation = conversation.duplicate(true)
	copy._next_entity_id = _next_entity_id
	return copy


## Snapshot format version (co-op joins and save files). Bump it when a change
## needs more than defaults to read older snapshots (renamed or reinterpreted
## fields, new grid arrays), and add the step to _migrate(). New entity,
## combat or state fields need no bump: missing keys keep their defaults.
## tests/fixtures holds a save from each version; they must keep loading.
const SNAPSHOT_VERSION := 1


## The whole state as compressed bytes (a co-op guest joining, catching up
## after a desync, or a save file). from_snapshot() rebuilds an identical state.
func to_snapshot() -> PackedByteArray:
	var entity_data: Array = []
	for e in entities:
		entity_data.append(e.to_dict())
	var data := {
		"grid": grid.to_dict(), "entities": entity_data, "combat": combat.to_dict(),
		"rng": rng.state, "tick": tick, "provoked": provoked, "next_entity_id": _next_entity_id,
		"facts": facts, "quests": quests, "conversation": conversation,
		"version": SNAPSHOT_VERSION,
	}
	var raw := var_to_bytes(data)
	return var_to_bytes([raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD)])


## Returns null for bytes that aren't a snapshot, or one from a newer version.
static func from_snapshot(bytes: PackedByteArray) -> SimState:
	var packed: Variant = bytes_to_var(bytes)
	if not packed is Array or packed.size() != 2 or not packed[1] is PackedByteArray:
		return null
	var raw: PackedByteArray = (packed[1] as PackedByteArray).decompress(packed[0], FileAccess.COMPRESSION_ZSTD)
	var unpacked: Variant = bytes_to_var(raw)
	if not unpacked is Dictionary or unpacked.get("version", 1) > SNAPSHOT_VERSION:
		return null
	var data := _migrate(unpacked)
	var state := SimState.new(SimGrid.from_dict(data.grid))
	for d: Dictionary in data.entities:
		state.entities.append(SimEntity.from_dict(d))
	state.combat = SimCombat.from_dict(data.combat)
	state.rng.state = data.rng
	state.tick = data.tick
	state.provoked = data.get("provoked", false)
	state.facts = data.get("facts", {})
	state.quests = data.get("quests", {})
	state.conversation = data.get("conversation", {})
	state._next_entity_id = data.next_entity_id
	return state


## Brings snapshot data from an older SNAPSHOT_VERSION up to the current one,
## one version step at a time (none yet: version 1 is the first).
static func _migrate(data: Dictionary) -> Dictionary:
	var version: int = data.get("version", 1)
	# if version == 1: ...; version = 2
	assert(version == SNAPSHOT_VERSION)
	return data


## SHA-256 over all authoritative state; equal checksums mean identical sims.
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	grid.hash_into(ctx)
	for e in entities:
		ctx.update(var_to_bytes(e.to_dict()))
	ctx.update(var_to_bytes(combat.to_dict()))
	ctx.update(var_to_bytes([facts, quests, conversation]))
	ctx.update(PackedInt64Array([tick, rng.state, _next_entity_id, 1 if provoked else 0]).to_byte_array())
	return ctx.finish().hex_encode()
