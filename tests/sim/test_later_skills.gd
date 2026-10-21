extends GutTest
## The "Later" school skills (GDD §5.9): Combust, Glacier, Wellspring, Shroud,
## Dread, Brace, Smoke Bomb, Snare; their tomes; and seeded loot tables.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES
const WATER := SimMaterials.Surface.WATER
const LATER := [A.COMBUST, A.GLACIER, A.WELLSPRING, A.SHROUD, A.DREAD, A.BRACE, A.SMOKE_BOMB, A.SNARE]


func _surface(state: SimState, c: Vector3i) -> int:
	return state.grid.surface_type[state.grid.index(c)]


func _gas(state: SimState, c: Vector3i) -> int:
	return state.grid.gas_type[state.grid.index(c)]


## The duel, with the hero ranked for the Later skills.
func _duel() -> SimState:
	var state := Fixtures.duel_state()
	for ability: int in LATER:
		Fixtures.rank_for(Fixtures.hero(state), ability)
	return state


func _water_around(state: SimState, c: Vector3i, radius: int) -> void:
	for cell in SimAbilities.splash_cells(state.grid, c, radius):
		state.grid.add_surface(cell, WATER, 20)


# --- Fire: Combust ------------------------------------------------------------------

func test_combust_bursts_the_hot_and_needs_someone_hot() -> void:
	var state := _duel()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(6, Y, 6))
	assert_false(CastCommand.new(1, A.COMBUST, bandit.cell).validate(state), "nobody hot")
	EntityOps.change_temperature(state, bandit, 1)
	var hp := bandit.hp
	assert_true(state.apply_command(CastCommand.new(1, A.COMBUST, Vector3i(5, Y, 5))))
	assert_lt(bandit.hp, hp)
	assert_gt(state.grid.fire[state.grid.index(bandit.cell)], 0, "its cell is alight")


func test_combust_spares_the_caster() -> void:
	var state := _duel()
	var hero := Fixtures.hero(state)
	EntityOps.change_temperature(state, hero, 1)
	assert_true(SimAbilities.combust_victims(state, hero, hero.cell).is_empty())


# --- Ice: Glacier -------------------------------------------------------------------

func test_glacier_freezes_the_pond_and_who_wades_in_it() -> void:
	var state := _duel()
	var bandit := Fixtures.bandit(state)
	var c := Vector3i(6, Y, 6)
	EntityOps.place(state, bandit, c)
	assert_false(CastCommand.new(1, A.GLACIER, c).validate(state), "no water")
	_water_around(state, c, 1)
	assert_true(state.apply_command(CastCommand.new(1, A.GLACIER, c)))
	assert_eq(_surface(state, c), SimMaterials.Surface.ICE)
	assert_eq(_surface(state, c + Vector3i(1, 0, 0)), SimMaterials.Surface.ICE)
	assert_true(bandit.is_frozen())


# --- Life: Wellspring ---------------------------------------------------------------

func test_wellspring_heals_everyone_in_the_water() -> void:
	var state := _duel()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(4, Y, 2))
	hero.hp = 10
	bandit.hp = 5
	assert_false(CastCommand.new(1, A.WELLSPRING, hero.cell).validate(state), "nobody in water")
	state.grid.add_surface(bandit.cell, WATER, 20)
	assert_true(state.apply_command(CastCommand.new(1, A.WELLSPRING, hero.cell)))
	assert_gt(bandit.hp, 5, "friend or foe")
	assert_eq(hero.hp, 10, "dry, so not healed")


# --- Death: Shroud; Rogue: Smoke Bomb -------------------------------------------------

func test_shroud_blocks_sight_through_it() -> void:
	var state := _duel()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(9, Y, 2))
	assert_true(SimLos.has_line_of_sight(state.grid, Vector3i(2, Y, 2), bandit.cell))
	assert_true(state.apply_command(CastCommand.new(1, A.SHROUD, Vector3i(6, Y, 2))))
	assert_eq(_gas(state, Vector3i(6, Y, 2)), SimMaterials.Gas.DARKNESS)
	assert_false(SimLos.has_line_of_sight(state.grid, Vector3i(2, Y, 2), bandit.cell))
	assert_false(CastCommand.new(1, A.FIREBOLT, bandit.cell).validate(state), "can't aim through it")
	state.step_ticks(8)
	assert_eq(_gas(state, Vector3i(6, Y, 2)), SimMaterials.Gas.DARKNESS, "it lingers on the ground")


