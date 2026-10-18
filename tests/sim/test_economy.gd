extends GutTest
## Consumables, resting, trading, equipment and progression.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES
const NEUTRAL := SimEntity.Faction.NEUTRAL


## A 30x5x30 field outside combat: Ari (id 1) and Bram (id 2) of the party
## side by side, and a merchant (id 3, trader, village pack 5) next to Ari.
## Ari's Charisma is 0, so trades are at list prices.
func _town() -> SimState:
	var state := Fixtures.flat_state(Vector3i(30, 5, 30))
	state.add_entity(SimArchetypes.make("vanguard", "Ari", PLAYERS, Vector3i(5, Y, 5))).charisma = 0
	state.add_entity(SimArchetypes.make("pyromancer", "Bram", PLAYERS, Vector3i(6, Y, 5)))
	var merchant := SimArchetypes.make("merchant", "Merchant", NEUTRAL, Vector3i(5, Y, 6), ["Healing potion", "Map", "Chain shirt"] as Array[String])
	merchant.trader = true
	merchant.gold = 50
	merchant.pack = 5
	state.add_entity(merchant)
	state.drain_events()
	return state


func _ari(state: SimState) -> SimEntity:
	return state.get_entity(1)


func _bram(state: SimState) -> SimEntity:
	return state.get_entity(2)


func _merchant(state: SimState) -> SimEntity:
	return state.get_entity(3)


# --- Consumables ----------------------------------------------------------------

func test_a_potion_heals_and_is_used_up() -> void:
	var state := _town()
	var ari := _ari(state)
	ari.hp = 10
	ari.inventory.assign(["Healing potion"])
	assert_true(state.apply_command(UseItemCommand.new(1, 0)))
	assert_eq(ari.hp, 20)
	assert_true(ari.inventory.is_empty())


func test_items_work_on_an_adjacent_ally_but_not_far_away() -> void:
	var state := _town()
	_bram(state).hp = 5
	_ari(state).inventory.assign(["Bread", "Bread"])
	assert_true(state.apply_command(UseItemCommand.new(1, 0, 2)))
	assert_eq(_bram(state).hp, 8)
	EntityOps.place(state, _bram(state), Vector3i(20, Y, 20))
	assert_false(UseItemCommand.new(1, 0, 2).validate(state))


func test_a_cooling_salve_puts_out_burning() -> void:
	var state := _town()
	var ari := _ari(state)
	EntityOps.change_temperature(state, ari, 2)
	assert_true(ari.is_burning())
	ari.inventory.assign(["Cooling salve"])
	state.apply_command(UseItemCommand.new(1, 0))
	assert_false(ari.is_burning())


func test_using_items_costs_ap_in_combat_and_odd_items_do_nothing() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	hero.inventory.assign(["Map", "Healing potion"])
	assert_false(UseItemCommand.new(1, 0).validate(state), "a map isn't usable")
	var ap := hero.ap
	assert_true(state.apply_command(UseItemCommand.new(1, 1)))
	assert_eq(hero.ap, ap - UseItemCommand.AP_COST)


# --- Rest -------------------------------------------------------------------------

func test_resting_heals_the_party_and_clears_statuses() -> void:
	var state := _town()
	_ari(state).hp = 3
	_ari(state).slowed = 2
	_bram(state).hp = 1
	_bram(state).cooldowns[SimAbilities.Ability.FIREBOLT] = 2
	assert_eq(RestCommand.blocker(state, _ari(state)), "Needs a bedroll")
	_bram(state).inventory.append("Bedroll")
	assert_true(state.apply_command(RestCommand.new(1)))
	assert_eq(_ari(state).hp, _ari(state).max_hp)
	assert_eq(_bram(state).hp, _bram(state).max_hp)
	assert_eq(_ari(state).slowed, 0)
	assert_eq(_bram(state).cooldown(SimAbilities.Ability.FIREBOLT), 0)
	assert_true(_bram(state).inventory.has("Bedroll"), "kept")


func test_no_rest_with_enemies_near_or_for_the_fallen() -> void:
	var state := _town()
	_ari(state).inventory.append("Bedroll")
	var thug := SimArchetypes.make("thug", "Thug", ENEMIES, Vector3i(14, Y, 5))
	state.add_entity(thug)
	assert_eq(RestCommand.blocker(state, _ari(state)), "Enemies are near")
	EntityOps.place(state, thug, Vector3i(28, Y, 28))
	EntityOps.damage(state, _bram(state), 100)
	state.combat.active = false
	assert_true(state.apply_command(RestCommand.new(1)))
	assert_false(_bram(state).is_alive(), "rest doesn't revive")


# --- Trade -------------------------------------------------------------------------

