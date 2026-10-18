extends GutTest
## Facts, expressions, dialogue and quests.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const NEUTRAL := SimEntity.Faction.NEUTRAL

const SCRIPT := """
=== test_npc
{self.suspicious} Npc: I'm watching you.
Npc: Hello there.
* [Who are you?] -> test_who
* {met} [Again?] -> test_again
* [Bye.] -> END

=== test_who
Npc: Nobody.
~ met = 1
~ count += 2
~ give Ring
-> END

=== test_again
Npc: Yes, again.
~ take Gold
-> END
"""

const QUEST := """
=== quest test_q
title: Test quest
known: met
active: Find out who the npc is.
outcome friends: met and has.Ring
    We have the ring.
outcome angry: hostile.Town
    They hate us.
"""


func before_each() -> void:
	SimDialogue.clear()
	QuestRules.clear()
	SimDialogue.register(SCRIPT, "test")
	QuestRules.register(QUEST, "test")


func after_all() -> void:
	SimDialogue.clear()
	QuestRules.clear()
	Content.load_all(true)  # put the game's content back for other tests


## A hero (id 1) next to a talkative townsperson (id 2, group Town, with a Ring).
func _talk_state() -> SimState:
	var state := Fixtures.flat_state(Vector3i(9, 4, 9))
	state.add_entity(SimEntity.character("Hero", PLAYERS, Vector3i(2, Y, 2), 20, "Sword", 4, ["Gold"] as Array[String]))
	var npc := state.add_entity(SimEntity.character("Npc", NEUTRAL, Vector3i(3, Y, 2), 10, "", 1, ["Ring"] as Array[String]))
	npc.group = "Town"
	npc.dialogue = "test_npc"
	return state


# --- Expressions -----------------------------------------------------------------

func test_expressions_evaluate() -> void:
	var state := _talk_state()
	state.facts["a"] = 3
	for case: Array in [["a == 3", 1], ["a > 4", 0], ["not a", 0], ["a - 1 == 2 and not b", 1],
			["b or (a >= 3 and a <= 3)", 1], ["alive.Town", 1], ["has.Gold", 1], ["has.Ring", 0], ["7", 7]]:
		assert_eq(SimExpr.eval(state, SimExpr.parse(case[0])), case[1], case[0])


func test_bad_expressions_are_rejected() -> void:
	for bad in ["a ==", "(a", "a and", "a $ b"]:
		assert_null(SimExpr.parse(bad), bad)


func test_the_game_content_parses_cleanly() -> void:
	Content.load_all(true)
	assert_eq(SimDialogue.errors, [] as Array[String])
	assert_eq(QuestRules.errors, [] as Array[String])
	assert_true(SimDialogue.knots.has("merchant"))
	assert_true(QuestRules.quests.has("bandits"))
	SimDialogue.clear()
	QuestRules.clear()
	SimDialogue.register(SCRIPT, "test")
	QuestRules.register(QUEST, "test")


# --- Dialogue --------------------------------------------------------------------

func test_talking_shows_a_page_of_lines_and_choices() -> void:
	var state := _talk_state()
	assert_true(state.apply_command(TalkCommand.new(1, 2)))
	var convo := state.conversation
	assert_eq(convo.lines.size(), 1, "the suspicious line is skipped")
	assert_eq(convo.lines[0][1], "Hello there.")
	assert_eq(convo.choices.size(), 2, "the {met} choice is hidden")


func test_choosing_runs_effects_and_ends() -> void:
	var state := _talk_state()
	state.apply_command(TalkCommand.new(1, 2))
	assert_true(state.apply_command(ChooseCommand.new(1, 0)))
	assert_eq(state.facts.met, 1)
	assert_eq(state.facts.count, 2)
	assert_true(Fixtures.hero(state).inventory.has("Ring"), "the npc gave its ring")
	assert_true(SimDialogue.at_end(state))
	assert_true(state.apply_command(ChooseCommand.new(1, -1)))
	assert_true(state.conversation.is_empty())


func test_conditions_open_new_choices_later() -> void:
	var state := _talk_state()
	state.facts["met"] = 1
	state.apply_command(TalkCommand.new(1, 2))
	assert_eq(state.conversation.choices.size(), 3)
	state.apply_command(ChooseCommand.new(1, 1))
	assert_false(Fixtures.hero(state).inventory.has("Gold"), "took the gold")


func test_talk_needs_reach_peace_and_a_script() -> void:
	var state := _talk_state()
	EntityOps.place(state, Fixtures.hero(state), Vector3i(7, Y, 7))
	assert_false(state.apply_command(TalkCommand.new(1, 2)), "too far")
	EntityOps.place(state, Fixtures.hero(state), Vector3i(2, Y, 2))
	state.get_entity(2).dialogue = ""
	assert_false(state.apply_command(TalkCommand.new(1, 2)), "nothing to say")


func test_walking_away_ends_the_talk() -> void:
	var state := _talk_state()
	state.apply_command(TalkCommand.new(1, 2))
	state.apply_command(TravelCommand.new(1, Vector3i(2, Y, 6)))
	assert_true(state.conversation.is_empty())


func test_conversations_survive_snapshots() -> void:
	var state := _talk_state()
	state.apply_command(TalkCommand.new(1, 2))
	var copy := SimState.from_snapshot(state.to_snapshot())
	assert_eq(copy.checksum(), state.checksum())
	assert_true(copy.apply_command(ChooseCommand.new(1, 0)))


# --- Quests ----------------------------------------------------------------------

func test_a_quest_becomes_known_then_ends_by_outcome() -> void:
	var state := _talk_state()
	assert_eq(SimFacts.value(state, "quest.test_q.known"), 0)
	state.apply_command(TalkCommand.new(1, 2))
	state.apply_command(ChooseCommand.new(1, 0))  # met = 1, and the ring changes hands
	assert_eq(SimFacts.value(state, "quest.test_q.known"), 1)
	assert_eq(SimFacts.value(state, "quest.test_q.friends"), 1, "ended the friendly way")
	assert_eq(QuestRules.journal(state, "test_q"), ["Test quest", "We have the ring.", true])


func test_any_route_to_an_outcome_counts() -> void:
	var state := _talk_state()
	# Never talked: steal the ring and set the fact some other way; it still ends.
	CrimeRules.move_item(state.get_entity(2), Fixtures.hero(state), 0)
	state.facts["met"] = 1
	state.step()
	assert_eq(SimFacts.value(state, "quest.test_q.friends"), 1)


func test_outcomes_wait_until_the_quest_is_known() -> void:
	var state := _talk_state()
	CrimeRules.turn_hostile(state, state.get_entity(2))
	state.step()
	assert_eq(SimFacts.value(state, "quest.test_q.angry"), 0, "not known yet")
	state.facts["met"] = 1
	state.step()
	assert_eq(SimFacts.value(state, "quest.test_q.angry"), 1, "ends as soon as it is known")


func test_outcomes_are_checked_in_order_and_end_once() -> void:
	var state := _talk_state()
	state.facts["met"] = 1
	CrimeRules.move_item(state.get_entity(2), Fixtures.hero(state), 0)
	CrimeRules.turn_hostile(state, state.get_entity(2))
	state.step()
	assert_eq(SimFacts.value(state, "quest.test_q.friends"), 1, "both hold: the first listed wins")
	assert_eq(SimFacts.value(state, "quest.test_q.angry"), 0, "and it ends only once")
