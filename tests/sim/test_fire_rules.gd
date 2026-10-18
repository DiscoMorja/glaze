extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const OIL := SimMaterials.Surface.OIL
const WATER := SimMaterials.Surface.WATER


func test_fire_spreads_along_oil_trail() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	for x in range(1, 8):
		grid.add_surface(Vector3i(x, Y, 4), OIL, 50)
	assert_true(state.apply_command(IgniteCommand.new(Vector3i(1, Y, 4))))
	state.step_ticks(6)
	assert_gt(grid.fire[grid.index(Vector3i(7, Y, 4))], 0, "fire should reach the end of the trail")


func test_fire_does_not_spread_to_bare_floor() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	grid.add_surface(c, OIL, 5)
	state.apply_command(IgniteCommand.new(c))
	state.step_ticks(3)
	for n: Vector3i in SimGrid.NEIGHBORS_4:
		assert_eq(grid.fire[grid.index(c + n)], 0)


func test_burning_consumes_fuel_and_makes_smoke() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	grid.add_surface(c, OIL, 5)
	state.apply_command(IgniteCommand.new(c))
	state.step_ticks(ceili(5.0 / SimMaterials.OIL_BURN_PER_TICK))
	assert_eq(grid.total_surface(OIL), 0)
	assert_gt(grid.total_gas(SimMaterials.Gas.SMOKE), 0)


func test_fire_without_fuel_burns_out() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	state.apply_command(IgniteCommand.new(c))
	state.drain_events()
	state.step_ticks(SimMaterials.FIRE_MAX / SimMaterials.FIRE_DECAY)
	assert_eq(grid.fire[grid.index(c)], 0)
	var burned_out := Fixtures.events_of_type(state.drain_events(), SimEvent.Type.BURNED_OUT)
	assert_eq(burned_out.size(), 1)


func test_fire_on_water_becomes_steam() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	grid.add_surface(c, WATER, 3)
	state.apply_command(IgniteCommand.new(c))
	state.step()
	assert_eq(grid.fire[grid.index(c)], 0)
	assert_gt(grid.total_gas(SimMaterials.Gas.STEAM), 0)
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.EXTINGUISHED).size(), 1)


func test_fire_heats_its_cell() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	state.apply_command(IgniteCommand.new(c))
	state.step()
	assert_gt(grid.temperature[grid.index(c)], SimMaterials.AMBIENT_TEMPERATURE)


func test_a_lit_oil_flask_puddle_burns_three_rounds() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	for cell in SimAbilities.splash_cells(grid, c, SimAbilities.OIL_FLASK_RADIUS):
		grid.add_surface(cell, OIL, SimAbilities.OIL_FLASK_AMOUNT)
	FireRules.ignite(state, c)
	var round_ticks := 2 * CombatRules.TICKS_PER_SIDE_TURN
	state.step_ticks(3 * round_ticks - 1)
	assert_gt(grid.fire_cells.size(), 0, "still burning late in the third round")
	state.step()
	assert_eq(grid.fire_cells.size(), 0, "out after three rounds")
