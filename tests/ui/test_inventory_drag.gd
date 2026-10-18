extends GutTest
## Inventory drag and drop: the data a dragged slot carries, dropping on
## another slot (sort) and on a party member's card (give).

const Y := 1

var _panel: InventoryPanel
var _owner: SimEntity
var _other: SimEntity
var _sorted: Array = []
var _given: Array = []


func before_each() -> void:
	_panel = InventoryPanel.new()
	add_child_autofree(_panel)
	_owner = SimEntity.character("Ari", SimEntity.Faction.PLAYERS, Vector3i(1, Y, 1), 20)
	_owner.id = 1
	_owner.inventory.assign(["Gold", "Bread", "Map"])
	_other = SimEntity.character("Bram", SimEntity.Faction.PLAYERS, Vector3i(2, Y, 1), 16)
	_other.id = 2
	_sorted.clear()
	_given.clear()
	_panel.sort_requested.connect(func(id: int, from: int, to: int) -> void: _sorted.append([id, from, to]))
	_panel.give_requested.connect(func(from_id: int, to_id: int, index: int) -> void: _given.append([from_id, to_id, index]))
	_panel.toggle()
	var party: Array[SimEntity] = [_owner, _other]
	_panel.show_for(_owner, party, true, true)


func _data(index: int) -> Dictionary:
	return {"kind": InventoryPanel.DRAG_KIND, "from_id": _owner.id, "index": index, "item": _owner.inventory[index]}


func test_dropping_on_another_slot_sorts() -> void:
	assert_true(_panel._accepts(_data(0)))
	_panel._drop_on(2, _data(0))
	assert_eq(_sorted, [[1, 0, 2]])


func test_dropping_on_an_empty_slot_moves_to_the_end() -> void:
	_panel._drop_on(9, _data(0))
	assert_eq(_sorted, [[1, 0, 2]])


func test_dropping_on_its_own_slot_does_nothing() -> void:
	_panel._drop_on(1, _data(1))
	assert_eq(_sorted, [])


func test_partners_items_cant_be_sorted() -> void:
	var party: Array[SimEntity] = [_owner, _other]
	_panel.show_for(_owner, party, false, false)
	assert_false(_panel._accepts(_data(0)))


func test_dropping_on_a_party_card_gives() -> void:
	var bar := PartyBar.new()
	add_child_autofree(bar)
	var dropped: Array = []
	bar.item_dropped.connect(func(to_id: int, from_id: int, index: int) -> void: dropped.append([to_id, from_id, index]))
	var party: Array[SimEntity] = [_owner, _other]
	bar.update_party(party, 1, {}, 0, false)
	var bram_card: Control = bar._cards[2]
	assert_true(bram_card._can_drop_data(Vector2.ZERO, _data(1)))
	assert_false(bar._cards[1]._can_drop_data(Vector2.ZERO, _data(1)), "not onto its own card")
	bram_card._drop_data(Vector2.ZERO, _data(1))
	assert_eq(dropped, [[2, 1, 1]])
