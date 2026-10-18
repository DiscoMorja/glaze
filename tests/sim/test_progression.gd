extends GutTest
## Attributes, school ranks and civil skills (StatRules, GDD §5.9).

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES
const NEUTRAL := SimEntity.Faction.NEUTRAL


## The duel with the bandit next to the hero (hero at (2, 2), bandit at (3, 2)).
func _adjacent_duel() -> SimState:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(3, Y, 2))
	return state


# --- Attributes -------------------------------------------------------------------

func test_weapons_hit_with_their_attribute() -> void:
	var e := SimEntity.character("E", PLAYERS, Vector3i.ZERO, 10, "Daggers", 3)
	e.strength = 4
	assert_eq(e.attack_damage(), 3, "daggers ignore Strength")
	e.dexterity = 5
	assert_eq(e.attack_damage(), 3 + 2, "+1 per 2 Dexterity")
	EquipRules.put(e, "main_hand", "Staff")
	e.mind = 2
	assert_eq(e.attack_damage(), 2 + 1, "a staff hits with Mind")
	EquipRules.put(e, "main_hand", "")
	assert_eq(e.attack_damage(), e.unarmed_damage + 2, "fists use Strength")


func test_dexterity_hits_harder_from_behind() -> void:
	var state := _adjacent_duel()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	hero.dexterity = 4
	bandit.facing = SimPerception.FACINGS.find(Vector3i(-1, 0, 0))  # facing the hero
	var hp := bandit.hp
	assert_true(state.apply_command(AttackCommand.new(1, 2)))
	assert_eq(bandit.hp, hp - 4, "from the front: the sword")
	bandit.facing = SimPerception.FACINGS.find(Vector3i(1, 0, 0))  # its back to the hero
	hp = bandit.hp
	assert_true(state.apply_command(AttackCommand.new(1, 2)))
	assert_eq(bandit.hp, hp - 4 - 2, "from behind: +1 per 2 Dexterity")


func test_vitality_adds_hp_armour_and_stagger() -> void:
	var e := SimEntity.character("E", PLAYERS, Vector3i.ZERO, 10)
	StatRules.set_value(e, "vitality", 4)
	assert_eq(e.max_hp, 10 + 4 * StatRules.HP_PER_VITALITY)
	assert_eq(e.hp, e.max_hp)
	assert_eq(e.armor, 1)
	assert_eq(StatRules.stagger_limit(e), e.stagger_max + 1)


func test_ward_softens_fire_and_frost_but_not_blows() -> void:
	var state := Fixtures.duel_state()
	var bandit := Fixtures.bandit(state)
	bandit.ward = 3
	var hp := bandit.hp
	EntityOps.damage(state, bandit, 4, -1, EntityOps.Element.FIRE)
	assert_eq(bandit.hp, hp - 3)
	EntityOps.damage(state, bandit, 1, -1, EntityOps.Element.FROST)
	assert_eq(bandit.hp, hp - 4, "never more than half a hit")
	EntityOps.damage(state, bandit, 4)
	assert_eq(bandit.hp, hp - 8, "physical hits are armour's job")


func test_ward_strengthens_heals_given_and_received() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	hero.hp = 5
	hero.ward = 3  # +1 cast (3 / 2), +1 received (3 / 3)
	assert_true(state.apply_command(CastCommand.new(1, A.MEND, hero.cell)))
	assert_eq(hero.hp, 5 + SimAbilities.MEND_HEAL + 2)


func test_strength_and_mind_set_what_you_can_move() -> void:
	var state := _adjacent_duel()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	bandit.mass = StatRules.SHOVE_BASE + 1
	assert_false(CastCommand.new(1, A.SHOVE, bandit.cell).validate(state), "too heavy at Strength 0")
	hero.strength = 1
	assert_true(CastCommand.new(1, A.SHOVE, bandit.cell).validate(state))
	bandit.mass = StatRules.TELEPORT_BASE + 5
	assert_false(CastCommand.new(1, A.TELEPORT, bandit.cell, Vector3i(6, Y, 6)).validate(state))
	hero.mind = 1
	assert_true(CastCommand.new(1, A.TELEPORT, bandit.cell, Vector3i(6, Y, 6)).validate(state))


