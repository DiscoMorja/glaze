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


func _oil_cells(state: SimState) -> int:
	return state.grid.surface_type.count(SimMaterials.Surface.OIL)


func test_oil_flask_splashes_its_whole_puddle_at_once() -> void:
	var state := _near_duel()
	assert_true(state.apply_command(CastCommand.new(1, A.OIL_FLASK, Vector3i(5, Y, 5))))
	var splash := SimAbilities.splash_cells(state.grid, Vector3i(5, Y, 5), SimAbilities.OIL_FLASK_RADIUS).size()
	assert_eq(splash, 13, "a radius-2 disc")
	assert_eq(_oil_cells(state), splash)
	assert_eq(state.grid.total_surface(SimMaterials.Surface.OIL), splash * SimAbilities.OIL_FLASK_AMOUNT)
	assert_eq(Fixtures.hero(state).ap, 4 - 1)
	state.step_ticks(8)
	assert_eq(_oil_cells(state), splash, "and it doesn't creep afterwards")


func test_lighting_oil_sets_the_whole_puddle_alight_at_once() -> void:
	var state := _near_duel()
	state.apply_command(CastCommand.new(1, A.OIL_FLASK, Vector3i(5, Y, 5)))
	state.apply_command(IgniteCommand.new(Vector3i(5, Y, 7)))
	assert_eq(state.grid.fire_cells.size(), _oil_cells(state), "every oil cell burns right away")


func test_walking_through_oil_slows() -> void:
	var state := _near_duel()
	var hero := Fixtures.hero(state)
	state.grid.add_surface(hero.cell + Vector3i(1, 0, 0), SimMaterials.Surface.OIL, 20)
	assert_true(state.apply_command(MoveCommand.new(hero.id, hero.cell + Vector3i(1, 0, 0))))
	assert_eq(hero.slowed, EntityOps.SLOW_TURNS)
	var two_cells: Array[Vector3i] = [hero.cell + Vector3i(0, 0, 1), hero.cell + Vector3i(0, 0, 2)]
	assert_eq(MoveCommand.ap_cost(hero, hero.cell, two_cells), 2, "moving costs double")
	assert_eq(CombatRules.move_budget(hero), hero.ap * CombatRules.MOVE_COST_PER_AP / 2)


func test_slow_wears_off_after_its_turns() -> void:
	var state := _near_duel()
	var hero := Fixtures.hero(state)
	hero.slowed = EntityOps.SLOW_TURNS
	for _i in EntityOps.SLOW_TURNS:
		state.apply_command(EndTurnCommand.new(SimEntity.Faction.PLAYERS))
		state.apply_command(EndTurnCommand.new(SimEntity.Faction.ENEMIES))
	assert_eq(hero.slowed, 0)


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
	assert_eq(thug.abilities, [A.HELP_UP] as Array[int], "everyone can help an ally up")


func test_every_role_is_valid() -> void:
	for role: String in SimArchetypes.ROLES:
		var e := SimArchetypes.make(role, role, Fixtures.ENEMIES, Vector3i(1, Y, 1))
		assert_gt(e.max_hp, 0, role)
		for ability in e.abilities:
			assert_between(ability, 0, SimAbilities.NAMES.size() - 1, role)


func test_rain_lays_its_whole_puddle_at_once() -> void:
	var state := _near_duel()
	var hero := Fixtures.hero(state)
	hero.abilities.assign([A.RAIN])
	assert_true(state.apply_command(CastCommand.new(1, A.RAIN, Vector3i(5, Y, 5))))
	var splash := SimAbilities.splash_cells(state.grid, Vector3i(5, Y, 5), SimAbilities.RAIN_RADIUS).size()
	var water := func() -> int: return state.grid.surface_type.count(SimMaterials.Surface.WATER)
	assert_eq(water.call(), splash)
	state.step_ticks(8)
	assert_eq(water.call(), splash, "and it doesn't creep afterwards")


func test_rain_puts_out_fire_at_once() -> void:
	var state := _near_duel()
	var hero := Fixtures.hero(state)
	hero.abilities.assign([A.RAIN])
	for c in SimAbilities.splash_cells(state.grid, Vector3i(5, Y, 5), 2):
		state.grid.add_surface(c, SimMaterials.Surface.OIL, 24)
	FireRules.ignite(state, Vector3i(5, Y, 5))
	assert_gt(state.grid.fire_cells.size(), 0)
	assert_true(state.apply_command(CastCommand.new(1, A.RAIN, Vector3i(5, Y, 5))))
	assert_eq(state.grid.fire_cells.size(), 0, "no fire left the moment it lands")
	assert_gt(state.grid.total_gas(SimMaterials.Gas.STEAM), 0, "it steams")
	assert_eq(state.grid.surface_type[state.grid.index(Vector3i(5, Y, 5))], SimMaterials.Surface.WATER, "water where the burning oil was")


func test_oil_thrown_next_to_fire_catches_at_once() -> void:
	var state := _near_duel()
	var hero := Fixtures.hero(state)
	hero.abilities.assign([A.OIL_FLASK])
	# A lone fire one cell beyond the splash's edge.
	FireRules.ignite(state, Vector3i(5, Y, 8))
	assert_true(state.apply_command(CastCommand.new(1, A.OIL_FLASK, Vector3i(5, Y, 5))))
	var oil := state.grid.surface_type.count(SimMaterials.Surface.OIL)
	assert_eq(state.grid.fire_cells.size(), oil + 1, "the whole new puddle burns right away")


func test_oil_thrown_away_from_fire_stays_unlit() -> void:
	var state := _near_duel()
	Fixtures.hero(state).abilities.assign([A.OIL_FLASK])
	FireRules.ignite(state, Vector3i(10, Y, 10))
	assert_true(state.apply_command(CastCommand.new(1, A.OIL_FLASK, Vector3i(5, Y, 5))))
	assert_eq(state.grid.fire_cells.size(), 1)
