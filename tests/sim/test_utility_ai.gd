extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


## Runs the enemy side until it ends its turn; returns the commands it chose.
func _enemy_turn(state: SimState) -> Array[SimCommand]:
	if state.combat.side == PLAYERS:
		state.apply_command(EndTurnCommand.new(PLAYERS))
	var chosen: Array[SimCommand] = []
	var guard := 0
	while state.combat.active and state.combat.side == ENEMIES and guard < 30:
		var command := UtilityAi.next_command(state)
		chosen.append(command)
		assert_true(state.apply_command(command), "AI command must be valid: %s" % command.to_dict())
		guard += 1
	return chosen


func _has_cast(commands: Array[SimCommand], ability: int) -> bool:
	for c in commands:
		if c is CastCommand and (c as CastCommand).ability == ability:
			return true
	return false


func test_enemy_closes_distance() -> void:
	var state := Fixtures.duel_state()
	var before := SimPathfinder.distance(Fixtures.bandit(state).cell, Fixtures.hero(state).cell)
	_enemy_turn(state)
	assert_lt(SimPathfinder.distance(Fixtures.bandit(state).cell, Fixtures.hero(state).cell), before)
	assert_eq(state.combat.side, PLAYERS, "turn ends on its own")


func test_adjacent_enemy_attacks_twice() -> void:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(3, Y, 3))
	_enemy_turn(state)
	assert_eq(Fixtures.hero(state).hp, 20 - 2 * 3)


func test_enemy_ends_turn_with_nothing_useful() -> void:
	var state := Fixtures.duel_state()
	state.apply_command(EndTurnCommand.new(PLAYERS))
	Fixtures.bandit(state).ap = 0
	assert_true(UtilityAi.next_command(state) is EndTurnCommand)


func test_mage_ignites_oil_under_players() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	Fixtures.teach(bandit, [A.FIREBOLT])
	EntityOps.place(state, bandit, Vector3i(7, Y, 2))
	# A puddle of oil around the hero but not on its own cell.
	for n: Vector3i in SimGrid.NEIGHBORS_4:
		state.grid.add_surface(hero.cell + n, SimMaterials.Surface.OIL, 30)
	var chosen := _enemy_turn(state)
	assert_true(_has_cast(chosen, A.FIREBOLT))
	assert_lt(hero.hp, 20)


func test_ai_will_not_burn_its_own_side() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var mage := Fixtures.bandit(state)
	Fixtures.teach(mage, [A.FIREBOLT])
	EntityOps.place(state, mage, Vector3i(9, Y, 2))
	# A second enemy stands next to the hero in a shared oil pool.
	var ally := state.add_entity(SimEntity.character("Grunt", ENEMIES, Vector3i(3, Y, 2), 30, "Club", 3))
	state.grid.add_surface(hero.cell, SimMaterials.Surface.OIL, 40)
	state.grid.add_surface(ally.cell, SimMaterials.Surface.OIL, 40)
	state.apply_command(EndTurnCommand.new(PLAYERS))
	var command := UtilityAi.next_command(state)
	assert_false(command is CastCommand and (command as CastCommand).ability == A.FIREBOLT,
			"burning the shared pool hurts the grunt more than it is worth")


func test_enemy_steps_out_of_fire() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	state.apply_command(EndTurnCommand.new(PLAYERS))
	state.grid.set_fire(state.grid.index(bandit.cell), SimMaterials.FIRE_MAX)
	var start := bandit.cell
	var command := UtilityAi.next_command(state)
	assert_true(command is MoveCommand)
	state.apply_command(command)
	assert_ne(bandit.cell, start)
	assert_eq(state.grid.fire[state.grid.index(bandit.cell)], 0)


func test_thief_takes_items_but_never_player_weapons() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	hero.can_be_disarmed = false
	hero.inventory.assign(["Gold"])
	Fixtures.teach(bandit, [A.STEAL])
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	var chosen := _enemy_turn(state)
	assert_true(_has_cast(chosen, A.STEAL))
	assert_eq(hero.weapon, "Sword")
	assert_true(bandit.inventory.has("Gold"))


