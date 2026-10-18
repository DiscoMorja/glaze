class_name TradePanel
extends PanelContainer
## Trading with a merchant (opened when their dialogue offers it). Two
## columns: their goods and your bag; click items to put them on the table,
## the bottom line shows what the deal costs, Accept sends one TradeCommand.
## Esc closes it.

signal deal_requested(buy: Array[int], sell: Array[int])
signal closed

const PICKED := Color(1.0, 0.85, 0.3)

var buyer_id := -1
var trader_id := -1
var _title: Label
var _theirs: VBoxContainer
var _mine: VBoxContainer
var _total: Label
var _accept: Button
var _buy: Array[int] = []
var _sell: Array[int] = []
var _shown_key := []
var _state: SimState


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(620, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.97)
	style.border_color = Color(0.5, 0.45, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	box.add_child(columns)
	_theirs = _column(columns)
	_mine = _column(columns)
	_total = Label.new()
	box.add_child(_total)
	var row := HBoxContainer.new()
	box.add_child(row)
	_accept = Button.new()
	_accept.text = "Accept deal"
	_accept.focus_mode = Control.FOCUS_NONE
	_accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accept.pressed.connect(func() -> void: deal_requested.emit(_buy.duplicate(), _sell.duplicate()))
	row.add_child(_accept)
	var close_button := Button.new()
	close_button.text = "Close  (Esc)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	row.add_child(close_button)


func _column(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(296, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column


func open(p_buyer_id: int, p_trader_id: int) -> void:
	buyer_id = p_buyer_id
	trader_id = p_trader_id
	_buy.clear()
	_sell.clear()
	_shown_key = []
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
	_title.text = "Trading with %s   (they have %d gold)" % [trader.name, trader.gold]
	_fill(_theirs, "%s's goods" % trader.name, trader.inventory, _buy, func(item: String) -> String:
		return "%d" % TradeCommand.price_of(trader, item), func(_item: String) -> String: return "")
	_fill(_mine, "%s's bag (%d gold)" % [buyer.name, buyer.gold], buyer.inventory, _sell, func(item: String) -> String:
		return "%d" % TradeCommand.offer_for(item), func(item: String) -> String:
		return "They won't buy their own goods back" if TradeCommand.refuses(trader, buyer, item) else "")
	var pay := TradeCommand.balance(trader, buyer, _buy, _sell)
	var deal := TradeCommand.new(buyer_id, trader_id, _buy, _sell)
	var ok := deal.validate(state)
	if _buy.is_empty() and _sell.is_empty():
		_total.text = "Click items to put them on the table."
	elif pay > 0:
		_total.text = "You pay %d gold.%s" % [pay, "" if buyer.gold >= pay else "  Not enough gold."]
	elif pay < 0:
		_total.text = "You receive %d gold.%s" % [-pay, "" if trader.gold >= -pay else "  They can't pay that much."]
	else:
		_total.text = "An even swap."
	_accept.disabled = not ok


## One column: a header, then a toggle button per item with its price.
func _fill(column: VBoxContainer, header: String, items: Array[String], picked: Array[int], price: Callable, refusal: Callable) -> void:
	for child in column.get_children():
		child.queue_free()
	var head := Label.new()
	head.text = header
	head.add_theme_color_override("font_color", Color(0.75, 0.77, 0.82))
	column.add_child(head)
	for i in items.size():
		var item := items[i]
		var button := Button.new()
		var why: String = refusal.call(item)
		button.text = "%s   %s gold" % [item, price.call(item)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = why if why != "" else SimItems.info(item).blurb
		button.disabled = why != ""
		if picked.has(i):
			button.add_theme_color_override("font_color", PICKED)
			button.text = "» " + button.text
		var index := i
		button.pressed.connect(func() -> void:
			if picked.has(index):
				picked.erase(index)
			else:
				picked.append(index)
			_shown_key = []
			show_trade.call_deferred(_state))
		column.add_child(button)


func handle_key(keycode: int) -> bool:
	if visible and keycode == KEY_ESCAPE:
		close()
		return true
	return false
