extends GutTest
## Fog of war: the party explores tiles within sight; explored stays explored,
## is saved, and replays identically.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const SIGHT := ExplorationRules.SIGHT


func _field() -> SimState:
	var state := Fixtures.flat_state(Vector3i(80, 4, 40))
	state.add_entity(SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(5, Y, 5), 20))
	return state


func test_the_party_explores_what_it_sees() -> void:
	var state := _field()
	state.step()
	assert_true(ExplorationRules.is_explored(state, Vector3i(5, Y, 5)))
	assert_true(ExplorationRules.is_explored(state, Vector3i(5 + SIGHT - 2, Y, 5)))
	assert_false(ExplorationRules.is_explored(state, Vector3i(5 + SIGHT + 4, Y, 5)), "beyond sight")
	assert_false(ExplorationRules.is_explored(state, Vector3i(70, Y, 30)))


func test_explored_stays_explored_after_leaving() -> void:
	var state := _field()
	state.step()
	state.apply_command(TravelCommand.new(1, Vector3i(40, Y, 5)))
	state.step_ticks(40)
	assert_eq(Fixtures.hero(state).cell, Vector3i(40, Y, 5))
	assert_true(ExplorationRules.is_explored(state, Vector3i(50, Y, 5)), "new ground")
	assert_true(ExplorationRules.is_explored(state, Vector3i(5, Y, 5)), "still remembered")
	assert_false(ExplorationRules.in_sight(state, Vector3i(5, Y, 5)), "but out of sight now")
	assert_true(ExplorationRules.in_sight(state, Vector3i(45, Y, 5)))


func test_enemies_reveal_nothing() -> void:
	var state := _field()
	state.add_entity(SimEntity.character("Bandit", SimEntity.Faction.ENEMIES, Vector3i(70, Y, 30), 10))
	state.step()
	assert_false(ExplorationRules.is_explored(state, Vector3i(70, Y, 30)))


func test_saved_and_replayed_identically() -> void:
	var state := _field()
	state.apply_command(TravelCommand.new(1, Vector3i(30, Y, 20)))
	state.step_ticks(10)
	var loaded := SimState.from_snapshot(state.to_snapshot())
	assert_eq(loaded.explored, state.explored)
	state.step_ticks(20)
	loaded.step_ticks(20)
	assert_eq(loaded.checksum(), state.checksum(), "a loaded state (no seen_from) keeps in step")


func test_saves_from_before_fog_still_load() -> void:
	var state := _field()
	var loaded := SimState.from_snapshot(state.to_snapshot())
	loaded.explored = PackedByteArray()  # as if saved before fog of war
	loaded.step()
	assert_true(ExplorationRules.is_explored(loaded, Vector3i(5, Y, 5)), "rebuilt around the party")


func test_a_copy_explores_on_its_own() -> void:
	var state := _field()
	state.step()
	var before := state.explored.duplicate()
	var copy := state.duplicate_state()
	copy.apply_command(TravelCommand.new(1, Vector3i(40, Y, 5)))
	copy.step_ticks(40)
	assert_eq(state.explored, before, "a preview copy must not explore for the real state")
	assert_true(ExplorationRules.is_explored(copy, Vector3i(50, Y, 5)))
