extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


func test_combat_starts_with_players_turn() -> void:
	var state := Fixtures.duel_state()
	assert_true(state.combat.active)
	assert_eq(state.combat.side, PLAYERS)
	assert_eq(Fixtures.hero(state).ap, 4)
	assert_eq(Fixtures.bandit(state).ap, 0)


func test_cannot_act_out_of_turn() -> void:
	var state := Fixtures.duel_state()
	assert_false(state.apply_command(MoveCommand.new(2, Vector3i(8, Y, 8))))
	assert_false(state.apply_command(EndTurnCommand.new(ENEMIES)))


func test_end_turn_swaps_sides_and_advances_world() -> void:
	var state := Fixtures.duel_state()
	var tick := state.tick
	assert_true(state.apply_command(EndTurnCommand.new(PLAYERS)))
	assert_eq(state.combat.side, ENEMIES)
	assert_eq(state.tick, tick + CombatRules.TICKS_PER_SIDE_TURN)
	assert_eq(Fixtures.bandit(state).ap, 4)
	state.apply_command(EndTurnCommand.new(ENEMIES))
	assert_eq(state.combat.side, PLAYERS)
	assert_eq(state.combat.round_number, 2)


func test_unspent_ap_carries_over_up_to_cap() -> void:
	var state := Fixtures.duel_state()
	for _i in 2:
		state.apply_command(EndTurnCommand.new(PLAYERS))
		state.apply_command(EndTurnCommand.new(ENEMIES))
	assert_eq(Fixtures.hero(state).ap, CombatRules.AP_CAP)


func test_combat_ends_when_enemies_die() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, Fixtures.hero(state), bandit.cell + Vector3i(1, 0, 0))
	bandit.hp = 1
	assert_true(state.apply_command(AttackCommand.new(1, 2)))
	assert_false(state.combat.active)
	var ended := Fixtures.events_of_type(state.drain_events(), SimEvent.Type.COMBAT_ENDED)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].amount, PLAYERS)


func test_move_spends_ap_by_distance() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	assert_true(state.apply_command(MoveCommand.new(1, Vector3i(5, Y, 2))))  # 3 cells = 30 cost
	assert_eq(hero.cell, Vector3i(5, Y, 2))
	assert_eq(hero.ap, 4 - 2)


func test_move_rejected_when_too_far() -> void:
	var state := Fixtures.duel_state()
	assert_false(state.apply_command(MoveCommand.new(1, Vector3i(11, Y, 2))))  # 9 cells > 8


func test_moving_out_of_combat_is_free() -> void:
	var state := Fixtures.flat_state(Vector3i(14, 4, 4))
	var e := state.add_entity(SimEntity.character("Walker", PLAYERS, Vector3i(0, Y, 1), 10))
	assert_true(state.apply_command(MoveCommand.new(e.id, Vector3i(13, Y, 1))))
	assert_eq(e.cell, Vector3i(13, Y, 1))


func test_walking_through_fire_hurts() -> void:
	var state := Fixtures.flat_state(Vector3i(8, 4, 3))
	var e := state.add_entity(SimEntity.character("Walker", PLAYERS, Vector3i(0, Y, 1), 10))
	# Fire wall across the whole corridor so there is no way around.
	for z in 3:
		state.apply_command(IgniteCommand.new(Vector3i(3, Y, z)))
	state.apply_command(MoveCommand.new(e.id, Vector3i(6, Y, 1)))
	assert_eq(e.hp, 10 - EntityOps.FIRE_DAMAGE_PER_TICK)


func test_slipping_on_ice_ends_movement() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var ice := Vector3i(4, Y, 2)
	state.grid.add_surface(ice, SimMaterials.Surface.ICE, 30)
	# Make ice the only way forward.
	state.grid.fill_solid(Vector3i(4, Y, 0), Vector3i(4, Y + 2, 1))
	state.grid.fill_solid(Vector3i(4, Y, 3), Vector3i(4, Y + 2, 11))
	assert_true(state.apply_command(MoveCommand.new(1, Vector3i(6, Y, 2))))
	assert_eq(hero.cell, ice)
	assert_eq(hero.ap, 0)
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.SLIPPED).size(), 1)
