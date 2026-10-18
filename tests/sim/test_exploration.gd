extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


## A 20x5x12 field with a hero at (1, 1, 5) and a watchful bandit at (18, 1, 5), not in combat.
func _field(bandit_sight: int = 6) -> SimState:
	var state := Fixtures.flat_state(Vector3i(20, 5, 12))
	state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(1, Y, 5), 20, "Sword", 4, [], SimAbilities.all()))
	var bandit := state.add_entity(SimEntity.character("Bandit", ENEMIES, Vector3i(18, Y, 5), 12, "Club", 3))
	bandit.sight = bandit_sight
	bandit.facing = 6  # looking west, toward the hero
	bandit.home_facing = 6
	state.drain_events()
	return state


func test_travel_walks_one_cell_per_tick() -> void:
	var state := _field()
	var hero := Fixtures.hero(state)
	assert_true(state.apply_command(TravelCommand.new(1, Vector3i(5, Y, 5))))
	assert_eq(hero.cell, Vector3i(1, Y, 5), "nothing moves until the world ticks")
	state.step()
	assert_eq(hero.cell, Vector3i(2, Y, 5))
	state.step_ticks(3)
	assert_eq(hero.cell, Vector3i(5, Y, 5))
	assert_true(hero.travel.is_empty())


func test_travel_is_not_allowed_in_combat() -> void:
	var state := Fixtures.duel_state()
	assert_false(state.apply_command(TravelCommand.new(1, Vector3i(4, Y, 2))))


func test_travel_goes_around_someone_in_the_way() -> void:
	var state := _field(0)
	var hero := Fixtures.hero(state)
	state.apply_command(TravelCommand.new(1, Vector3i(6, Y, 5)))
	state.add_entity(SimEntity.barrel("Barrel", Vector3i(3, Y, 5), SimMaterials.Surface.NONE, 0))
	state.step_ticks(8)
	assert_eq(hero.cell, Vector3i(6, Y, 5))


func test_ice_doesnt_stop_a_walk_outside_combat() -> void:
	var state := _field(0)
	var hero := Fixtures.hero(state)
	# A strip of ice across the whole field, so the route has to cross it.
	for z in 12:
		state.grid.add_surface(Vector3i(3, Y, z), SimMaterials.Surface.ICE, 20)
	state.grid.fill_temperature(SimMaterials.CHILL_TEMPERATURE)
	state.apply_command(TravelCommand.new(1, Vector3i(6, Y, 5)))
	state.step_ticks(5)
	assert_eq(hero.cell, Vector3i(6, Y, 5), "stagger only counts in a fight")


func test_walking_into_sight_starts_combat() -> void:
	var state := _field()
	state.apply_command(TravelCommand.new(1, Vector3i(14, Y, 5)))
	var guard := 0
	while not state.combat.active and guard < 20:
		state.step()
		guard += 1
	assert_true(state.combat.active)
	assert_true(SimAbilities.in_range(Fixtures.hero(state).cell, Fixtures.bandit(state).cell, 6))
	assert_true(Fixtures.hero(state).travel.is_empty(), "combat stops everyone where they stand")
	var spotted := Fixtures.events_of_type(state.drain_events(), SimEvent.Type.SPOTTED)
	assert_eq(spotted.size(), 1)


func test_walls_block_sight() -> void:
	var state := _field()
	state.grid.fill_solid(Vector3i(14, Y, 0), Vector3i(14, Y + 3, 11))
	EntityOps.place(state, Fixtures.hero(state), Vector3i(13, Y, 5))
	state.step()
	assert_false(state.combat.active)


func test_hurting_an_enemy_starts_combat() -> void:
	var state := _field(0)
	EntityOps.place(state, Fixtures.hero(state), Vector3i(13, Y, 5))
	assert_true(state.apply_command(CastCommand.new(1, SimAbilities.Ability.FIREBOLT, Fixtures.bandit(state).cell)))
	assert_true(state.combat.active)


func test_preparing_the_ground_does_not_start_combat() -> void:
	var state := _field(0)
	EntityOps.place(state, Fixtures.hero(state), Vector3i(13, Y, 5))
	Fixtures.give_flasks(Fixtures.hero(state))
	assert_true(state.apply_command(CastCommand.new(1, SimAbilities.Ability.OIL_FLASK, Vector3i(16, Y, 5))))
	assert_false(state.combat.active)


func test_exploration_is_deterministic() -> void:
	var a := _field()
	var b := _field()
	for s in [a, b]:
		s.apply_command(TravelCommand.new(1, Vector3i(10, Y, 8)))
		s.step_ticks(12)
	assert_eq(a.checksum(), b.checksum())


