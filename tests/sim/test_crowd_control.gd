extends GutTest
## Knockdown (stagger) and temperature (Frozen ... Burning).

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


## The duel, with the bandit next to the hero and a second hero ("Ally", id 3)
## next to both, all able to act. The bandit goes down at 2 stagger.
func _melee() -> SimState:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(3, Y, 2))
	var ally := state.add_entity(SimEntity.character("Ally", PLAYERS, Vector3i(3, Y, 3), 20, "Mace", 5, [], SimAbilities.all()))
	ally.ap = 4
	Fixtures.bandit(state).stagger_max = 2
	return state


func _end_round(state: SimState) -> void:
	state.apply_command(EndTurnCommand.new(PLAYERS))
	state.apply_command(EndTurnCommand.new(ENEMIES))


# --- Stagger and knockdown -----------------------------------------------------

func test_physical_hits_build_stagger() -> void:
	var state := _melee()
	var bandit := Fixtures.bandit(state)
	state.apply_command(AttackCommand.new(1, bandit.id))
	assert_eq(bandit.stagger, EntityOps.HIT_STAGGER, "a hit adds 1, whatever its damage")
	assert_false(bandit.knocked_down)


func test_two_characters_together_knock_down() -> void:
	var state := _melee()
	var bandit := Fixtures.bandit(state)
	state.apply_command(AttackCommand.new(1, bandit.id))
	state.apply_command(AttackCommand.new(3, bandit.id))
	assert_true(bandit.knocked_down, "down when the second hit lands")
	assert_eq(bandit.stagger, 0, "spent on the knockdown")


func test_stagger_clears_at_the_targets_turn_start() -> void:
	var state := _melee()
	var bandit := Fixtures.bandit(state)
	state.apply_command(AttackCommand.new(1, bandit.id))
	state.apply_command(EndTurnCommand.new(PLAYERS))
	assert_eq(bandit.stagger, 0, "one round to finish the job")


func test_knocked_down_skips_its_next_turn_then_acts() -> void:
	var state := _melee()
	var bandit := Fixtures.bandit(state)
	EntityOps.add_stagger(state, bandit, 99)
	assert_true(bandit.knocked_down)
	state.apply_command(EndTurnCommand.new(PLAYERS))
	assert_eq(bandit.ap, 0, "its turn is skipped")
	assert_true(bandit.knocked_down, "still down during the skipped turn")
	state.apply_command(EndTurnCommand.new(ENEMIES))
	assert_false(bandit.knocked_down, "gets up when the skipped turn ends")
	state.apply_command(EndTurnCommand.new(PLAYERS))
	assert_gt(bandit.ap, 0, "acts again the turn after")


func test_help_up_lets_a_fallen_ally_act_this_turn() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	EntityOps.add_stagger(state, hero, 99)
	assert_true(hero.knocked_down)
	assert_eq(hero.ap, 0)
	assert_true(state.apply_command(CastCommand.new(3, A.HELP_UP, hero.cell)))
	assert_false(hero.knocked_down)
	assert_eq(hero.ap, hero.max_ap)


func test_help_up_needs_a_fallen_ally() -> void:
	var state := _melee()
	assert_false(state.apply_command(CastCommand.new(3, A.HELP_UP, Fixtures.hero(state).cell)), "not down")
	EntityOps.add_stagger(state, Fixtures.bandit(state), 99)
	assert_false(state.apply_command(CastCommand.new(3, A.HELP_UP, Fixtures.bandit(state).cell)), "not an ally")


func test_shoving_into_a_wall_staggers_more() -> void:
	var state := _melee()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, state.get_entity(3), Vector3i(8, Y, 8))
	state.grid.fill_solid(Vector3i(4, Y, 2), Vector3i(4, Y + 2, 2))
	bandit.stagger_max = 9
	assert_true(state.apply_command(CastCommand.new(1, A.SHOVE, bandit.cell)))
	assert_eq(bandit.stagger, SimAbilities.SHOVE_STAGGER + SimAbilities.IMPACT_STAGGER, "the shove and the impact")


func test_no_stagger_outside_combat() -> void:
	var state := Fixtures.flat_state()
	var e := state.add_entity(SimEntity.character("Walker", PLAYERS, Vector3i(1, Y, 1), 20))
	EntityOps.add_stagger(state, e, 99)
	assert_false(e.knocked_down)


# --- Temperature ---------------------------------------------------------------