func test_smoke_bomb_hangs_low_while_thick_and_rises_when_thin() -> void:
	var state := _duel()
	var c := Vector3i(5, Y, 5)
	assert_true(state.apply_command(CastCommand.new(1, A.SMOKE_BOMB, c)))
	GasRules.step(state)
	GasRules.step(state)
	assert_eq(_gas(state, c), SimMaterials.Gas.SMOKE, "thick smoke hangs")
	assert_false(SimLos.has_line_of_sight(state.grid, Vector3i(5, Y, 2), Vector3i(5, Y, 8)))
	var thin := Vector3i(2, Y, 9)
	state.grid.add_gas(thin, SimMaterials.Gas.SMOKE, 10)
	GasRules.step(state)
	assert_eq(_gas(state, thin + Vector3i.UP), SimMaterials.Gas.SMOKE, "thin smoke rises")


func test_standing_in_smoke_hides_you() -> void:
	var state := _duel()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(8, Y, 2))
	state.grid.add_gas(bandit.cell, SimMaterials.Gas.SMOKE, 80)
	assert_false(SimLos.has_line_of_sight(state.grid, Vector3i(2, Y, 2), bandit.cell))


# --- Psychic: Dread -----------------------------------------------------------------

func test_dread_drops_the_shield_and_runs_on_its_turn() -> void:
	var state := _duel()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(4, Y, 2))
	EquipRules.put(bandit, EquipRules.OFF, "Wooden shield")
	assert_true(state.apply_command(CastCommand.new(1, A.DREAD, bandit.cell)))
	assert_eq(EquipRules.worn(bandit, EquipRules.OFF), "")
	assert_true(bandit.inventory.has("Wooden shield"))
	CombatRules.end_side_turn(state)
	assert_eq(state.combat.side, ENEMIES)
	assert_gt(bandit.cell.x, 4 + 2, "ran away from the caster")
	assert_eq(bandit.ap, 0, "and did nothing else")
	CombatRules.end_side_turn(state)
	CombatRules.end_side_turn(state)
	assert_gt(bandit.ap, 0, "over by its turn after")


func test_dread_outside_combat_runs_at_once() -> void:
	var state := Fixtures.flat_state(Vector3i(14, 5, 14))
	var hero := state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(2, Y, 2), 20, "", 0, [], [A.DREAD]))
	hero.schools = StatRules.schools_for(hero.abilities)
	var bandit := state.add_entity(SimEntity.character("Bandit", ENEMIES, Vector3i(4, Y, 2), 12))
	assert_true(state.apply_command(CastCommand.new(hero.id, A.DREAD, bandit.cell)))
	assert_eq(bandit.cell.x, 4 + SimAbilities.FLEE_CELLS)


# --- Warrior: Brace -----------------------------------------------------------------

func test_brace_needs_a_shield_and_holds_against_a_shove() -> void:
	var state := _duel()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	Fixtures.teach(bandit, [A.SHOVE])
	assert_false(CastCommand.new(1, A.BRACE, hero.cell).validate(state), "no shield")
	EquipRules.put(hero, EquipRules.MAIN, "Fine sword")
	EquipRules.put(hero, EquipRules.OFF, "Wooden shield")
	assert_true(state.apply_command(CastCommand.new(1, A.BRACE, hero.cell)))
	CombatRules.end_side_turn(state)
	assert_true(state.apply_command(CastCommand.new(bandit.id, A.SHOVE, hero.cell)))
	assert_eq(hero.cell, Vector3i(2, Y, 2), "it held")
	var hp := hero.hp
	EntityOps.damage(state, hero, 8, bandit.id)
	assert_eq(hp - hero.hp, 8 - hero.armor - SimAbilities.BRACE_ARMOR)
	CombatRules.end_side_turn(state)
	assert_eq(hero.braced, 0, "over at its next turn")


# --- Ranger: Snare ------------------------------------------------------------------

func test_snare_catches_the_first_enemy_to_step_in() -> void:
	var state := _duel()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	var trap := Vector3i(3, Y, 2)
	EntityOps.place(state, bandit, Vector3i(6, Y, 2))
	assert_true(state.apply_command(CastCommand.new(1, A.SNARE, trap)))
	assert_true(state.snares.has(trap))
	hero.cooldowns.fill(0)
	assert_false(CastCommand.new(1, A.SNARE, trap).validate(state), "one per cell")
	CombatRules.end_side_turn(state)
	state.drain_events()
	assert_true(state.apply_command(MoveCommand.new(bandit.id, Vector3i(2, Y, 3))))
	assert_eq(bandit.cell, trap, "stopped in the trap")
	assert_false(state.snares.has(trap), "sprung")
	assert_true(bandit.knocked_down, "3 stagger knocks a plain bandit down")
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.SNARED).size(), 1)


