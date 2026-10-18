extends GutTest
## The trade window: picking items builds the deal it asks for, the total
## and Accept follow the rules, refused items can't be picked.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y

var _panel: TradePanel
var _state: SimState
var _deals: Array = []


func before_each() -> void:
	_state = Fixtures.flat_state(Vector3i(12, 5, 12))
	var ari := SimArchetypes.make("vanguard", "Ari", SimEntity.Faction.PLAYERS, Vector3i(5, Y, 5), ["Silver ring", "Map"] as Array[String])
	ari.gold = 5
	ari.charisma = 0  # list prices
	_state.add_entity(ari)
	var merchant := SimArchetypes.make("merchant", "Merchant", SimEntity.Faction.NEUTRAL, Vector3i(5, Y, 6), ["Healing potion"] as Array[String])
	merchant.trader = true
	merchant.gold = 50
	merchant.pack = 3
	_state.add_entity(merchant)
	_panel = TradePanel.new()
	add_child_autofree(_panel)
	_deals.clear()
	_panel.deal_requested.connect(func(buy: Array[int], sell: Array[int]) -> void: _deals.append([buy, sell]))
	_panel.open(1, 2)
	_panel.show_trade(_state)


func _slots(grid: GridContainer) -> Array[ItemSlot]:
	var result: Array[ItemSlot] = []
	for child in grid.get_children():
		if child is ItemSlot and not child.is_queued_for_deletion():
			result.append(child)
	return result


func test_picking_items_builds_the_deal() -> void:
	assert_true(_panel._accept.disabled, "nothing on the table")
	assert_eq(_slots(_panel._theirs)[0].corner, "20", "the price in the corner")
	_slots(_panel._theirs)[0].on_click.call(false)  # potion, 20
	_panel.show_trade(_state)
	assert_true(_slots(_panel._theirs)[0].selected, "on the table")
	assert_true(_panel._accept.disabled, "5 gold isn't enough")
	assert_string_contains(_panel._total.text, "Not enough gold")
	_slots(_panel._mine)[0].on_click.call(false)  # ring, sells for 20
	_panel.show_trade(_state)
	assert_false(_panel._accept.disabled)
	assert_eq(_panel._total.text, "An even swap.")
	_panel._accept.pressed.emit()
	assert_eq(_deals, [[[0], [0]]])


func test_their_own_stolen_goods_cant_be_offered() -> void:
	CrimeRules.mark_stolen(_state.get_entity(1), "Map", 3)
	_panel._shown_key = []
	_panel.show_trade(_state)
	assert_true(_slots(_panel._mine)[1].dimmed)
	assert_false(_slots(_panel._mine)[1].on_click.is_valid())


func test_closes_when_trading_stops_being_possible() -> void:
	EntityOps.place(_state, _state.get_entity(1), Vector3i(1, Y, 1))
	_panel.show_trade(_state)
	assert_false(_panel.visible)
