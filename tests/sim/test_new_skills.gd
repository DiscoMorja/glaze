extends GutTest
## Progression phase B (GDD §5.9): vines, poison, poison gas, ranged weapons,
## the new school skills, Hot = speed, and skill tomes.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES
const VINES := SimMaterials.Surface.VINES
const POISON := SimMaterials.Surface.POISON
const WATER := SimMaterials.Surface.WATER


func _surface(state: SimState, c: Vector3i) -> int:
	return state.grid.surface_type[state.grid.index(c)]


func _gas(state: SimState, c: Vector3i) -> int:
	return state.grid.gas_type[state.grid.index(c)]


## The duel with the bandit next to the hero (hero (2, 2), bandit (3, 2)).
func _adjacent() -> SimState:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(3, Y, 2))
	return state


# --- Vines --------------------------------------------------------------------------

func test_overgrowth_grows_vines_that_slow_and_burn() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(6, Y, 6))
	assert_true(state.apply_command(CastCommand.new(1, A.OVERGROWTH, Vector3i(6, Y, 6))))
	assert_eq(_surface(state, Vector3i(6, Y, 6)), VINES)
	assert_gt(bandit.slowed, 0, "caught in the vines")
	FireRules.ignite(state, Vector3i(6, Y, 6))
	assert_gt(state.grid.fire_cells.size(), 1, "vines carry fire like oil")
	state.step_ticks(SimMaterials.FIRE_MAX + 4)
	assert_eq(_surface(state, Vector3i(6, Y, 6)), SimMaterials.Surface.NONE, "burnt away")


func test_frost_kills_vines() -> void:
	var state := Fixtures.duel_state()
	state.apply_command(CastCommand.new(1, A.OVERGROWTH, Vector3i(6, Y, 6)))
	Fixtures.hero(state).cooldowns.fill(0)
	assert_true(state.apply_command(CastCommand.new(1, A.FROST, Vector3i(6, Y, 6))))
	assert_eq(_surface(state, Vector3i(6, Y, 6)), SimMaterials.Surface.NONE)


# --- Poison -------------------------------------------------------------------------

func test_blight_poisons_water_that_hurts_until_rain_washes_it() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	var c := Vector3i(6, Y, 6)
	EntityOps.place(state, bandit, c)
	state.grid.add_surface(c, WATER, 20)
	assert_true(state.apply_command(CastCommand.new(1, A.BLIGHT, c)))
	assert_eq(_surface(state, c), POISON)
	var hp := bandit.hp
	EntityOps.turn_start(state, bandit)
	assert_eq(bandit.hp, hp - SimMaterials.POISON_DAMAGE, "standing in poison hurts each turn")
	Fixtures.hero(state).cooldowns.fill(0)
	assert_true(state.apply_command(CastCommand.new(1, A.RAIN, c)))
	assert_eq(_surface(state, c), WATER, "rain washes it clean")


func test_blight_needs_something_to_rot() -> void:
	var state := Fixtures.duel_state()
	assert_false(CastCommand.new(1, A.BLIGHT, Vector3i(6, Y, 6)).validate(state))


func test_a_blighted_corpse_makes_heavy_gas_that_explodes_in_fire() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	var c := Vector3i(6, Y, 6)
	EntityOps.place(state, bandit, c)
	EntityOps.damage(state, bandit, 100)
	assert_true(state.apply_command(CastCommand.new(1, A.BLIGHT, c)))
	assert_eq(_gas(state, c), SimMaterials.Gas.POISON)
	assert_false(CastCommand.new(1, A.BLIGHT, c).validate(state), "a body bursts once")
	state.step_ticks(2)
	assert_eq(_gas(state, c), SimMaterials.Gas.POISON, "heavy: it stays on the ground")
	var victim := state.add_entity(SimEntity.character("Victim", ENEMIES, Vector3i(7, Y, 6), 20))
	FireRules.ignite(state, Vector3i(6, Y, 7))
	assert_lte(victim.hp, 20 - SimMaterials.EXPLOSION_DAMAGE, "caught in the blast (and maybe the fire after)")
	assert_eq(_gas(state, c), SimMaterials.Gas.NONE, "the cloud is gone")
	assert_gt(state.grid.fire[state.grid.index(c)], 0, "and burns where it was")


# --- Fire and Death skills ----------------------------------------------------------

