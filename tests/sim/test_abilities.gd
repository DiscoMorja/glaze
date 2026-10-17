extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability


func _near_duel() -> SimState:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(5, Y, 2))
	return state


func test_firebolt_damages_and_ignites() -> void:
	var state := _near_duel()
	var bandit := Fixtures.bandit(state)
	assert_true(state.apply_command(CastCommand.new(1, A.FIREBOLT, bandit.cell)))
	assert_eq(bandit.hp, 12 - SimAbilities.FIREBOLT_DAMAGE)
	assert_gt(state.grid.fire[state.grid.index(bandit.cell)], 0)
	assert_eq(Fixtures.hero(state).ap, 4 - 2)


func test_firebolt_out_of_range_is_rejected() -> void:
	var state := Fixtures.duel_state()
	assert_false(state.apply_command(CastCommand.new(1, A.FIREBOLT, Vector3i(9, Y, 11))))


func test_rain_puts_water_down_and_extinguishes() -> void:
	var state := _near_duel()
	var bandit := Fixtures.bandit(state)
	state.apply_command(IgniteCommand.new(bandit.cell))
	assert_true(state.apply_command(CastCommand.new(1, A.RAIN, bandit.cell)))
	assert_eq(state.grid.surface_type[state.grid.index(bandit.cell)], SimMaterials.Surface.WATER)
	state.step()
	assert_eq(state.grid.fire[state.grid.index(bandit.cell)], 0)


func test_teleport_drops_target_from_height() -> void:
	var state := _near_duel()
	var bandit := Fixtures.bandit(state)
	var high := Vector3i(5, Y + 3, 5)
	assert_true(state.apply_command(CastCommand.new(1, A.TELEPORT, bandit.cell, high)))
	assert_eq(bandit.cell, Vector3i(5, Y, 5))
	assert_eq(bandit.hp, 12 - 2 * EntityOps.FALL_DAMAGE_PER_LEVEL)


func test_teleport_rejects_heavy_or_blocked() -> void:
	var state := _near_duel()
	var bandit := Fixtures.bandit(state)
	assert_false(state.apply_command(CastCommand.new(1, A.TELEPORT, bandit.cell, Fixtures.hero(state).cell)), "destination occupied")
	bandit.mass = SimAbilities.TELEPORT_MAX_MASS + 1
	assert_false(state.apply_command(CastCommand.new(1, A.TELEPORT, bandit.cell, Vector3i(6, Y, 6))))


func test_shove_pushes_two_cells() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	assert_true(state.apply_command(CastCommand.new(1, A.SHOVE, bandit.cell)))
	assert_eq(bandit.cell, Vector3i(5, Y, 2))
	assert_eq(bandit.hp, 12)


func test_shove_into_wall_hurts() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	state.grid.fill_solid(Vector3i(4, Y, 2), Vector3i(4, Y + 2, 2))
	state.apply_command(CastCommand.new(1, A.SHOVE, bandit.cell))
	assert_eq(bandit.cell, Vector3i(3, Y, 2))
	assert_eq(bandit.hp, 12 - EntityOps.COLLISION_DAMAGE)


func test_shove_off_a_ledge() -> void:
	var state := Fixtures.flat_state(Vector3i(10, 7, 6))
	state.grid.fill_solid(Vector3i(0, Y, 0), Vector3i(4, Y + 2, 5))  # platform, top at y = 4
	var top := Y + 3
	var hero := state.add_entity(SimEntity.character("Hero", Fixtures.PLAYERS, Vector3i(3, top, 2), 20))
	var bandit := state.add_entity(SimEntity.character("Bandit", Fixtures.ENEMIES, Vector3i(4, top, 2), 12))
	state.apply_command(StartCombatCommand.new())
	assert_true(state.apply_command(CastCommand.new(hero.id, A.SHOVE, bandit.cell)))
	assert_eq(bandit.cell, Vector3i(5, Y, 2))
	assert_eq(bandit.hp, 12 - 2 * EntityOps.FALL_DAMAGE_PER_LEVEL)


func test_steal_takes_weapon_first() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	assert_true(state.apply_command(CastCommand.new(1, A.STEAL, bandit.cell)))
	assert_eq(bandit.weapon, "")
	assert_eq(bandit.attack_damage(), bandit.unarmed_damage)
	assert_true(Fixtures.hero(state).inventory.has("Club"))
	assert_true(state.apply_command(CastCommand.new(1, A.STEAL, bandit.cell)))
	assert_true(Fixtures.hero(state).inventory.has("Gold"))
	assert_false(state.apply_command(CastCommand.new(1, A.STEAL, bandit.cell)), "nothing left to steal")


func test_adjacent_abilities_need_adjacency() -> void:
	var state := _near_duel()
	assert_false(state.apply_command(CastCommand.new(1, A.SHOVE, Fixtures.bandit(state).cell)))
	assert_false(state.apply_command(CastCommand.new(1, A.STEAL, Fixtures.bandit(state).cell)))
