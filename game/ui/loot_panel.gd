class_name LootPanel
extends PanelContainer
## What's inside a chest or on a body the selected character opened, in the
## same item slots as the inventory: click an item to take it, or take
## everything (Space). Hover for details. Esc closes it. Warns when the
## things belong to townsfolk (taking them is theft).
##
## Pocket mode (open_pockets()): a thief with Thievery looks through someone's
## pockets and picks one item at a time; what is beyond the thief's Thievery
## is greyed out.

signal take_requested(index: int)
signal closed

const COLUMNS := 5
const ROWS := 2

var container_id := -1
## The thief in pocket mode (-1 = an ordinary container).
var thief_id := -1
var _title: Label
var _warning: Label
var _items: GridContainer
var _details: Label
var _shown: Array[String] = []
var _shown_warning := false
var _contents: Array[String] = []
var _pick_hint: Label
var _take_all: Button
var _thief: SimEntity


func _ready() -> void:
	visible = false
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_top = -140
	offset_right = -24
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_theme_stylebox_override("panel", UiStyle.window_style(true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = UiStyle.title("")
	box.add_child(_title)
	_warning = Label.new()
	_warning.text = "Not yours: taking is theft if seen."
	_warning.add_theme_color_override("font_color", UiStyle.WARNING)
	_warning.add_theme_font_size_override("font_size", UiStyle.SMALL)
	box.add_child(_warning)
	_pick_hint = Label.new()
	_pick_hint.add_theme_font_size_override("font_size", UiStyle.SMALL)
	_pick_hint.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	box.add_child(_pick_hint)
	_items = GridContainer.new()
	_items.columns = COLUMNS
	_items.add_theme_constant_override("h_separation", 4)
	_items.add_theme_constant_override("v_separation", 4)
	box.add_child(_items)
	_details = Label.new()
	_details.custom_minimum_size = Vector2(COLUMNS * (ItemSlot.SIZE + 4), 58)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 13)
	box.add_child(_details)
	var row := HBoxContainer.new()
	box.add_child(row)
	_take_all = UiStyle.button("Take all  (Space)", func() -> void: take_requested.emit(LootCommand.ALL))
	_take_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_take_all)
	row.add_child(UiStyle.button("Close  (Esc)", close))


func open(id: int) -> void:
	container_id = id
	thief_id = -1
	_shown = []
	visible = true


## Opens `victim`'s pockets for `thief` to pick from (Pickpocket with Thievery).
func open_pockets(victim: int, thief: int) -> void:
	container_id = victim
	thief_id = thief
	_shown = []
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	container_id = -1
	thief_id = -1
	closed.emit()


## Shows the container's contents (closes when it is gone or emptied).
func show_contents(state: SimState) -> void:
	if not visible:
		return
	var container := state.get_entity(container_id)
	_thief = state.get_entity(thief_id)
	var pockets := thief_id >= 0
	if container == null or (not pockets and not LootCommand.is_container(container)):
		close()
		return
	if pockets and (_thief == null or container.inventory.is_empty()
			or not CastCommand.new(thief_id, SimAbilities.Ability.PICKPOCKET, container.cell).validate(state)):
		close()  # emptied, walked away, spotted into a fight...
		return
	var theft := pockets or LootCommand.neutral_owner(state, container) != 0
	if container.inventory == _shown and theft == _shown_warning:
		return
	_shown = container.inventory.duplicate()
	_contents = _shown
	_shown_warning = theft
	_title.text = container.name if container.takes_turns() or container.is_alive() else "%s (broken)" % container.name
	if pockets:
		_title.text = "%s's pockets" % container.name
	_warning.text = "Whoever sees you reacts." if pockets else "Not yours: taking is theft if seen."
	_warning.visible = theft
	_pick_hint.visible = pockets
	if pockets:
		_pick_hint.text = "Thievery %d: you can pick %s." % [_thief.thievery,
				"anything" if _thief.thievery >= StatRules.PICK_ANY_RANK else "things worth up to %d gold" % (StatRules.PICK_VALUE_PER_RANK * _thief.thievery)]
	_take_all.visible = not pockets
	for child in _items.get_children():
		child.queue_free()
	var count := maxi(ceili(_contents.size() / float(COLUMNS)), ROWS) * COLUMNS
	for i in count:
		var slot := ItemSlot.new()
		var item := _contents[i] if i < _contents.size() else ""
		slot.dimmed = pockets and item != "" and not StatRules.can_pick(_thief, item)
		slot.show_item(item)
		var index := i
		slot.on_hover = func(inside: bool) -> void: _show_details(index if inside else -1)
		if item != "" and not slot.dimmed:
			slot.on_click = func(_right: bool) -> void: take_requested.emit(index)
		_items.add_child(slot)
	_show_details(-1)


func _show_details(index: int) -> void:
	if index >= 0 and index < _contents.size():
		var pickable := thief_id < 0 or (_thief != null and StatRules.can_pick(_thief, _contents[index]))
		_details.text = ItemSlot.details(_contents[index]) + ("\nClick to take it." if pickable else "\nToo valuable for your Thievery.")
	elif _contents.is_empty():
		_details.text = "Empty."
	else:
		_details.text = "Click an item to take it, or take everything."


## Space takes all, Esc closes. Returns true if the key was used.
func handle_key(keycode: int) -> bool:
	if not visible:
		return false
	if keycode == KEY_ESCAPE:
		close()
		return true
	if keycode == KEY_SPACE and thief_id < 0:
		take_requested.emit(LootCommand.ALL)
		return true
	return false
