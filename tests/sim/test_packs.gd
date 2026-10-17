extends GutTest
## Fights are local: whoever spots or is hurt joins with their pack; the rest
## of the world sits it out.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


## A 40x5x12 field: a hero at (1, 1, 5); pack 1 (a watchful scout at (10, 1, 5)
## plus a blind mate at (12, 1, 2)); pack 2 far off at (36, 1, 5).
func _field() -> SimState:
	var state := Fixtures.flat_state(Vector3i(40, 5, 12))
	state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(1, Y, 5), 20, "Sword", 4, [], SimAbilities.all()))
	_bandit(state, "Scout", Vector3i(10, Y, 5), 1, 6)
	_bandit(state, "Mate", Vector3i(12, Y, 2), 1, 0)
	_bandit(state, "Far", Vector3i(36, Y, 5), 2, 6)
	state.drain_events()
	return state


func _bandit(state: SimState, p_name: String, cell: Vector3i, pack: int, sight: int) -> SimEntity:
	var e := state.add_entity(SimEntity.character(p_name, ENEMIES, cell, 12, "Club", 3))
	e.pack = pack
	e.sight = sight
	return e


func _named(state: SimState, p_name: String) -> SimEntity:
	for e in state.entities:
		if e.name == p_name:
			return e
	return null


func _walk_until_combat(state: SimState, to: Vector3i) -> void:
	state.apply_command(TravelCommand.new(1, to))
	var guard := 0
	while not state.combat.active and guard < 30:
		state.step()
		guard += 1


func test_spotting_pulls_in_the_whole_pack_only() -> void:
	var state := _field()
	_walk_until_combat(state, Vector3i(8, Y, 5))
	assert_true(state.combat.active)
	assert_true(_named(state, "Scout").in_combat)
	assert_true(_named(state, "Mate").in_combat, "the blind pack mate joins with the scout")
	assert_false(_named(state, "Far").in_combat, "a pack far away sits it out")
	assert_eq(CombatRules.fighters(state, ENEMIES).size(), 2)


func test_winning_ends_the_fight_while_other_packs_live() -> void:
	var state := _field()
	_walk_until_combat(state, Vector3i(8, Y, 5))
	EntityOps.damage(state, _named(state, "Scout"), 100)
	EntityOps.damage(state, _named(state, "Mate"), 100)
	CombatRules.check_end(state)
	assert_false(state.combat.active)
	assert_true(_named(state, "Far").is_alive())
	assert_false(_named(state, "Far").in_combat)


func test_hurting_a_far_pack_mid_fight_pulls_it_in() -> void:
	var state := _field()
	_walk_until_combat(state, Vector3i(8, Y, 5))
	EntityOps.damage(state, _named(state, "Far"), 1, Fixtures.hero(state).id)
	assert_true(_named(state, "Far").in_combat)
	assert_eq(CombatRules.fighters(state, ENEMIES).size(), 3)


func test_a_pack_that_sees_the_fight_joins_next_turn() -> void:
	var state := _field()
	_walk_until_combat(state, Vector3i(8, Y, 5))
	var far := _named(state, "Far")
	assert_false(far.in_combat)
	EntityOps.place(state, far, Vector3i(7, Y, 8))
	state.apply_command(EndTurnCommand.new(PLAYERS))
	assert_true(far.in_combat, "it saw the hero at the start of the enemies' turn")
	assert_gt(far.ap, 0, "and acts this turn")


func test_provoking_one_enemy_starts_a_fight_with_its_pack() -> void:
	var state := _field()
	EntityOps.place(state, Fixtures.hero(state), Vector3i(32, Y, 7))
	_named(state, "Far").sight = 0
	assert_true(state.apply_command(CastCommand.new(1, SimAbilities.Ability.FIREBOLT, _named(state, "Far").cell)))
	assert_true(state.combat.active)
	assert_true(_named(state, "Far").in_combat)
	assert_false(_named(state, "Scout").in_combat)


func test_start_combat_command_still_fights_everyone() -> void:
	var state := _field()
	state.apply_command(StartCombatCommand.new())
	assert_eq(CombatRules.fighters(state, ENEMIES).size(), 3)


func test_self_inflicted_damage_does_not_start_a_fight() -> void:
	var state := _field()
	EntityOps.damage(state, Fixtures.hero(state), 1)
	state.step()
	assert_false(state.combat.active)
	assert_false(state.provoked)
