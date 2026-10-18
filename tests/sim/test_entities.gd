extends GutTest

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const OIL := SimMaterials.Surface.OIL


func test_add_entity_settles_onto_ground() -> void:
	var state := Fixtures.flat_state()
	var e := state.add_entity(SimEntity.barrel("Barrel", Vector3i(3, 3, 3), OIL, 50))
	assert_eq(e.cell, Vector3i(3, Y, 3))
	assert_eq(e.id, 1)


func test_damage_kills_and_dead_entities_free_their_cell() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	EntityOps.damage(state, bandit, 100)
	assert_false(bandit.is_alive())
	assert_null(state.entity_at(bandit.cell))
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.DIED).size(), 1)


func test_destroyed_barrel_spills_contents() -> void:
	var state := Fixtures.flat_state()
	var barrel := state.add_entity(SimEntity.barrel("Oil barrel", Vector3i(4, Y, 4), OIL, 100))
	EntityOps.damage(state, barrel, 10)
	assert_eq(state.grid.total_surface(OIL), 100)
	assert_eq(state.grid.surface_type[state.grid.index(Vector3i(5, Y, 4))], OIL)


func test_fire_under_a_character_burns_at_once() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	state.apply_command(IgniteCommand.new(hero.cell))
	assert_eq(hero.hp, hero.max_hp - EntityOps.BURN_DAMAGE, "an instance of damage right away")
	assert_eq(hero.burning, EntityOps.BURN_TURNS)
	state.step_ticks(3)
	assert_eq(hero.hp, hero.max_hp - EntityOps.BURN_DAMAGE, "standing in it keeps the burn going without extra hits")
	assert_eq(hero.burning, EntityOps.BURN_TURNS)


func test_burning_hurts_at_each_turn_start_for_its_turns() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	hero.burning = EntityOps.BURN_TURNS
	for _i in EntityOps.BURN_TURNS + 2:
		state.apply_command(EndTurnCommand.new(SimEntity.Faction.PLAYERS))
		state.apply_command(EndTurnCommand.new(SimEntity.Faction.ENEMIES))
	assert_eq(hero.hp, hero.max_hp - EntityOps.BURN_TURNS * EntityOps.BURN_DAMAGE)
	assert_eq(hero.burning, 0)


func test_each_burning_cell_walked_over_hurts() -> void:
	var state := Fixtures.flat_state(Vector3i(10, 4, 3))
	var walker := state.add_entity(SimEntity.character("Walker", SimEntity.Faction.PLAYERS, Vector3i(0, Y, 1), 20))
	state.apply_command(StartCombatCommand.new())
	for z in 3:
		for x in [3, 4]:
			state.grid.set_fire(state.grid.index(Vector3i(x, Y, z)), SimMaterials.FIRE_MAX)
	assert_true(state.apply_command(MoveCommand.new(walker.id, Vector3i(6, Y, 1))))
	assert_eq(walker.hp, 20 - 2 * EntityOps.BURN_DAMAGE, "two burning cells, two hits")


func test_fire_spreading_under_someone_sets_them_alight() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	state.grid.add_surface(hero.cell, OIL, 20)
	state.grid.add_surface(hero.cell + Vector3i(1, 0, 0), OIL, 20)
	state.grid.set_fire(state.grid.index(hero.cell + Vector3i(1, 0, 0)), SimMaterials.FIRE_MAX)
	state.step()
	assert_eq(hero.burning, EntityOps.BURN_TURNS)
	assert_eq(hero.hp, hero.max_hp - EntityOps.BURN_DAMAGE)


func test_water_puts_out_burning() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	hero.burning = EntityOps.BURN_TURNS
	state.grid.add_surface(hero.cell + Vector3i(0, 0, 1), SimMaterials.Surface.WATER, 20)
	assert_true(state.apply_command(MoveCommand.new(hero.id, hero.cell + Vector3i(0, 0, 1))))
	assert_eq(hero.burning, 0)


func test_burning_oil_barrel_chain_reaction() -> void:
	var state := Fixtures.flat_state()
	state.add_entity(SimEntity.barrel("Oil barrel", Vector3i(4, Y, 4), OIL, 100))
	state.apply_command(IgniteCommand.new(Vector3i(4, Y, 4)))
	state.step_ticks(6)
	var burning := 0
	for n: Vector3i in SimGrid.NEIGHBORS_4:
		if state.grid.fire[state.grid.index(Vector3i(4, Y, 4) + n)] > 0:
			burning += 1
	assert_gt(burning, 0, "spilled oil should catch fire around the barrel")


func test_falling_damage_scales_with_height() -> void:
	var state := Fixtures.flat_state(Vector3i(9, 6, 9))
	var e := state.add_entity(SimEntity.character("Faller", SimEntity.Faction.PLAYERS, Vector3i(1, Y, 1), 20))
	EntityOps.place(state, e, Vector3i(1, Y + 3, 1))
	assert_eq(e.cell, Vector3i(1, Y, 1))
	assert_eq(e.hp, 20 - 2 * EntityOps.FALL_DAMAGE_PER_LEVEL)


func test_entity_round_trips_through_dict() -> void:
	var e := SimEntity.character("Cel", SimEntity.Faction.PLAYERS, Vector3i(1, 2, 3), 16, "Dagger", 3, ["Key"])
	assert_eq(SimEntity.from_dict(e.to_dict()).to_dict(), e.to_dict())


func test_burn_damage_is_fire_and_follows_turn_start() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	hero.burning = EntityOps.BURN_TURNS
	state.apply_command(EndTurnCommand.new(SimEntity.Faction.PLAYERS))
	state.drain_events()
	state.apply_command(EndTurnCommand.new(SimEntity.Faction.ENEMIES))
	var events := state.drain_events()
	var turn_index := -1
	var burn_index := -1
	for i in events.size():
		if events[i].type == SimEvent.Type.TURN_STARTED:
			turn_index = i
		if events[i].type == SimEvent.Type.DAMAGED and events[i].entity_id == hero.id:
			burn_index = i
			assert_eq(events[i].element, EntityOps.Element.FIRE)
	assert_gt(burn_index, turn_index, "shown with the new turn")
	assert_gt(turn_index, -1)
