extends GutTest
## Looting: chests, keys, bashing open, corpses, and theft from townsfolk.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES
const NEUTRAL := SimEntity.Faction.NEUTRAL
const ALL := LootCommand.ALL


## A 12x5x12 field: Cel (id 1, party) at (5, 1, 5) and a chest (id 2) with
## Gold and a Map right next to her at (6, 1, 5).
func _camp(lock: String = "") -> SimState:
	var state := Fixtures.flat_state(Vector3i(12, 5, 12))
	state.add_entity(SimArchetypes.make("trickster", "Cel", PLAYERS, Vector3i(5, Y, 5)))
	state.add_entity(SimEntity.container("Chest", Vector3i(6, Y, 5), ["Gold", "Map"] as Array[String], lock))
	state.drain_events()
	return state


func _cel(state: SimState) -> SimEntity:
	return state.get_entity(1)


func _chest(state: SimState) -> SimEntity:
	return state.get_entity(2)


func test_take_everything_from_a_chest_next_to_you() -> void:
	var state := _camp()
	assert_true(state.apply_command(LootCommand.new(1, 2, ALL)))
	assert_eq(_cel(state).inventory.slice(-2), ["Gold", "Map"])
	assert_true(_chest(state).inventory.is_empty())
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.LOOTED).size(), 2)
	assert_false(LootCommand.new(1, 2, ALL).validate(state), "nothing left")


func test_take_one_item() -> void:
	var state := _camp()
	assert_true(state.apply_command(LootCommand.new(1, 2, 1)))
	assert_true(_cel(state).inventory.has("Map"))
	assert_eq(_chest(state).inventory, ["Gold"])


func test_must_be_next_to_it_and_not_fighting() -> void:
	var state := _camp()
	EntityOps.place(state, _cel(state), Vector3i(2, Y, 2))
	assert_eq(LootCommand.blocker(state, _cel(state), _chest(state)), "Too far")
	assert_false(LootCommand.new(1, 2, ALL).validate(state))
	EntityOps.place(state, _cel(state), Vector3i(5, Y, 5))
	state.combat.active = true
	assert_false(LootCommand.new(1, 2, ALL).validate(state))


func test_a_locked_chest_needs_its_key_and_stays_open() -> void:
	var state := _camp("Camp key")
	assert_eq(LootCommand.blocker(state, _cel(state), _chest(state)), "Locked — needs Camp key")
	assert_false(LootCommand.new(1, 2, ALL).validate(state))
	_cel(state).inventory.append("Camp key")
	assert_true(state.apply_command(LootCommand.new(1, 2, 0)))
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.UNLOCKED).size(), 1)
	assert_eq(_chest(state).lock, "")
	_cel(state).inventory.erase("Camp key")
	assert_true(LootCommand.new(1, 2, ALL).validate(state), "unlocked for good")


func test_bashing_a_locked_chest_open_keeps_its_contents() -> void:
	var state := _camp("Camp key")
	EntityOps.damage(state, _chest(state), 50, 1)
	assert_false(_chest(state).is_alive())
	assert_true(LootCommand.is_container(_chest(state)), "the wreck still holds things")
	assert_eq(state.thing_at(_chest(state).cell), _chest(state))
	assert_true(state.apply_command(LootCommand.new(1, 2, ALL)))
	assert_true(_cel(state).inventory.has("Map"))


func test_corpses_can_be_looted_but_not_the_living() -> void:
	var state := _camp()
	var bandit := SimArchetypes.make("thug", "Thug", ENEMIES, Vector3i(5, Y, 6), ["Coins"] as Array[String])
	state.add_entity(bandit)
	assert_false(LootCommand.is_container(bandit), "alive")
	assert_false(LootCommand.new(1, bandit.id, ALL).validate(state))
	EntityOps.damage(state, bandit, 100, 1)
	state.combat.active = false
	assert_true(state.apply_command(LootCommand.new(1, bandit.id, ALL)))
	assert_true(_cel(state).inventory.has("Coins"))


func test_party_members_are_not_containers() -> void:
	var state := _camp()
	var ari := SimArchetypes.make("vanguard", "Ari", PLAYERS, Vector3i(4, Y, 5), ["Gold"] as Array[String])
	state.add_entity(ari)
	EntityOps.damage(state, ari, 100, -1)
	assert_false(LootCommand.is_container(ari), "fallen party members keep their things for a revive")


func test_taking_townsfolks_things_is_theft() -> void:
	var state := _camp()
	_chest(state).pack = 7
	var farmer := SimArchetypes.make("villager", "Farmer", NEUTRAL, Vector3i(5, Y, 8))
	farmer.pack = 7
	farmer.facing = 4  # south: looking away
	farmer.home_facing = 4
	state.add_entity(farmer)
	state.apply_command(LootCommand.new(1, 2, 0))
	assert_true(CrimeRules.is_stolen(_cel(state), "Gold"), "tagged as the village's")
	assert_false(farmer.suspicious, "nobody saw")
	farmer.facing = 0  # north: now facing Cel
	farmer.home_facing = 0
	state.apply_command(LootCommand.new(1, 2, 0))
	assert_true(farmer.suspicious, "seen taking the Map")


func test_the_bandits_things_are_fair_game() -> void:
	var state := _camp()
	_chest(state).pack = 3
	var thug := SimArchetypes.make("thug", "Thug", ENEMIES, Vector3i(10, Y, 10))
	thug.pack = 3
	state.add_entity(thug)
	state.apply_command(LootCommand.new(1, 2, ALL))
	assert_false(CrimeRules.is_stolen(_cel(state), "Gold"))


func test_loot_survives_snapshots_and_serialization() -> void:
	var state := _camp("Camp key")
	var copy := SimState.from_snapshot(state.to_snapshot())
	assert_eq(_chest(copy).lock, "Camp key")
	assert_eq(_chest(copy).model, "chest")
	var command := SimCommandRegistry.from_dict(LootCommand.new(1, 2, 1).to_dict()) as LootCommand
	assert_eq([command.looter_id, command.container_id, command.index], [1, 2, 1])