func test_back_to_real_time_after_a_win() -> void:
	var state := _field(0)
	EntityOps.place(state, Fixtures.hero(state), Vector3i(13, Y, 5))
	state.apply_command(CastCommand.new(1, SimAbilities.Ability.FIREBOLT, Fixtures.bandit(state).cell))
	assert_true(state.combat.active)
	EntityOps.damage(state, Fixtures.bandit(state), 100)
	CombatRules.check_end(state)
	assert_false(state.combat.active)
	assert_true(state.apply_command(TravelCommand.new(1, Vector3i(2, Y, 2))), "walking works again")
	state.step()
	assert_false(state.combat.active, "a dead bandit doesn't restart the fight")


func test_travel_is_limited_in_distance() -> void:
	var state := Fixtures.flat_state(Vector3i(60, 5, 6))
	state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(1, Y, 2), 20))
	var far := Vector3i(1 + TravelCommand.MAX_DISTANCE + 1, Y, 2)
	assert_false(state.apply_command(TravelCommand.new(1, far)), "too far for one order")
	assert_true(state.apply_command(TravelCommand.new(1, far - Vector3i(1, 0, 0))), "just within reach")


func test_route_search_gives_up_on_a_walled_off_goal() -> void:
	var state := _field(0)
	# A box around (10, Y, 5): reachable by nobody.
	state.grid.fill_solid(Vector3i(9, Y, 4), Vector3i(11, Y + 3, 6))
	state.grid.fill_solid(Vector3i(10, Y, 5), Vector3i(10, Y + 3, 5), false)
	assert_eq(SimPathfinder.find_path(state, Fixtures.hero(state).cell, Vector3i(10, Y, 5), 1, false, true, 50).size(), 0)


func test_slowed_walks_at_half_speed() -> void:
	var state := _field(0)
	var hero := Fixtures.hero(state)
	hero.slowed = 99
	state.apply_command(TravelCommand.new(1, Vector3i(9, Y, 5)))
	state.step_ticks(8)
	assert_eq(hero.cell, Vector3i(5, Y, 5), "four cells in eight ticks")


func test_a_travel_command_carries_its_route_and_replays_without_searching() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 4, 12))
	var hero := state.add_entity(SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(1, Fixtures.FLOOR_Y, 1), 20))
	var command := TravelCommand.new(hero.id, Vector3i(8, Fixtures.FLOOR_Y, 6))
	assert_true(command.validate(state))
	var data := command.to_dict()
	assert_true(data.has("route"), "the route found goes with the command")
	var replica := SimState.from_snapshot(state.to_snapshot())
	var replayed := SimCommandRegistry.from_dict(data) as TravelCommand
	assert_true(replayed.validate(replica))
	assert_eq(replayed.route(replica), command.route(state))


func test_a_bad_carried_route_is_searched_again() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 4, 12))
	var hero := state.add_entity(SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(1, Fixtures.FLOOR_Y, 1), 20))
	var to := Vector3i(8, Fixtures.FLOOR_Y, 1)
	var data := {"type": TravelCommand.TYPE, "entity_id": hero.id, "destination": to,
			"route": [Vector3i(5, Fixtures.FLOOR_Y, 1), to]}  # jumps cells: not a walk
	var command := SimCommandRegistry.from_dict(data) as TravelCommand
	assert_true(command.validate(state))
	assert_eq(command.route(state).size(), 7, "a proper path instead")


func test_a_route_found_elsewhere_is_used_as_is() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 4, 12))
	var hero := state.add_entity(SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(1, Fixtures.FLOOR_Y, 1), 20))
	var to := Vector3i(8, Fixtures.FLOOR_Y, 1)
	var route: Array[Vector3i] = []
	for x in range(2, 9):
		route.append(Vector3i(x, Fixtures.FLOOR_Y, 1))
	var command := TravelCommand.new(hero.id, to)
	command.set_route(route)
	assert_true(command.validate(state))
	assert_eq(command.route(state), route)


func test_a_walker_that_moved_on_picks_the_route_up_where_it_stands() -> void:
	var state := Fixtures.flat_state(Vector3i(12, 4, 12))
	var y := Fixtures.FLOOR_Y
	var hero := state.add_entity(SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(1, y, 1), 20))
	var to := Vector3i(8, y, 1)
	var route: Array[Vector3i] = []
	for x in range(2, 9):
		route.append(Vector3i(x, y, 1))
	# The route was searched from (1, y, 1); meanwhile it stepped to (2, y, 2).
	EntityOps.place(state, hero, Vector3i(2, y, 2))
	var command := TravelCommand.new(hero.id, to)
	command.set_route(route)
	assert_true(command.validate(state))
	assert_eq(command.route(state)[0], Vector3i(3, y, 1), "joins at the farthest neighbour")
	assert_eq(command.route(state).back(), to)
