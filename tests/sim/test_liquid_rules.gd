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
