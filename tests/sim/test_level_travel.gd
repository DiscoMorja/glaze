extends GutTest
## Travelling between levels (GDD §5.10): exits, the hand-over, the levels
## left behind, and facts and saves across them.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES
const TOWN := "res://town.tscn"
const MINE := "res://mine.tscn"


## A town with two party members, a bandit and an exit to the mine at (6, 6).
func _town() -> SimState:
	var state := Fixtures.flat_state(Vector3i(12, 5, 12))
	state.level = TOWN
	state.add_entity(SimEntity.character("Ari", PLAYERS, Vector3i(5, Y, 6), 20))
	state.add_entity(SimEntity.character("Bram", PLAYERS, Vector3i(2, Y, 2), 20))
	var bandit := state.add_entity(SimEntity.character("Bandit", ENEMIES, Vector3i(10, Y, 10), 10))
	bandit.group = "Bandits"
	state.exits[Vector3i(6, Y, 6)] = {"level": MINE, "entry": "start", "name": "Old mine"}
	state.entries["mine"] = Vector3i(7, Y, 6)
	state.facts["met_smith"] = 1
	return state


## The mine, baked after the town: its ids start after the town's.
func _mine(first_id: int) -> SimState:
	var state := Fixtures.flat_state(Vector3i(10, 5, 10), 99)
	state.level = MINE
	state.reserve_ids(first_id)
	var digger := state.add_entity(SimEntity.character("Digger", ENEMIES, Vector3i(8, Y, 8), 7))
	digger.group = "MineThugs"
	state.entries["start"] = Vector3i(2, Y, 2)
	state.exits[Vector3i(1, Y, 2)] = {"level": TOWN, "entry": "mine", "name": "The way up"}
	return state


func test_an_exit_needs_a_party_member_next_to_it_outside_combat() -> void:
	var state := _town()
	assert_eq(UseExitCommand.blocker(state, state.get_entity(2), Vector3i(6, Y, 6)), "Too far")
	assert_eq(UseExitCommand.blocker(state, state.get_entity(3), Vector3i(6, Y, 6)), "Pick a party member")
	assert_eq(UseExitCommand.blocker(state, state.get_entity(1), Vector3i(4, Y, 4)), "No way through here")
	state.combat.active = true
	assert_false(UseExitCommand.new(1, Vector3i(6, Y, 6)).validate(state))
	state.combat.active = false
	assert_true(state.apply_command(UseExitCommand.new(1, Vector3i(6, Y, 6))))
	assert_eq(state.pending_travel, {"level": MINE, "entry": "start"})
	assert_false(UseExitCommand.new(1, Vector3i(6, Y, 6)).validate(state), "already on the way")
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.LEVEL_EXIT).size(), 1)


func test_the_whole_party_arrives_and_the_town_waits() -> void:
	var town := _town()
	town.apply_command(UseExitCommand.new(1, Vector3i(6, Y, 6)))
	var mine := LevelTravel.arrive(town, _mine(town.next_entity_id()))
	var party := mine.entities.filter(func(e: SimEntity) -> bool: return e.faction == PLAYERS)
	assert_eq(party.size(), 2, "both, though only one stood at the exit")
	assert_eq(mine.get_entity(1).cell, Vector3i(2, Y, 2), "at the entry")
	assert_ne(mine.get_entity(2).cell, mine.get_entity(1).cell, "side by side")
	assert_eq(mine.facts.get("met_smith"), 1, "facts travel")
	assert_true(mine.away.has(TOWN))
	assert_eq(mine.away[TOWN].entities.size(), 1, "the bandit stayed home")
	assert_true(mine.pending_travel.is_empty())
	var ids := {}
	for e in mine.entities:
		assert_false(ids.has(e.id), "ids stay unique")
		ids[e.id] = true


func test_going_back_wakes_the_level_as_it_was_left() -> void:
	var town := _town()
	town.apply_command(UseExitCommand.new(1, Vector3i(6, Y, 6)))
	var mine := LevelTravel.arrive(town, _mine(town.next_entity_id()))
	mine.get_entity(1).cell = Vector3i(2, Y, 3)
	assert_true(mine.apply_command(UseExitCommand.new(1, Vector3i(1, Y, 2))))
	var back := LevelTravel.arrive(mine, mine.away[TOWN])
	assert_eq(back.level, TOWN)
	assert_eq(back.get_entity(1).cell, Vector3i(7, Y, 6), "at the town's mine entry")
	assert_true(back.away.has(MINE))
	assert_false(back.away.has(TOWN))
	assert_eq(back.away[MINE].entities.size(), 1, "the digger waits below")


func test_facts_count_people_in_levels_left_behind() -> void:
	var town := _town()
	town.apply_command(UseExitCommand.new(1, Vector3i(6, Y, 6)))
	var mine := LevelTravel.arrive(town, _mine(town.next_entity_id()))
	assert_eq(SimFacts.value(mine, "alive.Bandits"), 1, "the camp isn't cleared by leaving it")
	assert_eq(SimFacts.value(mine, "alive.MineThugs"), 1)


func test_a_world_of_levels_survives_a_snapshot() -> void:
	var town := _town()
	town.apply_command(UseExitCommand.new(1, Vector3i(6, Y, 6)))
	var mine := LevelTravel.arrive(town, _mine(town.next_entity_id()))
	var copy := SimState.from_snapshot(mine.to_snapshot())
	assert_eq(copy.level, MINE)
	assert_eq(copy.exits, mine.exits)
	assert_eq(copy.entries, mine.entries)
	assert_true(copy.away.has(TOWN))
	assert_eq(copy.away[TOWN].entities.size(), 1)
	assert_eq(copy.away[TOWN].exits, town.exits)
	assert_eq(copy.checksum(), mine.checksum())
	assert_eq(copy.next_entity_id(), mine.next_entity_id())
