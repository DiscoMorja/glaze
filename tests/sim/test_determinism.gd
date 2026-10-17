extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y


func _run_scenario(state: SimState) -> void:
	state.apply_command(SpawnSurfaceCommand.new(Vector3i(2, Y, 2), SimMaterials.Surface.OIL, 80, 2))
	state.apply_command(SpawnSurfaceCommand.new(Vector3i(6, 3, 6), SimMaterials.Surface.WATER, 120, 1))
	state.step_ticks(5)
	state.apply_command(IgniteCommand.new(Vector3i(2, Y, 2)))
	state.step_ticks(10)
	state.apply_command(ChillCommand.new(Vector3i(6, Y, 6), 2))
	state.step_ticks(25)


func test_same_commands_give_same_checksum() -> void:
	var a := Fixtures.flat_state()
	var b := Fixtures.flat_state()
	_run_scenario(a)
	_run_scenario(b)
	assert_eq(a.checksum(), b.checksum())


func test_checksum_detects_divergence() -> void:
	var a := Fixtures.flat_state()
	var b := Fixtures.flat_state()
	_run_scenario(a)
	_run_scenario(b)
	b.step()
	assert_ne(a.checksum(), b.checksum())


func test_duplicate_state_evolves_independently() -> void:
	var original := Fixtures.flat_state()
	original.apply_command(SpawnSurfaceCommand.new(Vector3i(4, Y, 4), SimMaterials.Surface.OIL, 60, 1))
	var control := original.duplicate_state()
	var preview := original.duplicate_state()
	assert_eq(preview.checksum(), original.checksum())

	preview.apply_command(IgniteCommand.new(Vector3i(4, Y, 4)))
	preview.step_ticks(5)
	original.step_ticks(5)
	control.step_ticks(5)
	assert_eq(original.checksum(), control.checksum(), "preview must not leak into the original")
	assert_ne(preview.checksum(), original.checksum())


func test_rng_is_deterministic() -> void:
	var a := SimRng.new(42)
	var b := SimRng.new(42)
	for _i in 100:
		assert_eq(a.next_u32(), b.next_u32())
	assert_true(a.range_int(10) < 10)
