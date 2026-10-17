extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")


func test_index_and_coord_round_trip() -> void:
	var grid := SimGrid.new(Vector3i(5, 3, 7))
	for c in [Vector3i(0, 0, 0), Vector3i(4, 2, 6), Vector3i(1, 2, 3), Vector3i(4, 0, 0)]:
		assert_eq(grid.coord(grid.index(c)), c)
	assert_eq(grid.index(Vector3i(4, 2, 6)), grid.cell_count - 1)


func test_out_of_bounds_counts_as_solid() -> void:
	var grid := SimGrid.new(Vector3i(3, 3, 3))
	assert_true(grid.is_solid(Vector3i(-1, 0, 0)))
	assert_true(grid.is_solid(Vector3i(0, 3, 0)))
	assert_false(grid.is_solid(Vector3i(1, 1, 1)))


func test_floor_supports_cells_above_it() -> void:
	var grid := Fixtures.flat_state().grid
	assert_true(grid.is_supported(Vector3i(4, Fixtures.FLOOR_Y, 4)))
	assert_false(grid.is_supported(Vector3i(4, Fixtures.FLOOR_Y + 1, 4)))


func test_making_cells_solid_clears_contents() -> void:
	var grid := Fixtures.flat_state().grid
	var c := Vector3i(2, Fixtures.FLOOR_Y, 2)
	grid.add_surface(c, SimMaterials.Surface.WATER, 50)
	grid.fill_solid(c, c)
	assert_eq(grid.surface_type[grid.index(c)], SimMaterials.Surface.NONE)
	assert_eq(grid.surface_amount[grid.index(c)], 0)


func test_add_surface_refuses_different_material() -> void:
	var grid := Fixtures.flat_state().grid
	var c := Vector3i(2, Fixtures.FLOOR_Y, 2)
	assert_true(grid.add_surface(c, SimMaterials.Surface.WATER, 10))
	assert_true(grid.add_surface(c, SimMaterials.Surface.WATER, 5))
	assert_false(grid.add_surface(c, SimMaterials.Surface.OIL, 10))
	assert_eq(grid.surface_amount[grid.index(c)], 15)


func test_disc_cells_skips_solid_and_uses_radius() -> void:
	var grid := Fixtures.flat_state().grid
	var center := Vector3i(4, Fixtures.FLOOR_Y, 4)
	assert_eq(grid.disc_cells(center, 0).size(), 1)
	assert_eq(grid.disc_cells(center, 1).size(), 5)
	grid.fill_solid(Vector3i(5, Fixtures.FLOOR_Y, 4), Vector3i(5, Fixtures.FLOOR_Y, 4))
	assert_eq(grid.disc_cells(center, 1).size(), 4)


func test_duplicate_is_independent() -> void:
	var grid := Fixtures.flat_state().grid
	var copy := grid.duplicate_grid()
	copy.add_surface(Vector3i(1, Fixtures.FLOOR_Y, 1), SimMaterials.Surface.OIL, 30)
	assert_eq(grid.total_surface(SimMaterials.Surface.OIL), 0)
	assert_eq(copy.total_surface(SimMaterials.Surface.OIL), 30)
