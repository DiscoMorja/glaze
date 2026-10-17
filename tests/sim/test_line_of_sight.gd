extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability


func test_clear_line_on_open_floor() -> void:
	var grid := Fixtures.flat_state().grid
	assert_true(SimLos.has_line_of_sight(grid, Vector3i(1, Y, 1), Vector3i(7, Y, 6)))


func test_wall_blocks_sight() -> void:
	var grid := Fixtures.flat_state().grid
	grid.fill_solid(Vector3i(4, Y, 0), Vector3i(4, Y + 2, 8))
	assert_false(SimLos.has_line_of_sight(grid, Vector3i(1, Y, 4), Vector3i(7, Y, 4)))


func test_low_step_does_not_block() -> void:
	var grid := Fixtures.flat_state().grid
	grid.fill_solid(Vector3i(4, Y, 0), Vector3i(4, Y, 8))  # knee-high, below eye height
	assert_true(SimLos.has_line_of_sight(grid, Vector3i(1, Y, 4), Vector3i(7, Y, 4)))


func test_sight_is_symmetric_around_corner() -> void:
	var grid := Fixtures.flat_state().grid
	grid.fill_solid(Vector3i(3, Y, 3), Vector3i(5, Y + 2, 5))
	assert_false(SimLos.has_line_of_sight(grid, Vector3i(2, Y, 2), Vector3i(6, Y, 6)))
	assert_true(SimLos.has_line_of_sight(grid, Vector3i(2, Y, 2), Vector3i(6, Y, 2)))


func test_ranged_ability_needs_sight() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(6, Y, 2))
	state.grid.fill_solid(Vector3i(4, Y, 0), Vector3i(4, Y + 2, 4))
	assert_false(state.apply_command(CastCommand.new(1, A.FIREBOLT, bandit.cell)))
	assert_false(state.apply_command(CastCommand.new(1, A.TELEPORT, bandit.cell, Vector3i(6, Y, 6))))


func test_teleport_destination_needs_sight() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(3, Y, 4))
	state.grid.fill_solid(Vector3i(5, Y, 0), Vector3i(5, Y + 3, 11))
	assert_false(state.apply_command(CastCommand.new(1, A.TELEPORT, bandit.cell, Vector3i(7, Y, 2))))
	assert_true(state.apply_command(CastCommand.new(1, A.TELEPORT, bandit.cell, Vector3i(4, Y, 6))))
