class_name LevelTravel
extends RefCounted
## Moving the party between levels (GDD §5.10). The world is the level the
## party is in plus the levels it left (SimState.away), frozen as they were.
##
## A trip starts with UseExitCommand (state.pending_travel). The host then
## bakes the level beyond (GameLevel.bake(), ids after from.next_entity_id())
## or takes it from `away` if the party was there before, and calls arrive():
## the party and everything that belongs to the whole world (facts, quests,
## the RNG, ids) move into it, and the level left joins `away`. The host
## does this once and sends guests the result as a snapshot, so it never
## has to replay identically.


## The arriving level, now the whole world. `from` (with a pending trip) is
## left without its party and stored in the result's `away`; `to` is a fresh
## bake or from.away[the trip's level].
static func arrive(from: SimState, to: SimState) -> SimState:
	var trip := from.pending_travel
	var party: Array[SimEntity] = []
	for e in from.entities:
		if e.faction == SimEntity.Faction.PLAYERS:
			party.append(e)
	for e in party:
		from.entities.erase(e)
	from.pending_travel = {}
	from.conversation = {}
	from.provoked = false
	from.drain_events()

	# The world moves with the party.
	to.away = from.away.duplicate()
	to.away.erase(to.level)
	from.away = {}
	to.away[from.level] = from
	to.facts = from.facts
	to.quests = from.quests
	to.rng.state = from.rng.state
	to.tick = maxi(to.tick, from.tick)
	to.reserve_ids(from.next_entity_id())
	to.pending_travel = {}
	to.conversation = {}

	var start: Vector3i = to.entries.get(trip.get("entry", ""), _any_entry(to))
	var taken := {}
	for e in party:
		e.travel.clear()
		e.in_combat = false
		e.stagger = 0
		var spot: Variant = _free_cell_near(to, start, taken, e)
		e.cell = spot if spot != null else start
		taken[e.cell] = true
		to.entities.append(e)
	ExplorationRules.step(to)
	to.emit_event(SimEvent.Type.ARRIVED, start, party[0].id if not party.is_empty() else -1)
	return to


## The first entry of a level with no matching one (or the grid's centre).
static func _any_entry(state: SimState) -> Vector3i:
	for name: String in state.entries:
		return state.entries[name]
	return state.grid.size / 2


## Nearest cell around `start` (breadth first over walkable steps) where `e`
## can stand and nobody else was put.
static func _free_cell_near(state: SimState, start: Vector3i, taken: Dictionary, e: SimEntity) -> Variant:
	if not e.is_alive():
		return start if not taken.has(start) else null  # the fallen are carried, laid down at the entry
	var queue: Array[Vector3i] = [start]
	var seen := {start: true}
	var head := 0
	while head < queue.size() and head < 400:
		var c := queue[head]
		head += 1
		if not taken.has(c) and SimPathfinder.is_standable(state, c, e.id):
			return c
		for d: Vector3i in SimPerception.FACINGS:
			var next: Variant = state.grid.floor_near(c + d, 1)
			if next != null and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return null
