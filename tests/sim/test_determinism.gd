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


func _run_combat(state: SimState) -> void:
	state.add_entity(SimEntity.barrel("Oil barrel", Vector3i(7, Y, 7), SimMaterials.Surface.OIL, 100))
	state.apply_command(CastCommand.new(1, SimAbilities.Ability.FIREBOLT, Vector3i(7, Y, 7)))
	state.apply_command(MoveCommand.new(1, Vector3i(4, Y, 4)))
	for _round in 3:
		state.apply_command(EndTurnCommand.new(SimEntity.Faction.PLAYERS))
		var guard := 0
		while state.combat.side == SimEntity.Faction.ENEMIES and state.combat.active and guard < 20:
			state.apply_command(UtilityAi.next_command(state))
			guard += 1


func test_combat_is_deterministic() -> void:
	var a := Fixtures.duel_state()
	var b := Fixtures.duel_state()
	_run_combat(a)
	_run_combat(b)
	assert_eq(a.checksum(), b.checksum())
	assert_gt(a.tick, 0)


func test_duplicate_state_copies_entities() -> void:
	var original := Fixtures.duel_state()
	var copy := original.duplicate_state()
	assert_eq(copy.checksum(), original.checksum())
	copy.apply_command(MoveCommand.new(1, Vector3i(3, Y, 3)))
	assert_eq(Fixtures.hero(original).cell, Vector3i(2, Y, 2))
	assert_ne(copy.checksum(), original.checksum())


func test_rng_is_deterministic() -> void:
	var a := SimRng.new(42)
	var b := SimRng.new(42)
	for _i in 100:
		assert_eq(a.next_u32(), b.next_u32())
	assert_true(a.range_int(10) < 10)


## Copies share arrays until written (copy-on-write): a whole scenario of
## surfaces, fire, gas, chill and frost on a copy must leave the original alone,
## and the original keeps working afterwards.
func test_copies_never_write_into_the_original() -> void:
	var original := Fixtures.duel_state()
	original.apply_command(SpawnSurfaceCommand.new(Vector3i(3, Y, 3), SimMaterials.Surface.WATER, 60, 1))
	original.step_ticks(3)
	var before := original.checksum()
	var copy := original.duplicate_state()
	_run_scenario(copy)
	copy.apply_command(CastCommand.new(1, SimAbilities.Ability.FROST, Vector3i(3, Y, 3)))
	copy.step_ticks(4)
	assert_ne(copy.checksum(), before)
	assert_eq(original.checksum(), before, "the original is untouched")

	var twin := original.duplicate_state()
	_run_scenario(original)
	_run_scenario(twin)
	assert_eq(original.checksum(), twin.checksum(), "and both sides still evolve the same")
