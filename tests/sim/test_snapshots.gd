extends GutTest
## Co-op groundwork: a snapshot rebuilds an identical sim that keeps evolving
## the same way, and commands name the entity that acts.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability


func _busy_state() -> SimState:
	var state := Fixtures.duel_state()
	Fixtures.give_flasks(Fixtures.hero(state))
	state.apply_command(CastCommand.new(1, A.OIL_FLASK, Vector3i(5, Y, 5)))
	state.apply_command(IgniteCommand.new(Vector3i(5, Y, 5)))
	state.apply_command(ChillCommand.new(Vector3i(2, Y, 8), 1))
	state.step_ticks(3)
	Fixtures.hero(state).owner = 1
	return state


func test_snapshot_round_trip_is_identical() -> void:
	var state := _busy_state()
	var copy := SimState.from_snapshot(state.to_snapshot())
	assert_eq(copy.checksum(), state.checksum())
	assert_eq(Fixtures.hero(copy).owner, 1)
	assert_eq(copy.grid.fire_cells.size(), state.grid.fire_cells.size())


func test_snapshot_keeps_evolving_the_same_way() -> void:
	var state := _busy_state()
	var copy := SimState.from_snapshot(state.to_snapshot())
	for s in [state, copy]:
		s.apply_command(MoveCommand.new(1, Vector3i(3, Y, 3)))
		s.apply_command(EndTurnCommand.new(SimEntity.Faction.PLAYERS))
		s.step_ticks(6)
	assert_eq(copy.checksum(), state.checksum())


func test_snapshot_is_compact() -> void:
	var state := _busy_state()
	assert_lt(state.to_snapshot().size(), 20000, "a small arena packs into a few KB")


func test_commands_name_their_actor() -> void:
	assert_eq(MoveCommand.new(3, Vector3i.ZERO).actor_id(), 3)
	assert_eq(TravelCommand.new(4, Vector3i.ZERO).actor_id(), 4)
	assert_eq(AttackCommand.new(5, 1).actor_id(), 5)
	assert_eq(CastCommand.new(6, A.FIREBOLT, Vector3i.ZERO).actor_id(), 6)
	assert_eq(EndTurnCommand.new(SimEntity.Faction.PLAYERS).actor_id(), -1)