func test_healer_mends_hurt_ally() -> void:
	var state := Fixtures.duel_state()
	var shaman := Fixtures.bandit(state)
	Fixtures.teach(shaman, [A.MEND])
	var grunt := state.add_entity(SimEntity.character("Grunt", ENEMIES, Vector3i(9, Y, 7), 20, "Club", 3))
	grunt.hp = 8
	var chosen := _enemy_turn(state)
	assert_true(_has_cast(chosen, A.MEND))
	assert_gt(grunt.hp, 8)


func test_ai_is_deterministic() -> void:
	var a := Fixtures.duel_state()
	var b := Fixtures.duel_state()
	Fixtures.teach(Fixtures.bandit(a), [A.FIREBOLT, A.SHOVE])
	Fixtures.teach(Fixtures.bandit(b), [A.FIREBOLT, A.SHOVE])
	_enemy_turn(a)
	_enemy_turn(b)
	assert_eq(a.checksum(), b.checksum())


func test_melee_takes_the_stairs_instead_of_the_cliff_edge() -> void:
	# A plateau two levels high (top floor y = 3) over x 0..5, with one stair
	# block at (6, 1, 4) as the only way down. The hero waits below the cliff.
	var state := Fixtures.flat_state(Vector3i(12, 6, 6))
	state.grid.fill_solid(Vector3i(0, Y, 0), Vector3i(5, Y + 1, 5))
	state.grid.fill_solid(Vector3i(6, Y, 4), Vector3i(6, Y, 4))
	var hero := state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(7, Y, 0), 20, "Sword", 4))
	var bandit := state.add_entity(SimEntity.character("Bandit", ENEMIES, Vector3i(2, Y + 2, 0), 12, "Club", 3))
	state.apply_command(StartCombatCommand.new())
	assert_eq(SimPathfinder.find_path(state, bandit.cell, Vector3i(5, Y + 2, 0), bandit.id).size() > 0, true, "the edge above the hero is walkable")
	_enemy_turn(state)
	assert_true(bandit.cell.z >= 3 or bandit.cell.y == Y, "heads for the stair, not the edge above the hero (at %s)" % bandit.cell)
	assert_eq(hero.hp, 20)


## A melee bandit at (6, 1, 3) with a firecaller (ranged) at (6, 1, 1), in a
## 16x5x18 field, and a hero at `hero_at`.
func _guard_field(hero_at: Vector3i) -> SimState:
	var state := Fixtures.flat_state(Vector3i(16, 5, 18))
	state.add_entity(SimEntity.character("Hero", PLAYERS, hero_at, 20, "Sword", 4))
	state.add_entity(SimEntity.character("Bandit", ENEMIES, Vector3i(6, Y, 3), 12, "Club", 3))
	state.add_entity(SimEntity.character("Caster", ENEMIES, Vector3i(6, Y, 1), 12, "Staff", 2, [], [A.FIREBOLT]))
	state.apply_command(StartCombatCommand.new())
	return state


func test_melee_prefers_staying_near_its_caster_over_advancing_alone() -> void:
	var state := _guard_field(Vector3i(6, Y, 17))
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, bandit, Vector3i(6, Y, 4))
	var near_caster := UtilityAi._position_value(state, bandit)
	EntityOps.place(state, bandit, Vector3i(6, Y, 12))
	var alone := UtilityAi._position_value(state, bandit)
	assert_gt(near_caster, alone, "8 cells closer to the hero isn't worth leaving the caster")


func test_melee_leaves_its_caster_to_hit_someone_in_reach() -> void:
	var state := _guard_field(Vector3i(6, Y, 8))
	var hero := Fixtures.hero(state)
	_enemy_turn(state)
	assert_lt(hero.hp, 20, "close enough to walk up and hit this turn")
