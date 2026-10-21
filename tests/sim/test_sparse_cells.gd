extends GutTest
## The grid's sparse surface and gas sets (SimGrid.surface_cells / gas_cells)
## must always cover every cell a whole-grid scan would find, through flows,
## fire, freezing, copies and snapshots: the rules only visit those cells.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const SURFACES := [SimMaterials.Surface.WATER, SimMaterials.Surface.OIL, SimMaterials.Surface.ICE,
		SimMaterials.Surface.VINES, SimMaterials.Surface.POISON]
const GASES := [SimMaterials.Gas.STEAM, SimMaterials.Gas.SMOKE, SimMaterials.Gas.POISON, SimMaterials.Gas.DARKNESS]


func _assert_covered(grid: SimGrid, why: String) -> void:
	assert_eq(grid.surface_indices(SURFACES), SimGrid.indices_of(grid.surface_type, SURFACES), "surfaces: " + why)
	assert_eq(grid.gas_indices(GASES), SimGrid.indices_of(grid.gas_type, GASES), "gases: " + why)


func test_sets_follow_flows_fire_and_frost() -> void:
	var state := Fixtures.flat_state(Vector3i(16, 6, 16))
	var grid := state.grid
	grid.add_surface(Vector3i(5, Y + 2, 5), SimMaterials.Surface.WATER, 300)  # falls and spreads
	grid.add_surface(Vector3i(10, Y, 10), SimMaterials.Surface.OIL, 200)
	grid.add_gas(Vector3i(8, Y, 3), SimMaterials.Gas.POISON, 90)  # heavy: creeps along the ground
	grid.add_gas(Vector3i(3, Y, 12), SimMaterials.Gas.SMOKE, 20)  # thin: rises
	state.step_ticks(6)
	_assert_covered(grid, "after flowing")
	FireRules.ignite(state, Vector3i(10, Y, 10))
	state.step_ticks(30)
	_assert_covered(grid, "after burning (oil used up, smoke made)")
	grid.edit_heat()
	for c in grid.disc_cells(Vector3i(5, Y, 5), 3):
		grid.set_temperature(grid.index(c), SimMaterials.CHILL_TEMPERATURE)
	state.step_ticks(4)
	_assert_covered(grid, "after freezing")
	state.step_ticks(200)
	_assert_covered(grid, "after melting and settling")


func test_copies_and_snapshots_keep_them() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 5, 12))
	state.grid.add_surface(Vector3i(4, Y, 4), SimMaterials.Surface.WATER, 120)
	state.grid.add_gas(Vector3i(7, Y, 7), SimMaterials.Gas.DARKNESS, 60)
	state.step_ticks(3)
	var copy := state.duplicate_state()
	copy.step_ticks(5)
	_assert_covered(copy.grid, "a copy stepped on")
	_assert_covered(state.grid, "the original, untouched by its copy")
	var loaded := SimState.from_snapshot(state.to_snapshot())
	_assert_covered(loaded.grid, "rebuilt from a snapshot")
	loaded.step_ticks(5)
	state.step_ticks(5)
	assert_eq(loaded.checksum(), state.checksum(), "and it steps on identically")