func test_kindle_makes_an_ally_hot_and_hot_means_speed() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	assert_true(state.apply_command(CastCommand.new(1, A.KINDLE, hero.cell)), "on yourself too")
	assert_eq(hero.temperature, 1)
	state.apply_command(EndTurnCommand.new(PLAYERS))
	state.apply_command(EndTurnCommand.new(ENEMIES))
	assert_eq(hero.ap, CombatRules.AP_CAP, "4 left banked... capped, so check a fresh turn below")
	hero.ap = 0
	hero.temperature = 1
	state.apply_command(EndTurnCommand.new(PLAYERS))
	state.apply_command(EndTurnCommand.new(ENEMIES))
	assert_eq(hero.ap, hero.max_ap + 1, "a Hot character starts its turn with an extra AP")


func test_kindle_sets_an_oil_barrel_alight() -> void:
	var state := Fixtures.duel_state()
	var barrel := state.add_entity(SimEntity.barrel("Barrel", Vector3i(5, Y, 5), SimMaterials.Surface.OIL, 60))
	assert_true(state.apply_command(CastCommand.new(1, A.KINDLE, barrel.cell)))
	assert_gt(state.grid.fire[state.grid.index(barrel.cell)], 0)


func test_drain_heals_what_it_takes() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, hero, Vector3i(6, Y, 9))
	hero.hp = 10
	var damage := SimAbilities.DRAIN_DAMAGE + SimAbilities.potency(hero, A.DRAIN)
	assert_true(state.apply_command(CastCommand.new(1, A.DRAIN, bandit.cell)))
	assert_eq(bandit.hp, 12 - damage)
	assert_eq(hero.hp, 10 + damage)


# --- Psychic and Rogue --------------------------------------------------------------

func test_distract_turns_a_watcher_away() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 5, 12))
	var thief := state.add_entity(SimEntity.character("Cel", PLAYERS, Vector3i(2, Y, 2), 10, "", 0, [], [A.DISTRACT]))
	var guard := state.add_entity(SimArchetypes.make("guard", "Guard", SimEntity.Faction.NEUTRAL, Vector3i(2, Y, 6)))
	guard.facing = SimPerception.FACINGS.find(Vector3i(0, 0, -1))  # looking at the thief
	guard.home_facing = guard.facing
	assert_true(SimPerception.can_see(state, guard, thief))
	assert_true(state.apply_command(CastCommand.new(thief.id, A.DISTRACT, guard.cell)))
	assert_false(SimPerception.can_see(state, guard, thief), "its back is turned")
	state.step_ticks(SimPerception.LOOK_TICKS)
	assert_false(SimPerception.can_see(state, guard, thief), "and it doesn't look around while distracted")
	state.step_ticks(SimAbilities.DISTRACT_TURNS * CombatRules.REALTIME_TICKS_PER_TURN + SimPerception.LOOK_TICKS)
	assert_eq(guard.distracted, 0)


func test_backstab_doubles_from_behind() -> void:
	var state := _adjacent()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	bandit.facing = SimPerception.FACINGS.find(Vector3i(-1, 0, 0))  # facing the hero
	assert_true(state.apply_command(CastCommand.new(1, A.BACKSTAB, bandit.cell)))
	assert_eq(bandit.hp, 12 - 4, "from the front: a normal hit")
	hero.cooldowns.fill(0)
	bandit.facing = SimPerception.FACINGS.find(Vector3i(1, 0, 0))
	bandit.hp = 12
	assert_true(state.apply_command(CastCommand.new(1, A.BACKSTAB, bandit.cell)))
	assert_eq(bandit.hp, 12 - 8, "from behind: double")


# --- Ranged weapons and Ranger ------------------------------------------------------

## The duel with a bow in the hero's hands, the bandit 5 cells away.
func _archery() -> SimState:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	EquipRules.put(hero, "main_hand", "Shortbow")
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(7, Y, 2))
	return state


func test_bows_shoot_in_range_and_sight() -> void:
	var state := _archery()
	var bandit := Fixtures.bandit(state)
	assert_true(state.apply_command(AttackCommand.new(1, 2)))
	assert_eq(bandit.hp, 12 - 3)
	EntityOps.place(state, bandit, Vector3i(10, Y, 10))
	assert_false(AttackCommand.new(1, 2).validate(state), "out of range")
	EntityOps.place(state, bandit, Vector3i(7, Y, 2))
	state.grid.fill_solid(Vector3i(5, Y, 1), Vector3i(5, Y + 2, 3))
	assert_false(AttackCommand.new(1, 2).validate(state), "a wall in the way")


