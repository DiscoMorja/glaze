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


func test_reachable_respects_budget() -> void:
	var state := Fixtures.flat_state()
	var from := Vector3i(4, Y, 4)
	var cells := SimPathfinder.reachable(state, from, 20)
	assert_true(cells.has(Vector3i(6, Y, 4)), "two straight steps cost 20")
	assert_false(cells.has(Vector3i(7, Y, 4)))
	assert_false(cells.has(from))
	assert_eq(cells[Vector3i(5, Y, 5)], SimPathfinder.COST_DIAGONAL)


func test_top_of_a_pillar_is_unreachable_without_a_full_search() -> void:
	var state := Fixtures.flat_state(Vector3i(40, 8, 40))
	var hero := state.add_entity(SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(1, Fixtures.FLOOR_Y, 1), 20))
	# A 2x2 pillar four levels high: its top is a walkable island.
	state.grid.fill_solid(Vector3i(30, Fixtures.FLOOR_Y, 30), Vector3i(31, Fixtures.FLOOR_Y + 3, 31))
	var top := Vector3i(30, Fixtures.FLOOR_Y + 4, 30)
	assert_true(SimPathfinder.is_standable(state, top))
	assert_eq(SimPathfinder.find_path(state, hero.cell, top, hero.id).size(), 0)
	assert_gt(SimPathfinder.find_path(state, hero.cell, Vector3i(29, Fixtures.FLOOR_Y, 29), hero.id).size(), 0, "the ground next to it still works")


## A 6x4x3 strip whose terrain rises from x = 3 on: one level up in sim terms.
func _terrain_step(rise_cm: int) -> SimState:
	var state := Fixtures.flat_state(Vector3i(6, 4, 3))
	state.grid.fill_solid(Vector3i(3, Y, 0), Vector3i(5, Y, 2))
	var floors := PackedInt32Array()
	var heights := PackedInt32Array()
	for z in 3:
		for x in 6:
			floors.append(Y if x < 3 else Y + 1)
			heights.append(Y * 100 if x < 3 else Y * 100 + rise_cm)
	state.grid.set_terrain(floors, heights)
	state.add_entity(SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(0, Y, 1), 20))
	return state


func test_steep_terrain_cannot_be_climbed() -> void:
	var state := _terrain_step(150)
	assert_eq(SimPathfinder.find_path(state, Vector3i(0, Y, 1), Vector3i(5, Y + 1, 1), 1).size(), 0, "a 1.5 m rise is a cliff")


func test_gentle_terrain_and_structure_steps_can_be_climbed() -> void:
	var state := _terrain_step(60)
	assert_gt(SimPathfinder.find_path(state, Vector3i(0, Y, 1), Vector3i(5, Y + 1, 1), 1).size(), 0, "a 0.6 m rise is a slope")
	var steep := _terrain_step(90)
	assert_eq(SimPathfinder.find_path(steep, Vector3i(0, Y, 1), Vector3i(5, Y + 1, 1), 1).size(), 0, "0.9 m of terrain is too steep")
	var flat := Fixtures.flat_state(Vector3i(6, 4, 3))
	flat.grid.fill_solid(Vector3i(3, Y, 0), Vector3i(5, Y, 2))
	flat.add_entity(SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(0, Y, 1), 20))
	assert_gt(SimPathfinder.find_path(flat, Vector3i(0, Y, 1), Vector3i(5, Y + 1, 1), 1).size(), 0, "a 1 m structure step")


func test_a_large_unreachable_roof_is_turned_down_without_a_full_search() -> void:
	# A 14 x 14 block (a roof bigger than POCKET_LIMIT) on terrain: its top is
	# standable but no stairs lead up, so the pocket check must say no.
	var state := Fixtures.flat_state(Vector3i(24, 10, 24))
	var floors := PackedInt32Array()
	var heights := PackedInt32Array()
	floors.resize(24 * 24)
	floors.fill(Y)
	heights.resize(24 * 24)
	heights.fill(Y * 100)
	state.grid.set_terrain(floors, heights)
	state.grid.fill_solid(Vector3i(5, Y, 5), Vector3i(18, Y + 3, 18))
	var roof := Vector3i(10, Y + 4, 10)
	assert_true(SimPathfinder.is_standable(state, roof))
	var occupied := SimPathfinder.occupancy(state)
	assert_true(SimPathfinder._in_pocket_without(state.grid, occupied, roof, Vector3i(1, Y, 1), -1))
	assert_eq(SimPathfinder.find_path(state, Vector3i(1, Y, 1), roof), [] as Array[Vector3i])


func test_a_structure_joined_to_the_ground_is_not_a_pocket() -> void:
	# A wide platform level with the ground at one edge: reachable.
	var state := Fixtures.flat_state(Vector3i(24, 10, 24))
	var floors := PackedInt32Array()
	var heights := PackedInt32Array()
	floors.resize(24 * 24)
	floors.fill(Y)
	heights.resize(24 * 24)
	heights.fill(Y * 100)
	state.grid.set_terrain(floors, heights)
	state.grid.fill_solid(Vector3i(5, Y, 5), Vector3i(18, Y, 18))  # one step up
	var top := Vector3i(15, Y + 1, 15)
	assert_false(SimPathfinder._in_pocket_without(state.grid, SimPathfinder.occupancy(state), top, Vector3i(1, Y, 1), -1))
	assert_false(SimPathfinder.find_path(state, Vector3i(1, Y, 1), top).is_empty())


func test_a_search_run_in_small_steps_finds_the_same_path() -> void:
	var state := Fixtures.flat_state(Vector3i(16, 4, 16))
	state.grid.fill_solid(Vector3i(6, Y, 0), Vector3i(6, Y + 2, 12))
	var from := Vector3i(1, Y, 2)
	var to := Vector3i(12, Y, 3)
	var whole := SimPathfinder.find_path(state, from, to)
	var search := SimPathSearch.new(state, from, to)
	var steps := 0
	while not search.step(3):
		steps += 1
	assert_gt(steps, 5, "it really ran in pieces")
	assert_eq(search.status, SimPathSearch.Status.FOUND)
	assert_eq(search.path, whole)


func test_a_stepped_search_fails_on_a_walled_off_goal() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 4, 12))
	state.grid.fill_solid(Vector3i(7, Y, 4), Vector3i(9, Y + 3, 6))
	state.grid.fill_solid(Vector3i(8, Y, 5), Vector3i(8, Y + 3, 5), false)
	var search := SimPathSearch.new(state, Vector3i(1, Y, 1), Vector3i(8, Y, 5))
	while not search.step(4):
		pass
	assert_eq(search.status, SimPathSearch.Status.FAILED)
	assert_true(search.path.is_empty())