func test_snare_ignores_the_setters_side() -> void:
	var state := _duel()
	var hero := Fixtures.hero(state)
	var trap := Vector3i(3, Y, 2)
	state.apply_command(CastCommand.new(1, A.SNARE, trap))
	assert_true(state.apply_command(MoveCommand.new(hero.id, Vector3i(4, Y, 2))))
	assert_eq(hero.cell, Vector3i(4, Y, 2))
	assert_true(state.snares.has(trap))


func test_snare_outside_combat_starts_the_fight() -> void:
	var state := Fixtures.flat_state(Vector3i(14, 5, 14))
	var hero := state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(2, Y, 2), 20, "", 0, [], [A.SNARE]))
	hero.schools = StatRules.schools_for(hero.abilities)
	var bandit := state.add_entity(SimEntity.character("Bandit", ENEMIES, Vector3i(6, Y, 2), 12))
	assert_true(state.apply_command(CastCommand.new(hero.id, A.SNARE, Vector3i(3, Y, 2))))
	bandit.travel.assign([Vector3i(5, Y, 2), Vector3i(4, Y, 2), Vector3i(3, Y, 2), Vector3i(2, Y, 3)])
	state.step_ticks(4)
	assert_eq(bandit.cell, Vector3i(3, Y, 2))
	assert_true(state.combat.active)


# --- Saves --------------------------------------------------------------------------

func test_snares_and_new_statuses_survive_a_snapshot() -> void:
	var state := _duel()
	var bandit := Fixtures.bandit(state)
	state.snares[Vector3i(3, Y, 2)] = 1
	bandit.dread = 2
	bandit.dread_from = Vector3i(2, Y, 2)
	bandit.braced = 1
	var copy := SimState.from_snapshot(state.to_snapshot())
	assert_eq(copy.snares, state.snares)
	assert_eq(copy.get_entity(2).dread, 2)
	assert_eq(copy.get_entity(2).dread_from, Vector3i(2, Y, 2))
	assert_eq(copy.get_entity(2).braced, 1)
	assert_eq(copy.checksum(), state.checksum())


# --- Tomes and loot ---------------------------------------------------------------

func test_every_later_skill_has_a_tome() -> void:
	for ability: int in LATER:
		var tome := "%s tome" % SimAbilities.NAMES[ability]
		assert_eq(SimItems.teaches(tome), ability, tome)


func test_a_new_tome_teaches_with_enough_rank() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 5, 12))
	var e := state.add_entity(SimArchetypes.make("vanguard", "Ari", PLAYERS, Vector3i(2, Y, 2), ["Brace tome"] as Array[String]))
	assert_true(state.apply_command(UseItemCommand.new(e.id, 0)), "the Vanguard has Warrior 2")
	assert_true(e.abilities.has(A.BRACE))


func test_loot_tables_name_real_items_and_cover_every_tome() -> void:
	for table: String in LootTables.TABLES:
		for item in LootTables.items_of(table):
			assert_true(SimItems.ITEMS.has(item), "%s: %s" % [table, item])
		for entry: String in LootTables.TABLES[table]:
			if entry.begins_with("@"):
				assert_true(LootTables.has_table(entry.substr(1)), "%s: %s" % [table, entry])
	var tomes := LootTables.items_of("tomes")
	for item: String in SimItems.ITEMS:
		if SimItems.teaches(item) >= 0:
			assert_true(tomes.has(item), "%s can be found" % item)


func test_loot_rolls_are_seeded() -> void:
	var a := LootTables.roll(SimRng.new(42), "cache", 6)
	var b := LootTables.roll(SimRng.new(42), "cache", 6)
	assert_eq(a, b, "same seed, same loot")
	assert_eq(a.size(), 6, "a cache never rolls nothing")
	var rng := SimRng.new(7)
	var seen := {}
	for _i in 200:
		for item in LootTables.roll(rng, "tomes"):
			seen[item] = true
	assert_gt(seen.size(), 10, "all sorts of tomes turn up")
	assert_eq(LootTables.roll(SimRng.new(1), "no such table", 3), [] as Array[String])
