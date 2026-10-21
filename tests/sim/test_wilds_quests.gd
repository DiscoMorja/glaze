extends GutTest
## The wilds quests (game/data/quests/wilds.quest) as the game loads them:
## outcomes over world facts, and the facts they need (intact.<Group>,
## burning.<Group>). Also the firebug that sets the granary's oil off.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES
const NEUTRAL := SimEntity.Faction.NEUTRAL


func before_all() -> void:
	Content.load_all(true)


func _outcome(state: SimState, id: String) -> String:
	return state.quests.get(id, {}).get("outcome", "")


## Hero at (2, 2), two ruffians, and the granary: two sacks and an oil barrel.
func _granary() -> SimState:
	var state := Fixtures.flat_state(Vector3i(14, 5, 14))
	state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(2, Y, 2), 20))
	for x in [9, 10]:
		var ruffian := state.add_entity(SimArchetypes.make("ruffian", "Ruffian", ENEMIES, Vector3i(x, Y, 10)))
		ruffian.group = "Ruffians"
	for z in [6, 8]:
		var sacks := state.add_entity(SimEntity.container("Grain sacks", Vector3i(7, Y, z), ["Bread"] as Array[String]))
		sacks.group = "Granary"
	var oil := state.add_entity(SimEntity.barrel("Oil barrel", Vector3i(6, Y, 7), SimMaterials.Surface.OIL, 150))
	oil.group = "Granary"
	return state


func test_granary_facts_count_things_and_fire() -> void:
	var state := _granary()
	assert_eq(SimFacts.value(state, "intact.Granary"), 3)
	assert_eq(SimFacts.value(state, "burning.Granary"), 0)
	FireRules.ignite(state, Vector3i(7, Y, 6))
	assert_eq(SimFacts.value(state, "burning.Granary"), 1)


func test_a_fire_at_the_granary_makes_the_quest_known() -> void:
	var state := _granary()
	QuestRules.step(state)
	assert_false(QuestRules.fact(state, "granary.known") == 1)
	FireRules.ignite(state, Vector3i(7, Y, 6))
	QuestRules.step(state)
	assert_eq(QuestRules.fact(state, "granary.known"), 1)


func test_granary_saved_once_the_ruffians_are_gone_and_it_stands() -> void:
	var state := _granary()
	state.facts["granary_warned"] = 1
	QuestRules.step(state)
	assert_eq(_outcome(state, "granary"), "", "not saved while the ruffians are about")
	for e in state.entities:
		if e.group == "Ruffians":
			e.hp = 0
	QuestRules.step(state)
	assert_eq(_outcome(state, "granary"), "saved")


func test_granary_burned_when_it_is_mostly_gone() -> void:
	var state := _granary()
	state.facts["granary_warned"] = 1
	var broken := 0
	for e in state.entities:
		if e.group == "Granary" and broken < 2:
			e.hp = 0
			broken += 1
	QuestRules.step(state)
	assert_eq(_outcome(state, "granary"), "burned")


func test_the_firebug_kindles_an_oil_barrel_near_the_party() -> void:
	var state := Fixtures.flat_state(Vector3i(14, 5, 14))
	var hero := state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(6, Y, 4), 20))
	var bug := state.add_entity(SimArchetypes.make("firebug", "Firebug", ENEMIES, Vector3i(6, Y, 10)))
	state.add_entity(SimEntity.barrel("Oil barrel", Vector3i(6, Y, 5), SimMaterials.Surface.OIL, 150))
	assert_true(SimAbilities.has_rank(bug, SimAbilities.Ability.KINDLE))
	state.apply_command(StartCombatCommand.new())
	var kindles := UtilityAi.candidates(state, bug).filter(func(c: SimCommand) -> bool:
		return c is CastCommand and (c as CastCommand).ability == SimAbilities.Ability.KINDLE)
	assert_eq(kindles.size(), 1, "the barrel next to the hero")
	assert_eq((kindles[0] as CastCommand).target, Vector3i(6, Y, 5))
	assert_true(hero.is_alive())


func test_the_hammer_quest_starts_when_the_party_holds_the_hammer() -> void:
	var state := Fixtures.flat_state()
	var hero := state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(2, Y, 2), 20))
	QuestRules.step(state)
	assert_eq(QuestRules.fact(state, "hammer.known"), 0)
	hero.inventory.append("Forge hammer")
	QuestRules.step(state)
	assert_eq(QuestRules.fact(state, "hammer.known"), 1)
	state.facts["hammer_returned"] = 1
	QuestRules.step(state)
	assert_eq(_outcome(state, "hammer"), "returned")


func test_the_shepherd_is_rescued_or_lost() -> void:
	for shepherd_dies in [false, true]:
		var state := Fixtures.flat_state()
		state.facts["shepherd_known"] = 1
		var hob := state.add_entity(SimEntity.character("Hob", NEUTRAL, Vector3i(2, Y, 2), 10))
		hob.group = "Shepherd"
		var ruffian := state.add_entity(SimEntity.character("Ruffian", ENEMIES, Vector3i(6, Y, 6), 7))
		ruffian.group = "HillRuffians"
		QuestRules.step(state)
		assert_eq(_outcome(state, "shepherd"), "")
		if shepherd_dies:
			hob.hp = 0
		ruffian.hp = 0
		QuestRules.step(state)
		assert_eq(_outcome(state, "shepherd"), "lost" if shepherd_dies else "rescued")


func test_the_smuggler_ends_three_ways() -> void:
	for fact: String in ["package_delivered", "smuggler_reported"]:
		var state := Fixtures.flat_state()
		state.facts["smuggler_known"] = 1
		state.facts[fact] = 1
		QuestRules.step(state)
		assert_eq(_outcome(state, "smuggler"), "delivered" if fact == "package_delivered" else "reported")
