extends GutTest
## The paperdoll: eleven slots, what fits where, two-handed weapons, gear
## stats, and what fallen enemies drop.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


## Outside combat: Ari (id 1, vanguard with a two-handed Greatsword).
func _camp() -> SimState:
	var state := Fixtures.flat_state(Vector3i(12, 5, 12))
	state.add_entity(SimArchetypes.make("vanguard", "Ari", PLAYERS, Vector3i(5, Y, 5)))
	state.drain_events()
	return state


func _ari(state: SimState) -> SimEntity:
	return state.get_entity(1)


func _equip(state: SimState, item: String, slot: String = "") -> bool:
	var ari := _ari(state)
	ari.inventory.append(item)
	return state.apply_command(EquipCommand.new(1, ari.inventory.size() - 1, slot))


func test_every_wearable_item_fits_a_slot() -> void:
	for item: String in SimItems.ITEMS:
		var kind := SimItems.slot_of(item)
		if kind != "":
			assert_true(EquipRules.SLOTS.any(func(slot: String) -> bool: return EquipRules.fits(slot, item)), item)


func test_items_only_go_where_they_fit() -> void:
	var state := _camp()
	assert_false(_equip(state, "Iron helm", "feet"))
	assert_false(_equip(state, "Map"))
	assert_true(_equip(state, "Iron helm"))
	assert_eq(_ari(state).worn.head, "Iron helm")


func test_a_new_weapon_swaps_the_old_one_into_the_bag() -> void:
	var state := _camp()
	assert_true(_equip(state, "Fine sword"))
	assert_eq(_ari(state).weapon, "Fine sword")
	assert_eq(_ari(state).attack_damage(), 6)
	assert_true(_ari(state).inventory.has("Greatsword"))


func test_two_handed_weapons_and_the_off_hand_exclude_each_other() -> void:
	var state := _camp()
	var ari := _ari(state)
	assert_true(_equip(state, "Wooden shield"))
	assert_eq(ari.weapon, "", "the greatsword needed both hands")
	assert_true(ari.inventory.has("Greatsword"))
	assert_eq(ari.armor, 1)
	assert_true(_equip(state, "Fine sword"))
	assert_eq(ari.worn.get("off_hand"), "Wooden shield", "a one-handed sword keeps the shield")
	ari.inventory.erase("Greatsword")
	assert_true(_equip(state, "Greatsword"))
	assert_false(ari.worn.has("off_hand"), "the greatsword takes the shield off")
	assert_true(ari.inventory.has("Wooden shield"))
	assert_true(ari.inventory.has("Fine sword"))


func test_two_rings_fill_both_ring_slots() -> void:
	var state := _camp()
	assert_true(_equip(state, "Copper ring"))
	assert_true(_equip(state, "Silver ring"))
	assert_eq(_ari(state).worn.ring1, "Copper ring")
	assert_eq(_ari(state).worn.ring2, "Silver ring")
	assert_true(_equip(state, "Copper ring", "ring2"))
	assert_eq(_ari(state).worn.ring2, "Copper ring")
	assert_true(_ari(state).inventory.has("Silver ring"))


func test_gear_adds_up_into_stats() -> void:
	var state := _camp()
	var ari := _ari(state)
	var hp := ari.max_hp
	var damage := ari.attack_damage()
	_equip(state, "Leather boots")  # +2 HP
	_equip(state, "Amber pendant")  # +4 HP
	_equip(state, "Brawler's gloves")  # +1 damage
	_equip(state, "Silver ring")  # +1 power
	assert_eq(ari.max_hp, hp + 6)
	assert_eq(ari.hp, ari.max_hp, "the bonus HP is there to use")
	assert_eq(ari.attack_damage(), damage + 2)
	assert_eq(ari.spell_power(), 1)
	assert_true(state.apply_command(EquipCommand.new(1, EquipCommand.UNEQUIP, "neck")))
	assert_eq(ari.max_hp, hp + 2)
	assert_true(ari.inventory.has("Amber pendant"))


func test_taking_off_hp_gear_lowers_hp_only_above_the_new_max() -> void:
	var state := _camp()
	var ari := _ari(state)
	_equip(state, "Amber pendant")
	ari.hp = 2
	state.apply_command(EquipCommand.new(1, EquipCommand.UNEQUIP, "neck"))
	assert_eq(ari.hp, 2, "wounds stay as they were")
	_equip(state, "Amber pendant")
	ari.hp = ari.max_hp
	state.apply_command(EquipCommand.new(1, EquipCommand.UNEQUIP, "neck"))
	assert_eq(ari.hp, ari.max_hp, "the bonus HP goes with it")


func test_armour_softens_blows_by_at_most_half_and_not_fire() -> void:
	var state := _camp()
	var ari := _ari(state)
	_equip(state, "Chain shirt")
	_equip(state, "Iron helm")
	assert_eq(ari.armor, 3)
	var hp := ari.hp
	EntityOps.damage(state, ari, 8, -1)
	assert_eq(ari.hp, hp - 5)
	EntityOps.damage(state, ari, 4, -1)
	assert_eq(ari.hp, hp - 7, "half of 4 still gets through")
	EntityOps.damage(state, ari, 4, -1, EntityOps.Element.FIRE)
	assert_eq(ari.hp, hp - 11, "fire ignores armour")


func test_no_equipping_in_combat() -> void:
	var state := _camp()
	_ari(state).inventory.append("Iron helm")
	state.combat.active = true
	assert_false(EquipCommand.new(1, 0).validate(state))


func test_fallen_enemies_drop_everything_they_wore() -> void:
	var state := _camp()
	var thug := SimArchetypes.make("thug", "Thug", ENEMIES, Vector3i(5, Y, 4))
	EquipRules.put(thug, "body", "Leather armour")
	EquipRules.put(thug, "head", "Leather cap")
	state.add_entity(thug)
	EntityOps.damage(state, thug, 100, 1)
	assert_eq(thug.inventory, ["Leather cap", "Leather armour", "Club"] as Array[String])
	assert_eq(thug.weapon, "")
	assert_true(thug.worn.is_empty())
	assert_true(LootCommand.is_container(thug))


func test_saves_from_before_the_paperdoll_keep_their_armour() -> void:
	var state := _camp()
	var data := _ari(state).to_dict()
	data.erase("worn")
	data["armor_item"] = "Chain shirt"
	var old := SimEntity.from_dict(data)
	assert_eq(old.worn.get("body"), "Chain shirt")
