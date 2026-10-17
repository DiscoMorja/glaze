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
	return true


## Advances the simulation by one tick. The pass order is part of the rules.
func step() -> void:
	LiquidRules.step(self)
	GasRules.step(self)
	FireRules.step(self)
	ThermalRules.step(self)
	EntityRules.step(self)
	tick += 1


func step_ticks(count: int) -> void:
	for _i in count:
		step()


# --- Entities ------------------------------------------------------------------

## Adds an entity (level setup) and assigns its id. It settles onto the ground.
func add_entity(e: SimEntity) -> SimEntity:
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
	copy._next_entity_id = _next_entity_id
	return copy


## SHA-256 over all authoritative state; equal checksums mean identical sims.
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	grid.hash_into(ctx)
	for e in entities:
		ctx.update(var_to_bytes(e.to_dict()))
	ctx.update(var_to_bytes(combat.to_dict()))
	ctx.update(PackedInt64Array([tick, rng.state, _next_entity_id]).to_byte_array())
	return ctx.finish().hex_encode()