func test_shooting_down_hits_harder() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 6, 12))
	state.grid.fill_solid(Vector3i(0, Y, 0), Vector3i(3, Y + 1, 3))  # a 2-high platform
	var archer := state.add_entity(SimEntity.character("Archer", PLAYERS, Vector3i(1, Y + 2, 1), 10, "Shortbow", 3))
	var target := state.add_entity(SimEntity.character("Target", ENEMIES, Vector3i(6, Y, 1), 20))
	assert_eq(StatRules.hit_damage(archer, target), 3 + 2, "+1 per level above")


func test_pinning_shot_holds_the_target_through_its_next_turn() -> void:
	var state := _archery()
	var bandit := Fixtures.bandit(state)
	assert_true(state.apply_command(CastCommand.new(1, A.PINNING_SHOT, bandit.cell)))
	assert_gt(bandit.pinned, 0)
	state.apply_command(EndTurnCommand.new(PLAYERS))
	assert_false(MoveCommand.new(2, Vector3i(8, Y, 2)).validate(state), "can't move this turn")
	state.apply_command(EndTurnCommand.new(ENEMIES))
	state.apply_command(EndTurnCommand.new(PLAYERS))
	assert_eq(bandit.pinned, 0)
	assert_true(MoveCommand.new(2, Vector3i(8, Y, 2)).validate(state), "free again")


func test_pinning_shot_needs_a_ranged_weapon() -> void:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(7, Y, 2))
	assert_false(CastCommand.new(1, A.PINNING_SHOT, Vector3i(7, Y, 2)).validate(state))


func test_loaded_shot_fires_the_arrow_it_carries() -> void:
	var state := _archery()
	var hero := Fixtures.hero(state)
	var c := Vector3i(7, Y, 5)
	assert_false(CastCommand.new(1, A.LOADED_SHOT, c).validate(state), "no arrows")
	hero.inventory.assign(["Oil arrows", "Fire arrows"])
	assert_true(state.apply_command(CastCommand.new(1, A.LOADED_SHOT, c)))
	assert_eq(_surface(state, c), SimMaterials.Surface.OIL, "the oil bulb bursts")
	assert_eq(hero.inventory, ["Fire arrows"] as Array[String], "the arrow is used up")
	hero.cooldowns.fill(0)
	hero.ap = 4
	assert_true(state.apply_command(CastCommand.new(1, A.LOADED_SHOT, c)))
	assert_gt(state.grid.fire[state.grid.index(c)], 0, "and the fire arrow lights it")
	assert_true(hero.inventory.is_empty())


func test_archers_shoot_from_where_they_stand() -> void:
	var state := Fixtures.duel_state()
	var archer := SimArchetypes.make("archer", "Archer", ENEMIES, Vector3i(7, Y, 2))
	state.entities[1] = archer  # replace the bandit (id 2)
	archer.id = 2
	archer.in_combat = true
	state.apply_command(EndTurnCommand.new(PLAYERS))
	var command := UtilityAi.next_command(state)
	assert_true(command is AttackCommand or (command is CastCommand and SimAbilities.SHOTS.has((command as CastCommand).ability)),
			"it shoots instead of walking up")


# --- Tomes --------------------------------------------------------------------------

func test_tomes_teach_skills_your_rank_allows() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 5, 12))
	var e := state.add_entity(SimArchetypes.make("vanguard", "Ari", PLAYERS, Vector3i(2, Y, 2), ["Drain tome", "Blight tome"] as Array[String]))
	assert_false(UseItemCommand.new(e.id, 0).validate(state), "no Death rank")
	assert_eq(UseItemCommand.cant_learn(state, e, "Drain tome"), "Needs Death 1")
	e.schools[StatRules.School.DEATH] = 1
	assert_true(state.apply_command(UseItemCommand.new(e.id, 0)))
	assert_true(e.abilities.has(A.DRAIN))
	assert_eq(e.inventory, ["Blight tome"] as Array[String], "read and gone")
	assert_false(UseItemCommand.new(e.id, 0).validate(state), "Blight needs Death 2")
	e.schools[StatRules.School.DEATH] = 2
	state.combat.active = true
	assert_false(UseItemCommand.new(e.id, 0).validate(state), "no reading in a fight")