func test_one_frost_only_chills_a_second_freezes_and_ends_the_turn() -> void:
	var state := _melee()
	var bandit := Fixtures.bandit(state)
	state.apply_command(CastCommand.new(1, A.FROST, bandit.cell))
	assert_eq(bandit.temperature, -1, "one bolt: Cold, not frozen")
	EntityOps.change_temperature(state, bandit, -SimAbilities.FROST_CHILL)  # a second chill (rain + frost, two casters)
	assert_true(bandit.is_frozen())
	state.apply_command(EndTurnCommand.new(PLAYERS))
	assert_eq(bandit.ap, 0, "a frozen character skips its turn")
	assert_true(bandit.is_frozen(), "and stays frozen through it")
	state.apply_command(EndTurnCommand.new(ENEMIES))
	assert_eq(bandit.temperature, -1, "then thaws to Cold")


func test_fire_on_a_frozen_character_brings_it_back_to_normal() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	EntityOps.change_temperature(state, hero, -2)
	assert_true(hero.is_frozen())
	assert_eq(hero.ap, 0, "frozen: the turn is over")
	Fixtures.teach(state.get_entity(3), [A.FIREBOLT])
	EntityOps.place(state, state.get_entity(3), Vector3i(2, Y, 6))
	assert_true(state.apply_command(CastCommand.new(3, A.FIREBOLT, hero.cell)))
	assert_eq(hero.temperature, 0)
	assert_eq(hero.ap, hero.max_ap, "thawed on its own turn: it can act again")


func test_frost_on_a_burning_character_puts_the_fire_out() -> void:
	var state := _melee()
	var bandit := Fixtures.bandit(state)
	EntityOps.change_temperature(state, bandit, 2)
	assert_true(bandit.is_burning())
	state.apply_command(CastCommand.new(1, A.FROST, bandit.cell))
	assert_eq(bandit.temperature, 1, "Burning to Hot")


func test_cold_slows_like_oil() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	EntityOps.change_temperature(state, hero, -1)
	assert_true(hero.is_slowed())
	assert_eq(CombatRules.move_budget(hero), hero.ap * CombatRules.MOVE_COST_PER_AP / 2)


func test_hot_and_cold_fade_at_the_next_turn_start() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	EntityOps.change_temperature(state, hero, 1)
	_end_round(state)
	assert_eq(hero.temperature, 0)


func test_rain_douses_a_burning_character() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	EntityOps.change_temperature(state, hero, 2)
	Fixtures.teach(state.get_entity(3), [A.RAIN])
	assert_true(state.apply_command(CastCommand.new(3, A.RAIN, hero.cell)))
	assert_eq(hero.temperature, 0)


func test_temperature_round_trips_through_a_snapshot() -> void:
	var state := _melee()
	EntityOps.change_temperature(state, Fixtures.hero(state), -2)
	EntityOps.add_stagger(state, Fixtures.bandit(state), 4)
	var copy := SimState.from_snapshot(state.to_snapshot())
	assert_eq(copy.checksum(), state.checksum())


func test_water_cools_to_cold_at_most() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	for x in range(0, 2):
		state.grid.add_surface(Vector3i(x, Y, 2), SimMaterials.Surface.WATER, 20)
	assert_true(state.apply_command(MoveCommand.new(hero.id, Vector3i(0, Y, 2))))
	assert_eq(hero.temperature, -1, "two water cells: Cold, not Frozen")


func test_rain_cools_but_doesnt_freeze() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	Fixtures.teach(state.get_entity(3), [A.RAIN])
	assert_true(state.apply_command(CastCommand.new(3, A.RAIN, hero.cell)))
	assert_eq(hero.temperature, -1)


func test_a_normal_character_goes_down_at_three() -> void:
	var thug := SimArchetypes.make("thug", "Thug", ENEMIES, Vector3i(1, Y, 1))
	assert_eq(thug.stagger_max, 3)
	assert_eq(SimArchetypes.make("brute", "Brute", ENEMIES, Vector3i(1, Y, 1)).stagger_max, 5)


func test_falls_and_collisions_alone_dont_stagger() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	EntityOps.damage(state, hero, 3)
	assert_eq(hero.stagger, 0, "only hits by someone stagger")


## The hero knocked down on the enemies' turn, then the party's turn begins.
func _hero_down_on_its_turn() -> SimState:
	var state := _melee()
	state.apply_command(EndTurnCommand.new(PLAYERS))
	EntityOps.add_stagger(state, Fixtures.hero(state), 99)
	state.apply_command(EndTurnCommand.new(ENEMIES))
	return state


func test_an_ally_can_help_up_during_the_skipped_turn() -> void:
	var state := _hero_down_on_its_turn()
	var hero := Fixtures.hero(state)
	assert_true(hero.knocked_down)
	assert_eq(hero.ap, 0)
	assert_true(state.apply_command(CastCommand.new(3, A.HELP_UP, hero.cell)))
	assert_eq(hero.ap, hero.max_ap, "and it acts this turn after all")


