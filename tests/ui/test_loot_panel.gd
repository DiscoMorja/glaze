extends GutTest
## The loot window: lists the container's items, asks to take one or all,
## warns about theft, and closes when the container is emptied.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y

var _panel: LootPanel
var _state: SimState
var _taken: Array = []


func before_each() -> void:
	_state = Fixtures.flat_state(Vector3i(12, 5, 12))
	_state.add_entity(SimArchetypes.make("trickster", "Cel", SimEntity.Faction.PLAYERS, Vector3i(5, Y, 5)))
	_state.add_entity(SimEntity.container("Chest", Vector3i(6, Y, 5), ["Gold", "Map"] as Array[String]))
	_panel = LootPanel.new()
	add_child_autofree(_panel)
	_taken.clear()
	_panel.take_requested.connect(func(index: int) -> void: _taken.append(index))
	_panel.open(2)
	_panel.show_contents(_state)


func _item_buttons() -> Array[Button]:
	var result: Array[Button] = []
	for child in _panel._items.get_children():
		if child is Button and not child.is_queued_for_deletion():
			result.append(child)
	return result


func test_lists_items_and_takes_the_clicked_one() -> void:
	var buttons := _item_buttons()
	assert_eq(buttons.size(), 2)
	assert_string_starts_with(buttons[1].text, "Map")
	buttons[1].pressed.emit()
	assert_eq(_taken, [1])


func test_space_takes_all_and_esc_closes() -> void:
	assert_true(_panel.handle_key(KEY_SPACE))
	assert_eq(_taken, [LootCommand.ALL])
	assert_true(_panel.handle_key(KEY_ESCAPE))
	assert_false(_panel.visible)
	assert_false(_panel.handle_key(KEY_SPACE), "closed: keys go to the game")


func test_closes_once_emptied() -> void:
	_state.apply_command(LootCommand.new(1, 2, LootCommand.ALL))
	_panel.show_contents(_state)
	assert_false(_panel.visible)


func test_warns_when_the_owners_are_neutral() -> void:
	assert_false(_panel._warning.visible)
	_state.get_entity(2).pack = 4
	var farmer := SimArchetypes.make("villager", "Farmer", SimEntity.Faction.NEUTRAL, Vector3i(1, Y, 1))
	farmer.pack = 4
	_state.add_entity(farmer)
	_panel.show_contents(_state)
	assert_true(_panel._warning.visible)