func test_dexterity_stretches_ap_for_walking() -> void:
	var e := SimEntity.character("E", PLAYERS, Vector3i.ZERO, 10)
	e.ap = 2
	assert_eq(CombatRules.move_budget(e), 2 * CombatRules.MOVE_COST_PER_AP)
	e.dexterity = 5
	assert_eq(CombatRules.move_budget(e), 2 * (CombatRules.MOVE_COST_PER_AP + 5))
	assert_eq(CombatRules.move_ap_cost(25, e), 1, "2.5 cells for one AP")


func test_carrying_too_much_slows() -> void:
	var e := SimEntity.character("E", PLAYERS, Vector3i.ZERO, 10)
	assert_false(e.is_slowed())
	for _i in 3:
		e.inventory.append("Chain shirt")  # 27 kg
	assert_true(StatRules.is_overloaded(e))
	assert_true(e.is_slowed())
	e.strength = 2  # 28 kg
	assert_false(e.is_slowed())


# --- Schools ------------------------------------------------------------------------

func test_school_rank_gates_skills() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	hero.schools[StatRules.School.WARRIOR] = 1
	assert_false(CastCommand.new(1, A.SHOCKWAVE, Vector3i(5, Y, 2)).validate(state), "Shockwave needs Warrior 2")
	assert_eq(SimAbilities.lacks(hero, A.SHOCKWAVE), "Needs Warrior 2")
	hero.schools[StatRules.School.WARRIOR] = 2
	assert_true(CastCommand.new(1, A.SHOCKWAVE, Vector3i(5, Y, 2)).validate(state))


func test_ranks_above_a_skill_add_potency() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	EntityOps.place(state, hero, Vector3i(7, Y, 9))
	hero.schools[StatRules.School.FIRE] = 3
	assert_eq(SimAbilities.potency(hero, A.FIREBOLT), 2)
	var hp := bandit.hp
	state.apply_command(CastCommand.new(1, A.FIREBOLT, bandit.cell))
	assert_lte(bandit.hp, hp - SimAbilities.FIREBOLT_DAMAGE - 2)


func test_oil_flasks_are_items_used_up_by_throwing() -> void:
	var state := Fixtures.duel_state()
	var e := state.add_entity(SimEntity.character("Thrower", PLAYERS, Vector3i(2, Y, 6), 10))
	e.ap = 4
	assert_false(SimAbilities.available(e).has(A.OIL_FLASK), "nothing to throw")
	e.inventory.assign(["Oil flask"])
	assert_true(SimAbilities.available(e).has(A.OIL_FLASK), "anyone carrying one can throw it")
	assert_true(state.apply_command(CastCommand.new(e.id, A.OIL_FLASK, Vector3i(5, Y, 6))))
	assert_true(e.inventory.is_empty(), "the flask is gone")
	assert_false(SimAbilities.available(e).has(A.OIL_FLASK))


func test_roles_start_with_their_preset() -> void:
	var pyro := SimArchetypes.make("pyromancer", "Bram", PLAYERS, Vector3i.ZERO)
	assert_eq([pyro.mind, pyro.ward, pyro.dexterity, pyro.historian], [3, 1, 1, 1])
	assert_eq(pyro.schools[StatRules.School.FIRE], 2)
	assert_eq(pyro.inventory.count("Oil flask"), 3)
	assert_true(SimAbilities.available(pyro).has(A.OIL_FLASK))
	var brute := SimArchetypes.make("brute", "Brute", ENEMIES, Vector3i.ZERO)
	assert_eq(brute.max_hp, 26, "same HP as before: base 20 + Vitality 2")
	assert_eq(brute.schools[StatRules.School.WARRIOR], 1, "enemies know the schools of their verbs")
	for role: String in SimArchetypes.ROLES:
		var e := SimArchetypes.make(role, role, ENEMIES, Vector3i.ZERO)
		for ability in e.abilities:
			assert_eq(SimAbilities.lacks(e, ability), "", "%s can use %s" % [role, SimAbilities.NAMES[ability]])


# --- Civil skills -------------------------------------------------------------------

