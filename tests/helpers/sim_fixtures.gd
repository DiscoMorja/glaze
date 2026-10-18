extends RefCounted
## Shared sim setups for tests. The floor is solid at y = 0, so the walkable
## layer is y = FLOOR_Y.

const FLOOR_Y := 1
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


static func flat_state(size: Vector3i = Vector3i(9, 4, 9), seed_value: int = 1234) -> SimState:
	var grid := SimGrid.new(size)
	grid.fill_solid(Vector3i(0, 0, 0), Vector3i(size.x - 1, 0, size.z - 1))
	return SimState.new(grid, seed_value)


## Flat 12x5x12 arena with a hero (all abilities) at (2, 1, 2) and a plain
## bandit at (9, 1, 9), in combat.
static func duel_state() -> SimState:
	var state := flat_state(Vector3i(12, 5, 12))
	state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(2, FLOOR_Y, 2), 20, "Sword", 4, [], SimAbilities.all()))
	state.add_entity(SimEntity.character("Bandit", ENEMIES, Vector3i(9, FLOOR_Y, 9), 12, "Club", 3, ["Gold"]))
	state.apply_command(StartCombatCommand.new())
	state.drain_events()
	return state


## Gives `e` exactly these abilities, with the school ranks to use them.
static func teach(e: SimEntity, abilities: Array) -> void:
	e.abilities.assign(abilities)
	var ranks := StatRules.schools_for(e.abilities)
	for i in ranks.size():
		e.schools[i] = maxi(e.schools[i], ranks[i])


## Oil flasks for whoever throws them (SimAbilities.FROM_ITEM).
static func give_flasks(e: SimEntity, count: int = 3) -> SimEntity:
	for _i in count:
		e.inventory.append("Oil flask")
	return e


static func hero(state: SimState) -> SimEntity:
	return state.get_entity(1)


static func bandit(state: SimState) -> SimEntity:
	return state.get_entity(2)


static func events_of_type(events: Array[SimEvent], type: SimEvent.Type) -> Array[SimEvent]:
	var matching: Array[SimEvent] = []
	for e in events:
		if e.type == type:
			matching.append(e)
	return matching