func test_buying_costs_value_and_selling_fetches_half() -> void:
	var state := _town()
	var ari := _ari(state)
	ari.gold = 30
	ari.inventory.assign(["Silver ring"])  # 40 -> sells for 20
	var deal := TradeCommand.new(1, 3, [0] as Array[int], [0] as Array[int])  # potion (20) for the ring
	assert_eq(TradeCommand.balance(_merchant(state), ari, deal.buy, deal.sell), 0)
	assert_true(state.apply_command(deal))
	assert_eq(ari.gold, 30)
	assert_true(ari.inventory.has("Healing potion"))
	assert_true(_merchant(state).inventory.has("Silver ring"))


func test_money_sells_at_full_value_and_you_must_afford_it() -> void:
	var state := _town()
	var ari := _ari(state)
	ari.gold = 0
	assert_false(TradeCommand.new(1, 3, [2] as Array[int], [] as Array[int]).validate(state), "chain shirt: 70 gold")
	ari.inventory.assign(["Gold", "Gold", "Gold"])
	assert_eq(TradeCommand.offer_for("Gold"), 25)
	assert_true(state.apply_command(TradeCommand.new(1, 3, [2] as Array[int], [0, 1, 2] as Array[int])))
	assert_eq(ari.gold, 5)
	assert_true(ari.inventory.has("Chain shirt"))


func test_charisma_lowers_prices_and_raises_offers() -> void:
	var state := _town()
	var ari := _ari(state)
	var merchant := _merchant(state)
	assert_eq(TradeCommand.price_of(merchant, "Chain shirt", ari), 70)
	ari.charisma = 2
	assert_eq(TradeCommand.price_of(merchant, "Chain shirt", ari), 63, "10 % off")
	assert_eq(TradeCommand.offer_for("Silver ring", ari), 24, "60 % of 40")
	assert_eq(TradeCommand.offer_for("Gold", ari), 25, "money stays at full value")
	merchant.suspicious = true
	assert_eq(TradeCommand.price_of(merchant, "Chain shirt", ari), 94, "half again when wary")


func test_the_trader_needs_gold_to_buy() -> void:
	var state := _town()
	_merchant(state).gold = 5
	_ari(state).inventory.assign(["Silver ring"])
	assert_false(TradeCommand.new(1, 3, [] as Array[int], [0] as Array[int]).validate(state))


func test_suspicious_traders_charge_more_and_wont_buy_their_own_goods() -> void:
	var state := _town()
	var ari := _ari(state)
	_merchant(state).suspicious = true
	assert_eq(TradeCommand.price_of(_merchant(state), "Healing potion"), 30)
	ari.inventory.assign(["Coins", "Map"])
	CrimeRules.mark_stolen(ari, "Map", 5)
	assert_true(TradeCommand.refuses(_merchant(state), ari, "Map"))
	assert_false(TradeCommand.new(1, 3, [] as Array[int], [1] as Array[int]).validate(state))
	CrimeRules.mark_stolen(ari, "Coins", 9)  # someone else's: fenced
	assert_true(state.apply_command(TradeCommand.new(1, 3, [] as Array[int], [0] as Array[int])))
	assert_false(CrimeRules.is_stolen(_merchant(state), "Coins"))


func test_no_trading_far_away_in_combat_or_with_non_traders() -> void:
	var state := _town()
	_ari(state).gold = 100
	EntityOps.place(state, _ari(state), Vector3i(20, Y, 20))
	assert_false(TradeCommand.new(1, 3, [0] as Array[int], [] as Array[int]).validate(state))
	EntityOps.place(state, _ari(state), Vector3i(5, Y, 5))
	_merchant(state).trader = false
	assert_false(TradeCommand.new(1, 3, [0] as Array[int], [] as Array[int]).validate(state))


func test_the_merchant_offers_to_trade_in_dialogue() -> void:
	Content.load_all()
	var state := _town()
	_merchant(state).dialogue = "merchant"
	state.apply_command(TalkCommand.new(1, 3))
	var options: Array = state.conversation.choices.map(func(c: Dictionary) -> String: return c.text)
	state.apply_command(ChooseCommand.new(1, options.find("Let's trade.")))
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.TRADE_OFFERED).size(), 1)


# --- Progression ------------------------------------------------------------------

func test_kills_give_the_whole_party_xp_and_levels() -> void:
	var state := _town()
	var thug := SimArchetypes.make("thug", "Thug", ENEMIES, Vector3i(5, Y, 4))  # 12 HP -> 48 XP
	state.add_entity(thug)
	EntityOps.damage(state, thug, 100, 1)
	assert_eq(_ari(state).xp, 48)
	assert_eq(_bram(state).xp, 48, "shared")
	var max_hp := _ari(state).max_hp
	ProgressionRules.award(state, 60)
	assert_eq(_ari(state).level, 2)
	assert_eq(_ari(state).points, 1)
	assert_eq(_ari(state).max_hp, max_hp + ProgressionRules.HP_PER_LEVEL)
	assert_eq(Fixtures.events_of_type(state.drain_events(), SimEvent.Type.LEVELED_UP).size(), 2)


func test_killing_townsfolk_gives_no_xp() -> void:
	var state := _town()
	EntityOps.damage(state, _merchant(state), 100, 1)  # turns the village, but the merchant was neutral when hit
	assert_eq(_ari(state).xp, 0)


