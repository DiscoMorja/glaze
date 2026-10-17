extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const WATER := SimMaterials.Surface.WATER
const ICE := SimMaterials.Surface.ICE


func _frozen_puddle() -> SimState:
	var state := Fixtures.flat_state()
	state.grid.add_surface(Vector3i(4, Y, 4), WATER, 3)
	state.apply_command(ChillCommand.new(Vector3i(4, Y, 4)))
	state.step()
	return state


func test_chill_freezes_water() -> void:
	var state := _frozen_puddle()
	var grid := state.grid
	assert_eq(grid.surface_type[grid.index(Vector3i(4, Y, 4))], ICE)
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.FROZE).size(), 1)


func test_ice_melts_when_temperature_recovers() -> void:
	var state := _frozen_puddle()
	var grid := state.grid
	var i := grid.index(Vector3i(4, Y, 4))
	# Temperature climbs by THERMAL_RELAX_PER_TICK; ice melts once it is above freezing.
	var ticks_to_melt := (SimMaterials.FREEZE_TEMPERATURE - SimMaterials.CHILL_TEMPERATURE) / SimMaterials.THERMAL_RELAX_PER_TICK + 1
	state.step_ticks(ticks_to_melt - 2)
	assert_eq(grid.surface_type[i], ICE)
	state.step()
	assert_eq(grid.surface_type[i], WATER)


func test_fire_melts_ice_then_boils_it() -> void:
	var state := _frozen_puddle()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	state.drain_events()
	state.apply_command(IgniteCommand.new(c))
	state.step()
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.MELTED).size(), 1)
	state.step()
	assert_eq(grid.fire[grid.index(c)], 0)
	assert_gt(grid.total_gas(SimMaterials.Gas.STEAM), 0)


func test_temperature_returns_to_ambient() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	state.apply_command(ChillCommand.new(c))
	state.step_ticks(SimMaterials.AMBIENT_TEMPERATURE - SimMaterials.CHILL_TEMPERATURE)
	assert_eq(grid.temperature[grid.index(c)], SimMaterials.AMBIENT_TEMPERATURE)


func test_chill_puts_out_fire() -> void:
	var state := Fixtures.flat_state()
	var grid := state.grid
	var c := Vector3i(4, Y, 4)
	state.apply_command(IgniteCommand.new(c))
	state.apply_command(ChillCommand.new(c))
	assert_eq(grid.fire[grid.index(c)], 0)
