extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y


func _all_commands() -> Array[SimCommand]:
	return [
		SpawnSurfaceCommand.new(Vector3i(2, Y, 3), SimMaterials.Surface.OIL, 40, 2),
		SpawnGasCommand.new(Vector3i(2, Y, 3), SimMaterials.Gas.SMOKE, 25, 1),
		IgniteCommand.new(Vector3i(4, Y, 4), 1),
		ChillCommand.new(Vector3i(5, Y, 1), 3),
		MoveCommand.new(3, Vector3i(1, Y, 7)),
		AttackCommand.new(3, 4),
		CastCommand.new(3, SimAbilities.Ability.TELEPORT, Vector3i(2, Y, 2), Vector3i(6, Y + 2, 6)),
		EndTurnCommand.new(SimEntity.Faction.ENEMIES),
		StartCombatCommand.new(),
	]


func test_commands_round_trip_through_registry() -> void:
	for command in _all_commands():
		var rebuilt := SimCommandRegistry.from_dict(command.to_dict())
		assert_not_null(rebuilt)
		assert_eq(rebuilt.to_dict(), command.to_dict())


func test_commands_reject_out_of_bounds_and_solid_cells() -> void:
	var state := Fixtures.flat_state()
	assert_false(state.apply_command(IgniteCommand.new(Vector3i(-1, Y, 0))))
	assert_false(state.apply_command(IgniteCommand.new(Vector3i(4, 0, 4))), "floor is solid")
	assert_false(state.apply_command(SpawnSurfaceCommand.new(Vector3i(4, Y, 4), SimMaterials.Surface.NONE)))
	assert_false(state.apply_command(SpawnSurfaceCommand.new(Vector3i(4, Y, 4), SimMaterials.Surface.WATER, 0)))


func test_rejected_command_changes_nothing() -> void:
	var state := Fixtures.flat_state()
	var before := state.checksum()
	state.apply_command(ChillCommand.new(Vector3i(99, 99, 99)))
	assert_eq(state.checksum(), before)


func test_spawn_surface_fills_disc() -> void:
	var state := Fixtures.flat_state()
	state.apply_command(SpawnSurfaceCommand.new(Vector3i(4, Y, 4), SimMaterials.Surface.WATER, 10, 1))
	assert_eq(state.grid.total_surface(SimMaterials.Surface.WATER), 50)
