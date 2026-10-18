class_name ExplorationRules
extends RefCounted
## What the party has seen (fog of war). The map is split into TILE x TILE
## columns; every tile within SIGHT of a living party member is explored and
## stays explored (SimState.explored: 0 or 255 per tile, saved with the state
## and shared by both players). Presentation draws unexplored ground black,
## dims explored ground out of sight, and hides characters out of sight.

## Tile size in cells.
const TILE := 2
## How far the party sees, in cells (round).
const SIGHT := 20
const EXPLORED := 255


static func tiles_x(grid: SimGrid) -> int:
	return ceili(grid.size.x / float(TILE))


static func tiles_z(grid: SimGrid) -> int:
	return ceili(grid.size.z / float(TILE))


## Marks what the party sees now. Cheap when nobody moved: each seer's last
## stamped cell is remembered (state.seen_from; derived, so not saved).
## Stamping from the same cell again changes nothing, so a state rebuilt from
## a snapshot (empty seen_from) still ends up identical to the original.
static func step(state: SimState) -> void:
	var tw := tiles_x(state.grid)
	var count := tw * tiles_z(state.grid)
	if state.explored.size() != count:
		state.explored.resize(count)
		state.explored.fill(0)
		state.seen_from.clear()
	for e in state.entities:
		if not is_seer(e):
			continue
		if state.seen_from.get(e.id) == e.cell:
			continue
		state.seen_from[e.id] = e.cell
		_stamp(state, e.cell, tw)


## Whether `e` reveals the map: a living party member.
static func is_seer(e: SimEntity) -> bool:
	return e.faction == SimEntity.Faction.PLAYERS and e.takes_turns() and e.is_alive()


static func is_explored(state: SimState, c: Vector3i) -> bool:
	var tw := tiles_x(state.grid)
	var tx := floori(c.x / float(TILE))
	var tz := floori(c.z / float(TILE))
	if tx < 0 or tz < 0 or tx >= tw or tz >= tiles_z(state.grid):
		return false
	var i := tx + tz * tw
	return i < state.explored.size() and state.explored[i] == EXPLORED


## Whether a party member sees `c` right now (within SIGHT).
static func in_sight(state: SimState, c: Vector3i) -> bool:
	for e in state.entities:
		if is_seer(e):
			var dx := e.cell.x - c.x
			var dz := e.cell.z - c.z
			if dx * dx + dz * dz <= SIGHT * SIGHT:
				return true
	return false


# Every tile whose centre is within SIGHT of `at`.
static func _stamp(state: SimState, at: Vector3i, tw: int) -> void:
	@warning_ignore("integer_division")
	var th: int = state.explored.size() / tw
	var r := SIGHT + TILE  # tiles reach a little past their centre
	var lo_x := maxi(floori((at.x - r) / float(TILE)), 0)
	var hi_x := mini(floori((at.x + r) / float(TILE)), tw - 1)
	var lo_z := maxi(floori((at.z - r) / float(TILE)), 0)
	var hi_z := mini(floori((at.z + r) / float(TILE)), th - 1)
	var limit := SIGHT * SIGHT * 4  # in half-cells, to use tile centres exactly
	for tz in range(lo_z, hi_z + 1):
		var dz := tz * TILE * 2 + TILE - at.z * 2 - 1
		var row := tz * tw
		for tx in range(lo_x, hi_x + 1):
			var dx := tx * TILE * 2 + TILE - at.x * 2 - 1
			if dx * dx + dz * dz <= limit:
				state.explored[row + tx] = EXPLORED
