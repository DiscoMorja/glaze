extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y


func test_straight_path_cost() -> void:
	var state := Fixtures.flat_state()
	var from := Vector3i(1, Y, 4)
	var path := SimPathfinder.find_path(state, from, Vector3i(5, Y, 4))
	assert_eq(path.size(), 4)
	assert_eq(path.back(), Vector3i(5, Y, 4))
	assert_eq(SimPathfinder.movement_cost(from, path), 4 * SimPathfinder.COST_STRAIGHT)


func test_diagonal_path_cost() -> void:
	var state := Fixtures.flat_state()
	var from := Vector3i(1, Y, 1)
	var path := SimPathfinder.find_path(state, from, Vector3i(4, Y, 4))
	assert_eq(path.size(), 3)
	assert_eq(SimPathfinder.movement_cost(from, path), 3 * SimPathfinder.COST_DIAGONAL)


func test_path_goes_around_wall() -> void:
	var state := Fixtures.flat_state()
	state.grid.fill_solid(Vector3i(4, Y, 0), Vector3i(4, Y + 2, 6))
	var path := SimPathfinder.find_path(state, Vector3i(2, Y, 2), Vector3i(6, Y, 2))
	assert_false(path.is_empty())
	for c in path:
		assert_ne(c.x == 4 and c.z <= 6, true, "path must not cross the wall at %s" % c)


func test_no_corner_cutting() -> void:
	var state := Fixtures.flat_state()
	state.grid.fill_solid(Vector3i(3, Y, 2), Vector3i(3, Y + 2, 2))
	var path := SimPathfinder.find_path(state, Vector3i(2, Y, 2), Vector3i(3, Y, 3))
	assert_eq(path.size(), 2, "must go around the block, not diagonally past its corner")


func test_steps_up_and_down_one_level() -> void:
	var state := Fixtures.flat_state()
	state.grid.fill_solid(Vector3i(4, Y, 0), Vector3i(4, Y, 8))  # one-high step
	var from := Vector3i(2, Y, 4)
	var path := SimPathfinder.find_path(state, from, Vector3i(6, Y, 4))
	assert_true(path.has(Vector3i(4, Y + 1, 4)))
	assert_eq(path.back(), Vector3i(6, Y, 4))


func test_cannot_climb_two_levels() -> void:
	var state := Fixtures.flat_state()
	state.grid.fill_solid(Vector3i(4, Y, 0), Vector3i(4, Y + 1, 8))
	var path := SimPathfinder.find_path(state, Vector3i(2, Y, 4), Vector3i(6, Y, 4))
	assert_true(path.is_empty())


func test_occupied_cells_block() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	assert_true(SimPathfinder.find_path(state, Vector3i(2, Y, 2), bandit.cell).is_empty())
	var adjacent := SimPathfinder.find_path(state, Vector3i(2, Y, 2), bandit.cell, 1, true)
	assert_true(SimAbilities.is_adjacent(adjacent.back(), bandit.cell))


func test_avoids_fire_when_detour_is_short() -> void:
	var state := Fixtures.flat_state()
	state.apply_command(IgniteCommand.new(Vector3i(4, Y, 4)))
	var path := SimPathfinder.find_path(state, Vector3i(2, Y, 4), Vector3i(6, Y, 4))
	assert_false(path.has(Vector3i(4, Y, 4)))


func test_affordable_prefix_respects_budget() -> void:
	var from := Vector3i(0, Y, 0)
	var path: Array[Vector3i] = [Vector3i(1, Y, 0), Vector3i(2, Y, 0), Vector3i(3, Y, 0)]
	assert_eq(SimPathfinder.affordable_prefix(from, path, 25).size(), 2)
	assert_eq(SimPathfinder.affordable_prefix(from, path, 5).size(), 0)
