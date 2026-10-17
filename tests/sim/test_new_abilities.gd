extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability


func _near_duel() -> SimState:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(5, Y, 2))
	return state


func test_frost_freezes_water_now_and_nips() -> void:
	var state := _near_duel()
	var bandit := Fixtures.bandit(state)
	state.grid.add_surface(bandit.cell, SimMaterials.Surface.WATER, 3)
	assert_true(state.apply_command(CastCommand.new(1, A.FROST, bandit.cell)))
	assert_eq(state.grid.surface_type[state.grid.index(bandit.cell)], SimMaterials.Surface.ICE)
	assert_eq(bandit.hp, 12 - SimAbilities.FROST_DAMAGE)


func test_frost_puts_out_fire() -> void:
	var state := _near_duel()
	var cell := Vector3i(5, Y, 4)
	state.apply_command(IgniteCommand.new(cell))
	state.apply_command(CastCommand.new(1, A.FROST, cell))
	assert_eq(state.grid.fire[state.grid.index(cell)], 0)


func test_oil_flask_spreads_oil() -> void:
	var state := _near_duel()
	assert_true(state.apply_command(CastCommand.new(1, A.OIL_FLASK, Vector3i(5, Y, 5))))
	assert_eq(state.grid.total_surface(SimMaterials.Surface.OIL), 5 * SimAbilities.OIL_FLASK_AMOUNT)
	assert_eq(Fixtures.hero(state).ap, 4 - 1)


func test_mend_heals_up_to_max_and_needs_a_wound() -> void:
	var state := _near_duel()
	var hero := Fixtures.hero(state)
	assert_false(state.apply_command(CastCommand.new(1, A.MEND, hero.cell)), "already at full HP")
	hero.hp = 17
	assert_true(state.apply_command(CastCommand.new(1, A.MEND, hero.cell)))
	assert_eq(hero.hp, 20)


func test_cleave_hits_everyone_adjacent() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	var friend := state.add_entity(SimEntity.character("Friend", Fixtures.PLAYERS, Vector3i(2, Y, 3), 10))
	var far := state.add_entity(SimEntity.character("Far", Fixtures.ENEMIES, Vector3i(6, Y, 6), 10))
	assert_true(state.apply_command(CastCommand.new(1, A.CLEAVE, bandit.cell)))
	assert_eq(bandit.hp, 12 - 4)
	assert_eq(friend.hp, 10 - 4, "cleave doesn't care whose side you're on")
	assert_eq(far.hp, 10)


func test_blink_moves_caster_to_free_cell_in_sight() -> void:
	var state := _near_duel()
	var hero := Fixtures.hero(state)
	assert_false(state.apply_command(CastCommand.new(1, A.BLINK, Fixtures.bandit(state).cell)), "occupied")
	assert_false(state.apply_command(CastCommand.new(1, A.BLINK, Vector3i(2, Y, 8))), "too far")
	assert_true(state.apply_command(CastCommand.new(1, A.BLINK, Vector3i(4, Y, 4))))
	assert_eq(hero.cell, Vector3i(4, Y, 4))


func test_steal_cannot_take_protected_weapon() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	hero.can_be_disarmed = false
	bandit.abilities.assign([A.STEAL])
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	state.apply_command(EndTurnCommand.new(Fixtures.PLAYERS))
	assert_false(state.apply_command(CastCommand.new(2, A.STEAL, hero.cell)), "nothing it is allowed to take")
	hero.inventory.assign(["Gold"])
	assert_true(state.apply_command(CastCommand.new(2, A.STEAL, hero.cell)))
	assert_eq(hero.weapon, "Sword")
	assert_true(bandit.inventory.has("Gold"))


func test_archetypes_build_roles() -> void:
	var ari := SimArchetypes.make("vanguard", "Ari", Fixtures.PLAYERS, Vector3i(1, Y, 1))
	assert_eq(ari.archetype, "vanguard")
	assert_eq(ari.max_hp, SimArchetypes.ROLES.vanguard.hp)
	assert_true(ari.abilities.has(A.CLEAVE))
	assert_false(ari.can_be_disarmed, "player characters keep their weapons")
	var thug := SimArchetypes.make("thug", "Thug", Fixtures.ENEMIES, Vector3i(1, Y, 1))
	assert_true(thug.can_be_disarmed)
	assert_true(thug.abilities.is_empty())


func test_every_role_is_valid() -> void:
	for role: String in SimArchetypes.ROLES:
		var e := SimArchetypes.make(role, role, Fixtures.ENEMIES, Vector3i(1, Y, 1))
		assert_gt(e.max_hp, 0, role)
		for ability in e.abilities:
			assert_between(ability, 0, SimAbilities.NAMES.size() - 1, role)