func test_points_buy_attributes_schools_and_civil_skills() -> void:
	var state := _town()
	var bram := _bram(state)  # Pyromancer: Mind 3, Fire 2, Historian 1
	bram.points = 2
	bram.combat_points = 1
	bram.civil_points = 1
	var hp := bram.max_hp
	assert_true(state.apply_command(SpendPointCommand.new(2, "vitality")))
	assert_eq(bram.max_hp, hp + StatRules.HP_PER_VITALITY)
	assert_eq(bram.attack_damage(), 3, "staff 2 + Mind 3 / 2")
	assert_true(state.apply_command(SpendPointCommand.new(2, "mind")))
	assert_eq(bram.attack_damage(), 4, "a staff hits with Mind")
	assert_false(SpendPointCommand.new(2, "mind").validate(state), "out of attribute points")
	assert_true(state.apply_command(SpendPointCommand.new(2, "death")))
	assert_eq(bram.schools[StatRules.School.DEATH], 1)
	assert_false(SpendPointCommand.new(2, "fire").validate(state), "out of combat points")
	assert_true(state.apply_command(SpendPointCommand.new(2, "charisma")))
	assert_eq(bram.charisma, 1)
	assert_false(SpendPointCommand.new(2, "thievery").validate(state), "out of civil points")
	assert_false(SpendPointCommand.new(1, "luck").validate(state))


func test_ranks_stop_at_five() -> void:
	var state := _town()
	var ari := _ari(state)
	ari.combat_points = 9
	for i in StatRules.MAX_RANK - 2:  # Vanguard starts at Warrior 2
		assert_true(state.apply_command(SpendPointCommand.new(1, "warrior")))
	assert_eq(ari.schools[StatRules.School.WARRIOR], StatRules.MAX_RANK)
	assert_false(SpendPointCommand.new(1, "warrior").validate(state))


func test_levels_give_attribute_combat_and_every_other_civil_point() -> void:
	var state := _town()
	var ari := _ari(state)
	var hp := ari.max_hp
	ProgressionRules.award(state, ProgressionRules.xp_for_level(4))
	assert_eq(ari.level, 4)
	assert_eq([ari.points, ari.combat_points, ari.civil_points], [3, 3, 2], "levels 2, 3, 4; civil at 2 and 4")
	assert_eq(ari.max_hp, hp + 3 * ProgressionRules.HP_PER_LEVEL)


func test_mind_adds_to_spells() -> void:
	var state := Fixtures.duel_state()
	var hero := Fixtures.hero(state)
	var bandit := Fixtures.bandit(state)
	hero.mind = 4
	EntityOps.place(state, hero, Vector3i(7, Y, 9))
	var hp := bandit.hp
	state.apply_command(CastCommand.new(1, SimAbilities.Ability.FIREBOLT, bandit.cell))
	assert_lte(bandit.hp, hp - SimAbilities.FIREBOLT_DAMAGE - 2)


func test_quest_outcomes_give_their_xp() -> void:
	Content.load_all()
	var state := _town()
	state.facts["bandits_known"] = 1
	QuestRules.step(state)
	var bandit := SimArchetypes.make("thug", "Thug", ENEMIES, Vector3i(25, Y, 25))
	bandit.group = "Bandits"
	state.add_entity(bandit)
	EntityOps.damage(state, bandit, 100)  # no killer; 48 XP for the kill
	QuestRules.step(state)
	assert_eq(state.quests.bandits.outcome, "cleared")
	assert_eq(_ari(state).xp, 48 + 250)


func test_new_fields_survive_snapshots() -> void:
	var state := _town()
	var ari := _ari(state)
	ari.gold = 33
	ari.xp = 120
	ari.level = 2
	ari.points = 1
	ari.combat_points = 2
	ari.dexterity = 4
	ari.thievery = 2
	EquipRules.put(ari, "body", "Chain shirt")
	EquipRules.put(ari, "ring2", "Copper ring")
	var copy := SimState.from_snapshot(state.to_snapshot())
	var a := copy.get_entity(1)
	assert_eq([a.gold, a.xp, a.level, a.points, a.combat_points, a.dexterity, a.thievery, a.armor, a.max_hp, a.gear_hp],
			[33, 120, 2, 1, 2, 4, 2, 2, ari.max_hp, 2])
	assert_eq(a.schools, ari.schools)
	assert_eq(a.worn, {"body": "Chain shirt", "ring2": "Copper ring"})
	assert_true(copy.get_entity(3).trader)
	for command: SimCommand in [UseItemCommand.new(1, 0, 2), RestCommand.new(1), TradeCommand.new(1, 3, [0] as Array[int], [1] as Array[int]),
			EquipCommand.new(1, -1, "body"), SpendPointCommand.new(1, "mind")]:
		assert_eq(SimCommandRegistry.from_dict(command.to_dict()).to_dict(), command.to_dict())
