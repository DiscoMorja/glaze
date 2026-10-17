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
	bandit.abilities.assign([A.FIREBOLT])
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
	mage.abilities.assign([A.FIREBOLT])
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
	bandit.abilities.assign([A.STEAL])
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	var chosen := _enemy_turn(state)
	assert_true(_has_cast(chosen, A.STEAL))
	assert_eq(hero.weapon, "Sword")
	assert_true(bandit.inventory.has("Gold"))


func test_healer_mends_hurt_ally() -> void:
	var state := Fixtures.duel_state()
	var shaman := Fixtures.bandit(state)
	shaman.abilities.assign([A.MEND])
	var grunt := state.add_entity(SimEntity.character("Grunt", ENEMIES, Vector3i(9, Y, 7), 20, "Club", 3))
	grunt.hp = 8
	var chosen := _enemy_turn(state)
	assert_true(_has_cast(chosen, A.MEND))
	assert_gt(grunt.hp, 8)


func test_ai_is_deterministic() -> void:
	var a := Fixtures.duel_state()
	var b := Fixtures.duel_state()
	Fixtures.bandit(a).abilities.assign([A.FIREBOLT, A.SHOVE])
	Fixtures.bandit(b).abilities.assign([A.FIREBOLT, A.SHOVE])
	_enemy_turn(a)
	_enemy_turn(b)
	assert_eq(a.checksum(), b.checksum())