## Outside combat: a thief (id 1) next to a townsman (id 2) with a cheap and a dear item.
func _street() -> SimState:
	var state := Fixtures.flat_state(Vector3i(12, 5, 12))
	var thief := state.add_entity(SimArchetypes.make("trickster", "Cel", PLAYERS, Vector3i(2, Y, 2)))
	thief.inventory.clear()
	var mark := state.add_entity(SimArchetypes.make("villager", "Mark", NEUTRAL, Vector3i(3, Y, 2), ["Bread", "Silver ring"] as Array[String]))
	mark.sight = 0  # sees nothing
	return state


func test_thievery_chooses_what_to_pickpocket() -> void:
	var state := _street()
	var thief := state.get_entity(1)
	var mark := state.get_entity(2)
	thief.thievery = 0
	assert_false(CastCommand.new(1, A.PICKPOCKET, mark.cell, Vector3i.ZERO, 1).validate(state), "no choosing at Thievery 0")
	thief.thievery = 1
	assert_false(CastCommand.new(1, A.PICKPOCKET, mark.cell, Vector3i.ZERO, 1).validate(state), "a 40 gold ring is beyond rank 1")
	thief.thievery = 2
	assert_true(state.apply_command(CastCommand.new(1, A.PICKPOCKET, mark.cell, Vector3i.ZERO, 1)))
	assert_eq(thief.inventory, ["Silver ring"] as Array[String])
	assert_eq(mark.inventory, ["Bread"] as Array[String])


func test_lockpicks_open_locks_up_to_your_thievery() -> void:
	var state := _street()
	var thief := state.get_entity(1)
	var chest := state.add_entity(SimEntity.container("Chest", Vector3i(2, Y, 3), ["Gold"] as Array[String]))
	chest.lock_level = 2
	thief.thievery = 2
	assert_ne(LootCommand.blocker(state, thief, chest), "", "no lockpick")
	thief.inventory.assign(["Lockpick"])
	thief.thievery = 1
	assert_ne(LootCommand.blocker(state, thief, chest), "", "not skilled enough")
	thief.thievery = 2
	assert_true(state.apply_command(LootCommand.new(1, chest.id, LootCommand.ALL)))
	assert_true(thief.inventory.has("Gold"))
	assert_true(thief.inventory.has("Lockpick"), "a lockpick isn't used up")
	assert_eq(chest.lock_level, 0, "it stays open")


func test_thievery_sneaks_faster_and_walks_silently() -> void:
	var state := _street()
	var thief := state.get_entity(1)
	var guard := state.get_entity(2)
	guard.sight = 6
	guard.facing = SimPerception.FACINGS.find(Vector3i(1, 0, 0))  # its back to the thief
	assert_true(SimPerception.can_see(state, guard, thief), "heard walking up behind")
	thief.thievery = StatRules.SILENT_RANK
	assert_false(SimPerception.can_see(state, guard, thief), "a master thief isn't heard")
	thief.sneaking = true
	thief.thievery = StatRules.SNEAK_FAST_RANK
	thief.travel.assign([Vector3i(2, Y, 3), Vector3i(2, Y, 4)])
	state.tick = 1  # an odd tick: half-speed walkers wait
	state.step_ticks(1)
	assert_eq(thief.cell, Vector3i(2, Y, 3), "sneaks at full speed")


func test_dialogue_reads_the_talker_and_calms() -> void:
	var state := _street()
	var talker := state.get_entity(1)
	var npc := state.get_entity(2)
	npc.suspicious = true
	SimDialogue.register("=== test_calm\n{talker.charisma >= 2} Mark: Fine words.\n{talker.charisma >= 2} ~ calm\n", "test")
	talker.charisma = 1
	SimDialogue.start(state, talker, npc, "test_calm")
	assert_true(npc.suspicious)
	assert_eq(state.conversation.lines.size(), 0)
	SimDialogue.end(state)
	talker.charisma = 2
	SimDialogue.start(state, talker, npc, "test_calm")
	assert_false(npc.suspicious, "talked down")
	assert_eq(SimFacts.value(state, "talker.charisma", {"talker": 1}), 2)
	assert_eq(SimFacts.value(state, "talker.fire", {"talker": 1}), 0)
	SimDialogue.knots.erase("test_calm")
