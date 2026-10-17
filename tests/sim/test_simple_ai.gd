extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y


func _enemy_turn(state: SimState) -> void:
	state.apply_command(EndTurnCommand.new(Fixtures.PLAYERS))
	var guard := 0
	while state.combat.active and state.combat.side == Fixtures.ENEMIES and guard < 50:
		assert_true(state.apply_command(SimpleAi.next_command(state)))
		guard += 1


func test_enemy_walks_toward_player() -> void:
	var state := Fixtures.duel_state()
	var before := SimPathfinder.distance(Fixtures.bandit(state).cell, Fixtures.hero(state).cell)
	_enemy_turn(state)
	var after := SimPathfinder.distance(Fixtures.bandit(state).cell, Fixtures.hero(state).cell)
	assert_lt(after, before)
	assert_eq(state.combat.side, Fixtures.PLAYERS)


func test_adjacent_enemy_attacks() -> void:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(3, Y, 3))
	_enemy_turn(state)
	assert_eq(Fixtures.hero(state).hp, 20 - 2 * 3, "4 AP = two club hits")


func test_ai_ends_turn_when_nothing_to_do() -> void:
	var state := Fixtures.duel_state()
	state.apply_command(EndTurnCommand.new(Fixtures.PLAYERS))
	Fixtures.bandit(state).ap = 0
	assert_true(SimpleAi.next_command(state) is EndTurnCommand)
