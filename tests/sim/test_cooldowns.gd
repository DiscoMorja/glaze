extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


func _near_duel() -> SimState:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(5, Y, 2))
	return state


func _next_round(state: SimState) -> void:
	state.apply_command(EndTurnCommand.new(PLAYERS))
	state.apply_command(EndTurnCommand.new(ENEMIES))


func test_using_an_ability_starts_its_cooldown() -> void:
	var state := _near_duel()
	assert_true(state.apply_command(CastCommand.new(1, A.FIREBOLT, Fixtures.bandit(state).cell)))
	assert_eq(Fixtures.hero(state).cooldown(A.FIREBOLT), SimAbilities.COOLDOWN[A.FIREBOLT])
	assert_false(state.apply_command(CastCommand.new(1, A.FIREBOLT, Fixtures.bandit(state).cell)), "once per turn")


func test_cooldown_counts_down_on_own_turns() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	hero.hp = 5
	assert_true(state.apply_command(CastCommand.new(1, A.MEND, hero.cell)))
	for turn in SimAbilities.COOLDOWN[A.MEND] - 1:
		_next_round(state)
		assert_false(state.apply_command(CastCommand.new(1, A.MEND, hero.cell)), "still cooling down after %d turns" % (turn + 1))
	_next_round(state)
	assert_true(state.apply_command(CastCommand.new(1, A.MEND, hero.cell)))


func test_cooldowns_only_tick_on_the_owners_turn() -> void:
	var state := _near_duel()
	var hero := Fixtures.hero(state)
	assert_true(state.apply_command(CastCommand.new(1, A.TELEPORT, Fixtures.bandit(state).cell, Vector3i(5, Y, 6))))
	state.apply_command(EndTurnCommand.new(PLAYERS))
	assert_eq(hero.cooldown(A.TELEPORT), SimAbilities.COOLDOWN[A.TELEPORT], "enemy turn doesn't count")
	state.apply_command(EndTurnCommand.new(ENEMIES))
	assert_eq(hero.cooldown(A.TELEPORT), SimAbilities.COOLDOWN[A.TELEPORT] - 1)


func test_attack_has_no_cooldown() -> void:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(3, Y, 2))
	assert_true(state.apply_command(AttackCommand.new(1, 2)))
	assert_true(state.apply_command(AttackCommand.new(1, 2)))


func test_cooldowns_count_down_in_real_time_outside_combat() -> void:
	var state := Fixtures.flat_state()
	var e := state.add_entity(SimEntity.character("Walker", PLAYERS, Vector3i(1, Y, 1), 10, "", 0, [], [A.OIL_FLASK]))
	assert_true(state.apply_command(CastCommand.new(e.id, A.OIL_FLASK, Vector3i(3, Y, 3))))
	assert_false(state.apply_command(CastCommand.new(e.id, A.OIL_FLASK, Vector3i(5, Y, 5))), "cooling down")
	state.step_ticks(SimAbilities.COOLDOWN[A.OIL_FLASK] * CombatRules.REALTIME_TICKS_PER_TURN)
	assert_true(state.apply_command(CastCommand.new(e.id, A.OIL_FLASK, Vector3i(5, Y, 5))))


func test_cooldowns_survive_copies() -> void:
	var state := _near_duel()
	state.apply_command(CastCommand.new(1, A.FIREBOLT, Fixtures.bandit(state).cell))
	var copy := state.duplicate_state()
	assert_eq(copy.get_entity(1).cooldown(A.FIREBOLT), SimAbilities.COOLDOWN[A.FIREBOLT])
	assert_eq(copy.checksum(), state.checksum())


func test_every_ability_has_a_cooldown_entry() -> void:
	assert_eq(SimAbilities.COOLDOWN.size(), SimAbilities.NAMES.size())


func test_healer_and_caster_duel_ends() -> void:
	# The reported stalemate: a healer that mends every turn out-heals a caster.
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var shaman := Fixtures.bandit(state)
	hero.abilities.assign([A.FIREBOLT])
	shaman.abilities.assign([A.MEND, A.FIREBOLT])
	EntityOps.place(state, shaman, Vector3i(7, Y, 2))
	var rounds := 0
	while state.combat.active and rounds < 20:
		state.apply_command(CastCommand.new(1, A.FIREBOLT, shaman.cell))
		state.apply_command(EndTurnCommand.new(PLAYERS))
		var guard := 0
		while state.combat.active and state.combat.side == ENEMIES and guard < 20:
			state.apply_command(UtilityAi.next_command(state))
			guard += 1
		rounds += 1
	assert_false(state.combat.active, "someone wins within 20 rounds")
