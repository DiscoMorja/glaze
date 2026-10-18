extends GutTest
## Perception (cones, hearing, sneaking), pickpocketing, witnesses and crime.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability
const PLAYERS := SimEntity.Faction.PLAYERS
const NEUTRAL := SimEntity.Faction.NEUTRAL
const NORTH := 0
const EAST := 2
const SOUTH := 4


## A 16x5x16 field: a thief (id 1, party) at (8, 1, 8); a merchant (id 2,
## village pack 7, carrying Coins and a Ring) at (8, 1, 9) facing south, its
## back to the thief; a guard (id 3, same pack) at (8, 1, 13) facing north.
func _village() -> SimState:
	var state := Fixtures.flat_state(Vector3i(16, 5, 16))
	var thief := SimArchetypes.make("trickster", "Cel", PLAYERS, Vector3i(8, Y, 8))
	state.add_entity(thief)
	var merchant := SimArchetypes.make("merchant", "Merchant", NEUTRAL, Vector3i(8, Y, 9), ["Coins", "Ring"] as Array[String])
	merchant.pack = 7
	_face(merchant, SOUTH)
	state.add_entity(merchant)
	var guard := SimArchetypes.make("guard", "Guard", NEUTRAL, Vector3i(8, Y, 13))
	guard.pack = 7
	_face(guard, SOUTH)  # looking away for now
	state.add_entity(guard)
	state.drain_events()
	return state


func _face(e: SimEntity, facing: int) -> void:
	e.facing = facing
	e.home_facing = facing


func _thief(state: SimState) -> SimEntity:
	return state.get_entity(1)


func _merchant(state: SimState) -> SimEntity:
	return state.get_entity(2)


func _guard(state: SimState) -> SimEntity:
	return state.get_entity(3)


# --- Perception ----------------------------------------------------------------

func test_cones_see_in_front_not_behind() -> void:
	var state := _village()
	var guard := _guard(state)
	var thief := _thief(state)
	EntityOps.place(state, thief, Vector3i(8, Y, 8))
	_face(guard, SOUTH)
	assert_false(SimPerception.can_see(state, guard, thief), "behind it, 5 cells away")
	_face(guard, NORTH)
	assert_true(SimPerception.can_see(state, guard, thief), "in front")


func test_walking_close_is_heard_from_any_side() -> void:
	var state := _village()
	var merchant := _merchant(state)
	assert_true(SimPerception.can_see(state, merchant, _thief(state)), "right behind it, not sneaking")
	_thief(state).sneaking = true
	assert_false(SimPerception.can_see(state, merchant, _thief(state)), "sneaking behind it")


func test_sneaking_shortens_the_cone() -> void:
	var state := _village()
	var guard := _guard(state)
	var thief := _thief(state)
	_face(guard, NORTH)
	thief.sneaking = true
	assert_false(SimPerception.can_see(state, guard, thief), "5 cells: beyond half of sight 7")
	EntityOps.place(state, thief, Vector3i(8, Y, 11))
	assert_true(SimPerception.can_see(state, guard, thief), "2 cells in front: seen even sneaking")


func test_walls_block_the_cone() -> void:
	var state := _village()
	var guard := _guard(state)
	_face(guard, NORTH)
	state.grid.fill_solid(Vector3i(6, Y, 11), Vector3i(10, Y + 3, 11))
	assert_false(SimPerception.can_see(state, guard, _thief(state)))


func test_idle_npcs_look_around() -> void:
	var state := _village()
	var guard := _guard(state)
	var seen := {}
	for _i in SimPerception.LOOK_TICKS * 4:
		state.step()
		seen[guard.facing] = true
	assert_gt(seen.size(), 1, "its facing changes while it stands")
	assert_true(seen.has(SOUTH))


func test_walking_turns_you_to_face_the_way() -> void:
	var state := _village()
	var thief := _thief(state)
	state.apply_command(TravelCommand.new(1, Vector3i(12, Y, 8)))
	state.step()
	assert_eq(thief.facing, EAST)


func test_sneaking_walks_at_half_speed() -> void:
	var state := _village()
	var thief := _thief(state)
	assert_true(state.apply_command(SneakCommand.new(1, true)))
	state.apply_command(TravelCommand.new(1, Vector3i(12, Y, 8)))
	state.step_ticks(4)
	assert_eq(thief.cell, Vector3i(10, Y, 8), "two cells in four ticks")


func test_combat_ends_sneaking() -> void:
	var state := _village()
	state.apply_command(SneakCommand.new(1, true))
	state.add_entity(SimEntity.character("Bandit", SimEntity.Faction.ENEMIES, Vector3i(1, Y, 1), 10))
	state.apply_command(StartCombatCommand.new())
	assert_false(_thief(state).sneaking)
	assert_false(state.apply_command(SneakCommand.new(1, true)), "no sneaking in a fight")


# --- Pickpocketing and witnesses -----------------------------------------------

func test_pickpocketing_unseen_takes_an_item_quietly() -> void:
	var state := _village()
	var thief := _thief(state)
	thief.sneaking = true
	assert_true(state.apply_command(CastCommand.new(1, A.PICKPOCKET, _merchant(state).cell)))
	assert_true(thief.inventory.has("Coins"))
	assert_true(CrimeRules.is_stolen(thief, "Coins"))
	assert_false(_merchant(state).suspicious)
	assert_eq(_merchant(state).faction, NEUTRAL)
	assert_false(state.combat.active)


