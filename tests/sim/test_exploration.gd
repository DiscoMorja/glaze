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


func test_slipping_on_ice_stops_the_walk() -> void:
	var state := _field(0)
	var hero := Fixtures.hero(state)
	# A strip of ice across the whole field, so the route has to cross it.
	for z in 12:
		state.grid.add_surface(Vector3i(3, Y, z), SimMaterials.Surface.ICE, 20)
	state.grid.temperature.fill(SimMaterials.CHILL_TEMPERATURE)
	state.apply_command(TravelCommand.new(1, Vector3i(6, Y, 5)))
	state.step_ticks(2)
	assert_eq(hero.cell, Vector3i(3, Y, 5))
	assert_true(hero.travel.is_empty())


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
