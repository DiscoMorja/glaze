class_name SimPerception
extends RefCounted
## Who notices whom. Watchers see in a cone in front of them (facing), out to
## their sight range, with line of sight. Someone walking normally is also
## heard close by from any side; a sneaking character is only seen in the
## cone, at a shorter range. NPCs not doing anything turn their heads now and
## then (look_around()), so a cone can sweep over you.

## Facing directions, clockwise from north (-z): index -> unit step.
const FACINGS: Array[Vector3i] = [
	Vector3i(0, 0, -1), Vector3i(1, 0, -1), Vector3i(1, 0, 0), Vector3i(1, 0, 1),
	Vector3i(0, 0, 1), Vector3i(-1, 0, 1), Vector3i(-1, 0, 0), Vector3i(-1, 0, -1),
]
## Cells around a watcher in which it hears someone not sneaking, from any side.
const HEARING := 2
## A sneaking character is seen in the cone only this close (percent of sight).
const SNEAK_SIGHT_PERCENT := 50
## Ticks between head turns while idle, and the turns (in facing steps) an
## idle NPC cycles through around its post.
const LOOK_TICKS := 12
const LOOK_PATTERN := [0, 1, 0, -1]


## The facing index for a step from a to b (or `current` if they're equal).
static func facing_toward(a: Vector3i, b: Vector3i, current: int) -> int:
	var d := Vector3i(signi(b.x - a.x), 0, signi(b.z - a.z))
	var i := FACINGS.find(d)
	return current if i == -1 else i


## Whether `watcher` notices `target` where they stand now.
static func can_see(state: SimState, watcher: SimEntity, target: SimEntity) -> bool:
	return sees_cell(state, watcher, target.cell, target.sneaking, target.thievery < StatRules.SILENT_RANK)


## Whether `watcher` would notice someone at `c` (sneaking or not; `audible`:
## walking normally can be heard, unless Thievery makes it silent).
@warning_ignore("integer_division")
static func sees_cell(state: SimState, watcher: SimEntity, c: Vector3i, sneaking: bool, audible: bool = true) -> bool:
	if watcher.sight <= 0 or not watcher.is_alive() or c == watcher.cell:
		return false
	var dx := c.x - watcher.cell.x
	var dz := c.z - watcher.cell.z
	var dist2 := dx * dx + dz * dz
	if absi(c.y - watcher.cell.y) > watcher.sight:
		return false
	if not sneaking and audible and dist2 <= HEARING * HEARING:
		return true  # heard, whichever way it faces
	var reach := watcher.sight if not sneaking else maxi(1, watcher.sight * SNEAK_SIGHT_PERCENT / 100)
	if dist2 > reach * reach or not in_cone(watcher.facing, dx, dz):
		return false
	return SimLos.has_line_of_sight(state.grid, watcher.cell, c)


## Whether the offset (dx, dz) lies within 60 degrees of the facing direction
## (a 120 degree cone). Integer: dot >= cos(60) * |d| * |f|.
static func in_cone(facing: int, dx: int, dz: int) -> bool:
	var f: Vector3i = FACINGS[facing]
	var dot := dx * f.x + dz * f.z
	if dot <= 0:
		return false
	return 4 * dot * dot >= (dx * dx + dz * dz) * (f.x * f.x + f.z * f.z)


## Idle NPCs (real time, not walking) look around their post.
@warning_ignore("integer_division")
static func look_around(state: SimState) -> void:
	if state.tick % LOOK_TICKS != 0:
		return
	var beat := state.tick / LOOK_TICKS
	for e in state.entities:
		if not e.is_alive() or not e.takes_turns() or e.faction == SimEntity.Faction.PLAYERS:
			continue
		if not e.travel.is_empty() or e.sight <= 0:
			continue
		var offset: int = LOOK_PATTERN[(beat + e.id) % LOOK_PATTERN.size()]
		e.facing = posmod(e.home_facing + offset, FACINGS.size())