func test_pickpocketing_seen_makes_witnesses_suspicious() -> void:
	var state := _village()
	assert_true(state.apply_command(CastCommand.new(1, A.PICKPOCKET, _merchant(state).cell)))
	assert_true(_merchant(state).suspicious, "heard you, right behind it")
	assert_eq(_merchant(state).faction, NEUTRAL, "a first offence: just suspicious")


func test_caught_twice_turns_the_group_hostile() -> void:
	var state := _village()
	state.apply_command(CastCommand.new(1, A.PICKPOCKET, _merchant(state).cell))
	state.apply_command(CastCommand.new(1, A.PICKPOCKET, _merchant(state).cell))
	assert_eq(_merchant(state).faction, SimEntity.Faction.ENEMIES)
	assert_eq(_guard(state).faction, SimEntity.Faction.ENEMIES, "the whole group")
	assert_true(state.combat.active, "and they fight")


func test_attacking_a_neutral_turns_its_group_hostile() -> void:
	var state := _village()
	assert_true(state.apply_command(AttackCommand.new(1, 2)))
	assert_eq(_merchant(state).faction, SimEntity.Faction.ENEMIES)
	assert_eq(_guard(state).faction, SimEntity.Faction.ENEMIES)
	assert_true(state.combat.active)


func test_suspicious_npcs_recognize_their_stolen_goods() -> void:
	var state := _village()
	var thief := _thief(state)
	thief.sneaking = true
	state.apply_command(CastCommand.new(1, A.PICKPOCKET, _merchant(state).cell))
	_guard(state).suspicious = true
	_face(_guard(state), NORTH)
	thief.sneaking = false
	state.step()
	assert_eq(_guard(state).faction, SimEntity.Faction.ENEMIES, "it saw the coins on you")


func test_pickpocket_only_outside_combat_and_not_your_own() -> void:
	var state := _village()
	var ally := SimArchetypes.make("vanguard", "Ari", PLAYERS, Vector3i(7, Y, 8), ["Bread"] as Array[String])
	ally.owner = 0
	_thief(state).owner = 0
	state.add_entity(ally)
	assert_false(state.apply_command(CastCommand.new(1, A.PICKPOCKET, ally.cell)), "your own character")
	ally.owner = 1
	assert_true(state.apply_command(CastCommand.new(1, A.PICKPOCKET, ally.cell)), "your partner's")
	assert_false(CrimeRules.is_stolen(_thief(state), "Bread"), "not a crime within the party")


# --- Inventory -------------------------------------------------------------------

func test_giving_moves_the_item_and_its_stolen_tag() -> void:
	var state := _village()
	var thief := _thief(state)
	thief.sneaking = true
	state.apply_command(CastCommand.new(1, A.PICKPOCKET, _merchant(state).cell))
	var ally := state.add_entity(SimArchetypes.make("vanguard", "Ari", PLAYERS, Vector3i(2, Y, 2)))
	var index := thief.inventory.find("Coins")
	assert_true(state.apply_command(GiveCommand.new(1, ally.id, index)))
	assert_true(ally.inventory.has("Coins"))
	assert_true(CrimeRules.is_stolen(ally, "Coins"))
	assert_false(CrimeRules.is_stolen(thief, "Coins"))


func test_crime_state_survives_a_snapshot() -> void:
	var state := _village()
	state.apply_command(CastCommand.new(1, A.PICKPOCKET, _merchant(state).cell))
	var copy := SimState.from_snapshot(state.to_snapshot())
	assert_eq(copy.checksum(), state.checksum())


# --- Items -------------------------------------------------------------------------

func test_items_have_value_and_weight() -> void:
	assert_eq(SimItems.value_of("Silver ring"), 40)
	assert_eq(SimItems.weight_of("Bread"), 400)
	var bag: Array[String] = ["Gold", "Bread", "Silver ring"]
	assert_eq(SimItems.total_value(bag), 25 + 1 + 40)
	assert_eq(SimItems.total_weight(bag), 250 + 400 + 20)
	assert_eq(SimItems.weight_text(670), "670 g")
	assert_eq(SimItems.weight_text(1250), "1.25 kg")


func test_unknown_items_are_worthless_oddments() -> void:
	assert_eq(SimItems.value_of("Mystery thing"), 0)
	assert_eq(SimItems.weight_of("Mystery thing"), 1000)


func test_every_item_in_the_levels_is_in_the_catalog() -> void:
	for path in ["res://levels/start_area/start_area.tscn", "res://levels/arena/arena.tscn"]:
		var text := FileAccess.get_file_as_string(path)
		var regex := RegEx.create_from_string(r'inventory = Array\[String\]\(\[([^\]]*)\]\)')
		for m in regex.search_all(text):
			for raw in m.get_string(1).split(","):
				var item := raw.strip_edges().trim_prefix('"').trim_suffix('"')
				assert_true(SimItems.ITEMS.has(item), "%s (in %s)" % [item, path])


func test_sorting_moves_an_item_to_another_slot() -> void:
	var state := _village()
	var thief := _thief(state)
	thief.inventory.assign(["Gold", "Bread", "Map"])
	assert_true(state.apply_command(SortItemCommand.new(1, 0, 2)))
	assert_eq(thief.inventory, ["Bread", "Map", "Gold"] as Array[String])
	assert_true(state.apply_command(SortItemCommand.new(1, 2, 0)))
	assert_eq(thief.inventory, ["Gold", "Bread", "Map"] as Array[String])
	assert_false(state.apply_command(SortItemCommand.new(1, 0, 3)), "no slot 3")
	assert_eq(SimCommandRegistry.from_dict(SortItemCommand.new(1, 0, 2).to_dict()).to_dict(), SortItemCommand.new(1, 0, 2).to_dict())
