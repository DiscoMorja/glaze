extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const WATER := SimMaterials.Surface.WATER
const OIL := SimMaterials.Surface.OIL


func test_liquid_falls_onto_floor() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	grid.add_surface(Vector3i(4, 3, 4), WATER, 30)
	state.step_ticks(3)
	assert_eq(grid.surface_amount[grid.index(Vector3i(4, 3, 4))], 0)
	assert_gt(grid.surface_amount[grid.index(Vector3i(4, Fixtures.FLOOR_Y, 4))], 0)


func test_water_spreads_on_flat_floor() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var center := Vector3i(4, Fixtures.FLOOR_Y, 4)
	grid.add_surface(center, WATER, 200)
	state.step_ticks(10)
	for n: Vector3i in SimGrid.NEIGHBORS_4:
		assert_eq(grid.surface_type[grid.index(center + n)], WATER)
	assert_lt(grid.surface_amount[grid.index(center)], 200)


func test_liquid_mass_is_conserved() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	grid.add_surface(Vector3i(2, 3, 2), WATER, 300)
	grid.add_surface(Vector3i(6, Fixtures.FLOOR_Y, 6), OIL, 150)
	state.step_ticks(60)
	assert_eq(grid.total_surface(WATER), 300)
	assert_eq(grid.total_surface(OIL), 150)


func test_liquid_flows_downhill_off_a_platform() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	# Platform covering x 0..3 one cell above the floor; its top layer is y = 2.
	grid.fill_solid(Vector3i(0, 1, 0), Vector3i(3, 1, 8))
	var source := Vector3i(2, 2, 4)
	grid.add_surface(source, WATER, 200)
	state.step_ticks(40)
	var below_ledge := 0
	for x in range(4, 9):
		for z in 9:
			below_ledge += grid.surface_amount[grid.index(Vector3i(x, Fixtures.FLOOR_Y, z))]
	assert_gt(below_ledge, 0, "water should reach the lower floor")
	assert_lt(grid.surface_amount[grid.index(source)], 200)


func test_walls_block_flow() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	grid.fill_solid(Vector3i(5, 1, 0), Vector3i(5, 3, 8))
	grid.add_surface(Vector3i(2, Fixtures.FLOOR_Y, 4), WATER, 300)
	state.step_ticks(60)
	for x in range(6, 9):
		for z in 9:
			assert_eq(grid.surface_amount[grid.index(Vector3i(x, Fixtures.FLOOR_Y, z))], 0)


func test_different_liquids_do_not_mix() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	grid.add_surface(Vector3i(3, Fixtures.FLOOR_Y, 4), WATER, 200)
	grid.add_surface(Vector3i(5, Fixtures.FLOOR_Y, 4), OIL, 200)
	state.step_ticks(30)
	assert_eq(grid.total_surface(WATER), 200)
	assert_eq(grid.total_surface(OIL), 200)


func test_settled_liquids_are_skipped_until_something_changes() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	grid.add_surface(Vector3i(4, Fixtures.FLOOR_Y, 4), WATER, 200)
	var steps := LiquidRules.settle(state, 500)
	assert_lt(steps, 500, "the puddle comes to rest")
	var resting := grid.surface_amount.duplicate()
	var version := grid.surface_version
	LiquidRules.step(state)
	assert_eq(grid.surface_version, version, "a settled step writes nothing")
	assert_eq(grid.surface_amount, resting)
	# New water wakes it up again.
	grid.add_surface(Vector3i(1, Fixtures.FLOOR_Y, 1), WATER, 100)
	LiquidRules.step(state)
	assert_gt(grid.surface_amount[grid.index(Vector3i(2, Fixtures.FLOOR_Y, 1))], 0, "the new water spreads")


func test_a_removed_wall_wakes_settled_liquids() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var y := Fixtures.FLOOR_Y
	grid.fill_solid(Vector3i(4, y, 0), Vector3i(4, y, 8))
	grid.add_surface(Vector3i(2, y, 4), WATER, 300)
	LiquidRules.settle(state, 500)
	assert_eq(grid.surface_amount[grid.index(Vector3i(5, y, 4))], 0, "held back")
	grid.fill_solid(Vector3i(4, y, 0), Vector3i(4, y, 8), false)
	state.step_ticks(5)
	assert_gt(grid.surface_amount[grid.index(Vector3i(4, y, 4))], 0, "flows through the gap")


func test_settled_and_unsettled_runs_match() -> void:
	# Skipping a settled step must change nothing: compare with a grid that
	# never learns it settled.
	var a := Fixtures.flat_state()
	var b := Fixtures.flat_state()
	for s: SimState in [a, b]:
		s.grid.add_surface(Vector3i(3, Fixtures.FLOOR_Y, 3), WATER, 150)
	for i in 120:
		LiquidRules.step(a)
		LiquidRules.step(b)
		b.grid.liquids_still_at = [-1, -1]
	assert_eq(a.grid.surface_amount, b.grid.surface_amount)
	assert_eq(a.grid.surface_type, b.grid.surface_type)