func test_an_ally_can_thaw_a_frozen_character_during_its_skipped_turn() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	state.apply_command(EndTurnCommand.new(PLAYERS))
	EntityOps.change_temperature(state, hero, -2)
	state.apply_command(EndTurnCommand.new(ENEMIES))
	assert_true(hero.is_frozen(), "frozen through its own turn")
	EntityOps.change_temperature(state, hero, 2)
	assert_eq(hero.temperature, 0)
	assert_eq(hero.ap, hero.max_ap, "thawed: it acts this turn")


# --- Arriving in a cell, however it happens ----------------------------------------

## The bandit at (3, 1, 2) with nobody behind it, so a shove from the hero at
## (2, 1, 2) pushes it to (5, 1, 2) through (4, 1, 2).
func _shove_lane() -> SimState:
	var state := _melee()
	EntityOps.place(state, state.get_entity(3), Vector3i(8, Y, 8))
	Fixtures.bandit(state).stagger_max = 9
	return state


func test_shoved_into_oil_is_slowed_at_once() -> void:
	var state := _shove_lane()
	var bandit := Fixtures.bandit(state)
	state.grid.add_surface(Vector3i(5, Y, 2), SimMaterials.Surface.OIL, 20)
	assert_true(state.apply_command(CastCommand.new(1, A.SHOVE, bandit.cell)))
	assert_eq(bandit.cell, Vector3i(5, Y, 2))
	assert_true(bandit.is_slowed())


func test_shoved_through_fire_burns() -> void:
	var state := _shove_lane()
	var bandit := Fixtures.bandit(state)
	state.grid.set_fire(state.grid.index(Vector3i(4, Y, 2)), SimMaterials.FIRE_MAX)
	var hp := bandit.hp
	assert_true(state.apply_command(CastCommand.new(1, A.SHOVE, bandit.cell)))
	assert_eq(bandit.temperature, 1, "pushed through one fire cell: Hot")
	assert_eq(bandit.hp, hp - EntityOps.BURN_DAMAGE)


func test_shoved_onto_ice_staggers() -> void:
	var state := _shove_lane()
	var bandit := Fixtures.bandit(state)
	state.grid.add_surface(Vector3i(5, Y, 2), SimMaterials.Surface.ICE, 20)
	assert_true(state.apply_command(CastCommand.new(1, A.SHOVE, bandit.cell)))
	assert_eq(bandit.stagger, SimAbilities.SHOVE_STAGGER + EntityOps.ICE_STAGGER)


func test_teleported_into_water_cools() -> void:
	var state := _shove_lane()
	var bandit := Fixtures.bandit(state)
	state.grid.add_surface(Vector3i(6, Y, 6), SimMaterials.Surface.WATER, 20)
	assert_true(state.apply_command(CastCommand.new(1, A.TELEPORT, bandit.cell, Vector3i(6, Y, 6))))
	assert_eq(bandit.temperature, -1)


func test_blinking_into_oil_slows() -> void:
	var state := _shove_lane()
	var hero := Fixtures.hero(state)
	state.grid.add_surface(Vector3i(2, Y, 5), SimMaterials.Surface.OIL, 20)
	assert_true(state.apply_command(CastCommand.new(1, A.BLINK, Vector3i(2, Y, 5))))
	assert_true(hero.is_slowed())


# --- Death and revival -----------------------------------------------------------

func test_the_fallen_stay_as_corpses() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	EntityOps.damage(state, hero, 999)
	assert_false(hero.is_alive())
	assert_eq(state.corpse_at(hero.cell), hero)
	assert_null(state.entity_at(hero.cell), "the body doesn't block the cell")


func test_revive_works_after_combat_only() -> void:
	var state := _melee()
	var hero := Fixtures.hero(state)
	state.get_entity(3).abilities.append(A.REVIVE)
	EntityOps.damage(state, hero, 999)
	assert_false(state.apply_command(CastCommand.new(3, A.REVIVE, hero.cell)), "not during a fight")
	EntityOps.damage(state, Fixtures.bandit(state), 999)
	CombatRules.check_end(state)
	assert_false(state.combat.active)
	assert_true(state.apply_command(CastCommand.new(3, A.REVIVE, hero.cell)))
	assert_true(hero.is_alive())
	assert_eq(hero.hp, hero.max_hp * SimAbilities.REVIVE_HP_PERCENT / 100)


func test_party_roles_can_revive() -> void:
	assert_true(SimArchetypes.make("vanguard", "Ari", PLAYERS, Vector3i(1, Y, 1)).abilities.has(A.REVIVE))
	assert_false(SimArchetypes.make("thug", "Thug", ENEMIES, Vector3i(1, Y, 1)).abilities.has(A.REVIVE))
