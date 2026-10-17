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


func test_standing_in_fire_burns() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	state.apply_command(IgniteCommand.new(hero.cell))
	state.step_ticks(3)
	assert_eq(hero.hp, hero.max_hp - 3 * EntityOps.FIRE_DAMAGE_PER_TICK)


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
