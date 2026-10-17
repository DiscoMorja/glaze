extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const STEAM := SimMaterials.Gas.STEAM


func test_gas_rises_to_ceiling() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var top_y := grid.size.y - 1
	grid.add_gas(Vector3i(4, Fixtures.FLOOR_Y, 4), STEAM, 80)
	state.step_ticks(top_y - Fixtures.FLOOR_Y)
	assert_eq(grid.gas_type[grid.index(Vector3i(4, top_y, 4))], STEAM)
	assert_eq(grid.gas_amount[grid.index(Vector3i(4, Fixtures.FLOOR_Y, 4))], 0)


func test_gas_spreads_under_ceiling() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var top := Vector3i(4, grid.size.y - 1, 4)
	grid.add_gas(top, STEAM, 100)
	state.step_ticks(3)
	for n: Vector3i in SimGrid.NEIGHBORS_4:
		assert_eq(grid.gas_type[grid.index(top + n)], STEAM)


func test_gas_decays_away() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	grid.add_gas(Vector3i(4, Fixtures.FLOOR_Y, 4), STEAM, 20)
	state.step_ticks(20)
	assert_eq(grid.total_gas(STEAM), 0)
