class_name TradePanel
extends PanelContainer
## Trading with a merchant (opened when their dialogue offers it), in the
## same item slots as the inventory: their goods on the left, your bag on the
## right, each with its price in the corner. Click items to put them on the
## table (gold border) or take them off again; the line below says what the
## deal costs, and Accept sends one TradeCommand. Hover an item for details.
## Esc closes it.

signal deal_requested(buy: Array[int], sell: Array[int])
signal closed

const COLUMNS := 6
const ROWS := 5

var buyer_id := -1
var trader_id := -1
var _title: Label
var _their_head: Label
var _my_head: Label
var _theirs: GridContainer
var _mine: GridContainer
var _details: Label
var _total: Label
var _accept: Button
var _buy: Array[int] = []
var _sell: Array[int] = []
var _shown_key := []
var _state: SimState
var _hovered: Array = []  # [side, index] or []


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiStyle.window_style(true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = UiStyle.title("")
	box.add_child(_title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	box.add_child(columns)
	_their_head = UiStyle.dim("")
	_theirs = _column(columns, _their_head)
	_my_head = UiStyle.dim("")
	_mine = _column(columns, _my_head)
	_details = Label.new()
	_details.custom_minimum_size = Vector2(0, 58)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 13)
	box.add_child(_details)
	_total = Label.new()
	box.add_child(_total)
	var row := HBoxContainer.new()
	box.add_child(row)
	_accept = UiStyle.button("Accept deal", func() -> void: deal_requested.emit(_buy.duplicate(), _sell.duplicate()))
	_accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_accept)
	row.add_child(UiStyle.button("Close  (Esc)", close))


func _column(parent: Control, head: Label) -> GridContainer:
	var column := VBoxContainer.new()
	parent.add_child(column)
	column.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (ItemSlot.SIZE + 4) + 4, ROWS * (ItemSlot.SIZE + 4))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	return grid


func open(p_buyer_id: int, p_trader_id: int) -> void:
	buyer_id = p_buyer_id
	trader_id = p_trader_id
	_buy.clear()
	_sell.clear()
	_shown_key = []
	_hovered = []
	visible = true
	_center.call_deferred()


func _center() -> void:
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).floor()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## After a deal went through: clear the table.
func dealt() -> void:
	_buy.clear()
	_sell.clear()
	_shown_key = []


func show_trade(state: SimState) -> void:
	if not visible:
		return
	_state = state
	var buyer := state.get_entity(buyer_id)
	var trader := state.get_entity(trader_id)
	if not TradeCommand.can_trade(state, buyer, trader):
		close()
		return
	var key := [buyer.inventory.duplicate(), trader.inventory.duplicate(), buyer.gold, trader.gold, _buy.duplicate(), _sell.duplicate(), trader.suspicious]
	if key == _shown_key:
		return
	_shown_key = key
	_title.text = "Trading with %s" % trader.name
	_their_head.text = "%s's goods   ·   %d gold" % [trader.name, trader.gold]
	_my_head.text = "%s's bag   ·   %d gold" % [buyer.name, buyer.gold]
	_fill(_theirs, "theirs", trader.inventory, _buy, func(item: String) -> int: return TradeCommand.price_of(trader, item, buyer),
			func(_item: String) -> bool: return false)
	_fill(_mine, "mine", buyer.inventory, _sell, func(item: String) -> int: return TradeCommand.offer_for(item, buyer),
			func(item: String) -> bool: return TradeCommand.refuses(trader, buyer, item))
	var pay := TradeCommand.balance(trader, buyer, _buy, _sell)
	if _buy.is_empty() and _sell.is_empty():
		_total.text = "Click items to put them on the table."
		_total.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	else:
		var short := ""
		if pay > 0 and buyer.gold < pay:
			short = "   Not enough gold."
		elif pay < 0 and trader.gold < -pay:
			short = "   They can't pay that much."
		_total.text = ("You pay %d gold." % pay if pay > 0 else "You receive %d gold." % -pay if pay < 0 else "An even swap.") + short
		_total.add_theme_color_override("font_color", UiStyle.BAD if short != "" else UiStyle.TEXT)
	_accept.disabled = not TradeCommand.new(buyer_id, trader_id, _buy, _sell).validate(state)
	_show_details()


## One side's slots: every item with its price; picked ones have a gold
## border, refused ones are greyed out. Always a row more than needed.
func _fill(grid: GridContainer, side: String, items: Array[String], picked: Array[int], price: Callable, refused: Callable) -> void:
	for child in grid.get_children():
		child.queue_free()
	var count := maxi(ceili(items.size() / float(COLUMNS)) + 1, ROWS) * COLUMNS
	for i in count:
		var slot := ItemSlot.new()
		var item := items[i] if i < items.size() else ""
		slot.selected = picked.has(i)
		slot.dimmed = item != "" and refused.call(item)
		slot.corner_color = UiStyle.ACCENT
		slot.show_item(item, "%d" % price.call(item) if item != "" else "")
		var index := i
		slot.on_hover = func(inside: bool) -> void:
			if inside:
				_hovered = [side, index]
			elif _hovered == [side, index]:
				_hovered = []
			_show_details()
		if item != "" and not slot.dimmed:
			slot.on_click = func(_right: bool) -> void:
				if picked.has(index):
					picked.erase(index)
				else:
					picked.append(index)
				_shown_key = []
				show_trade.call_deferred(_state)
		grid.add_child(slot)


func _show_details() -> void:
	if _state == null:
		return
	var buyer := _state.get_entity(buyer_id)
	var trader := _state.get_entity(trader_id)
	var item := ""
	var line := ""
	if _hovered.size() == 2:
		var mine: bool = _hovered[0] == "mine"
		var items := buyer.inventory if mine else trader.inventory
		var index: int = _hovered[1]
		if index < items.size():
			item = items[index]
			if mine and TradeCommand.refuses(trader, buyer, item):
				line = "They won't buy their own goods back."
			elif mine:
				line = "Sells for %d gold%s." % [TradeCommand.offer_for(item, buyer), " (money: full value)" if SimItems.has_property(item, "money") else ""]
			else:
				line = "Costs %d gold%s." % [TradeCommand.price_of(trader, item, buyer), " (they're wary of you: half again)" if trader.suspicious else ""]
	if item == "":
		_details.text = "Hover an item for details; click it to put it on the table."
	else:
		_details.text = ItemSlot.details(item) + "\n" + line


func handle_key(keycode: int) -> bool:
	if visible and keycode == KEY_ESCAPE:
		close()
		return true
	return false
