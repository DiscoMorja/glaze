extends GutTest
## The paged action bar: default layout, items on the bar, arranging by drag,
## pages, and what pressing a slot does.

const Y := 1
const TEST_PATH := "user://test_hotbars.cfg"
const A := SimAbilities.Ability

var _bar: ActionBar
var _ari: SimEntity
var _pressed: Array = []


func before_each() -> void:
	HotbarLayout.reset(TEST_PATH)
	_ari = SimArchetypes.make("pyromancer", "Testy", SimEntity.Faction.PLAYERS, Vector3i(1, Y, 1), ["Healing potion", "Map", "Healing potion"] as Array[String])
	_ari.id = 1
	_bar = ActionBar.new()
	add_child_autofree(_bar)
	_pressed.clear()
	_bar.action_pressed.connect(func(action: int) -> void: _pressed.append(["action", action]))
	_bar.item_pressed.connect(func(item: String) -> void: _pressed.append(["item", item]))
	_bar.show_actions(_ari, ActionInfo.NONE, true, false)


func after_all() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	HotbarLayout.reset("user://hotbars.cfg")


func test_default_layout_has_actions_then_usable_items() -> void:
	var first := HotbarLayout.page(_ari, 0)
	assert_eq(first[0], HotbarLayout.action_entry(ActionInfo.ATTACK))
	assert_eq(first[1], HotbarLayout.action_entry(A.FIREBOLT))
	var potion_at := first.find(HotbarLayout.item_entry("Healing potion"))
	assert_gt(potion_at, 1, "the potion follows the actions")
	assert_false(first.has(HotbarLayout.item_entry("Map")), "maps don't go on the bar")
	assert_eq(first.count(HotbarLayout.item_entry("Healing potion")), 1, "one slot per kind")


func test_pressing_slots_aims_actions_and_uses_items() -> void:
	_bar.press(1)
	var potion_at := HotbarLayout.page(_ari, 0).find(HotbarLayout.item_entry("Healing potion"))
	_bar.press(potion_at)
	assert_eq(_pressed, [["action", A.FIREBOLT], ["item", "Healing potion"]])


func test_unusable_slots_do_nothing() -> void:
	_ari.cooldowns[A.FIREBOLT] = 2
	_bar.show_actions(_ari, ActionInfo.NONE, true, true)
	_bar.press(1)
	_bar.show_actions(_ari, ActionInfo.NONE, false, false)
	_bar.press(0)
	_bar.press(9)  # empty
	assert_eq(_pressed, [])


func test_dragging_an_inventory_item_onto_a_slot_places_it() -> void:
	var data := {"kind": InventoryPanel.DRAG_KIND, "from_id": 1, "index": 0, "item": "Healing potion"}
	assert_true(_bar._accepts(data))
	assert_false(_bar._accepts({"kind": InventoryPanel.DRAG_KIND, "from_id": 1, "index": 1, "item": "Map"}))
	assert_false(_bar._accepts({"kind": InventoryPanel.DRAG_KIND, "from_id": 2, "index": 0, "item": "Healing potion"}), "someone else's")
	_bar.turn_page(1)
	_bar._drop(4, data)
	assert_eq(HotbarLayout.page(_ari, 1)[4], HotbarLayout.item_entry("Healing potion"))
	assert_false(HotbarLayout.page(_ari, 0).has(HotbarLayout.item_entry("Healing potion")), "moved, not copied")


func test_slots_swap_clear_and_stay_cleared() -> void:
	_bar._drop(5, {"kind": ActionBar.DRAG_KIND, "page": 0, "index": 0})
	assert_eq(HotbarLayout.page(_ari, 0)[5], HotbarLayout.action_entry(ActionInfo.ATTACK))
	_bar._clear(5)
	assert_false(HotbarLayout.page(_ari, 0).has(HotbarLayout.action_entry(ActionInfo.ATTACK)))
	HotbarLayout.reset(TEST_PATH)  # reload from the file
	assert_false(HotbarLayout.page(_ari, 0).has(HotbarLayout.action_entry(ActionInfo.ATTACK)), "a cleared slot isn't refilled")


func test_new_usable_items_find_a_free_slot_once() -> void:
	_ari.inventory.append("Cooling salve")
	var first := HotbarLayout.page(_ari, 0)
	assert_true(first.has(HotbarLayout.item_entry("Cooling salve")))


func test_pages_wrap_around() -> void:
	_bar.turn_page(-1)
	assert_eq(_bar.page, HotbarLayout.PAGES - 1)
	_bar.turn_page(1)
	assert_eq(_bar.page, 0)


func test_every_action_and_bar_item_has_an_icon() -> void:
	for action in [ActionInfo.ATTACK] + range(SimAbilities.NAMES.size()):
		assert_not_null(GameIcons.for_action(action), ActionInfo.name_of(action))
	for item: String in SimItems.ITEMS:  # the inventory shows every item's icon
		assert_not_null(GameIcons.for_item(item), item)
	assert_not_null(GameIcons.portrait())
