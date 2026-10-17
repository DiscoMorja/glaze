class_name SimState
extends RefCounted
## Authoritative simulation state: grid, RNG, tick counter and pending events.
## Everything outside the sim mutates it only through apply_command() (CLAUDE.md rule 2).

var grid: SimGrid
var rng: SimRng
var tick: int = 0

var _events: Array[SimEvent] = []


func _init(p_grid: SimGrid, seed_value: int = 1) -> void:
	grid = p_grid
	rng = SimRng.new(seed_value)


## Validates and executes a command. Returns false (and changes nothing) if invalid.
func apply_command(command: SimCommand) -> bool:
	if not command.validate(self):
		return false
	command.execute(self)
	return true


## Advances the simulation by one tick. The pass order is part of the rules.
func step() -> void:
	LiquidRules.step(self)
	GasRules.step(self)
	FireRules.step(self)
	ThermalRules.step(self)
	tick += 1


func step_ticks(count: int) -> void:
	for _i in count:
		step()


func emit_event(type: SimEvent.Type, cell: Vector3i) -> void:
	_events.append(SimEvent.new(type, cell))


## Returns and clears all events emitted since the last drain.
func drain_events() -> Array[SimEvent]:
	var drained := _events.duplicate()
	_events.clear()
	return drained


## Independent copy for previews and AI lookahead. Pending events are not copied.
func duplicate_state() -> SimState:
	var copy := SimState.new(grid.duplicate_grid())
	copy.rng.state = rng.state
	copy.tick = tick
	return copy


## SHA-256 over all authoritative state; equal checksums mean identical sims.
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	grid.hash_into(ctx)
	ctx.update(PackedInt64Array([tick, rng.state]).to_byte_array())
	return ctx.finish().hex_encode()
