class_name LootPanel
extends PanelContainer
## What's inside a chest or on a body the selected character opened, in the
## same item slots as the inventory: click an item to take it, or take
## everything (Space). Hover for details. Esc closes it. Warns when the
## things belong to townsfolk (taking them is theft).

signal take_requested(index: int)
signal closed

const COLUMNS := 5
const ROWS := 2

var container_id := -1
var _title: Label
var _warning: Label
var _items: GridContainer
var _details: Label
var _shown: Array[String] = []
var _shown_warning := false
var _contents: Array[String] = []


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
	var take_all := UiStyle.button("Take all  (Space)", func() -> void: take_requested.emit(LootCommand.ALL))
	take_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(take_all)
	row.add_child(UiStyle.button("Close  (Esc)", close))


func open(id: int) -> void:
	container_id = id
	_shown = []
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	container_id = -1
	closed.emit()


## Shows the container's contents (closes when it is gone or emptied).
func show_contents(state: SimState) -> void:
	if not visible:
		return
	var container := state.get_entity(container_id)
	if container == null or not LootCommand.is_container(container):
		close()
		return
	var theft := LootCommand.neutral_owner(state, container) != 0
	if container.inventory == _shown and theft == _shown_warning:
		return
	_shown = container.inventory.duplicate()
	_contents = _shown
	_shown_warning = theft
	_title.text = container.name if container.takes_turns() or container.is_alive() else "%s (broken)" % container.name
	_warning.visible = theft
	for child in _items.get_children():
		child.queue_free()
	var count := maxi(ceili(_contents.size() / float(COLUMNS)), ROWS) * COLUMNS
	for i in count:
		var slot := ItemSlot.new()
		var item := _contents[i] if i < _contents.size() else ""
		slot.show_item(item)
		var index := i
		slot.on_hover = func(inside: bool) -> void: _show_details(index if inside else -1)
		if item != "":
			slot.on_click = func(_right: bool) -> void: take_requested.emit(index)
		_items.add_child(slot)
	_show_details(-1)


func _show_details(index: int) -> void:
	if index >= 0 and index < _contents.size():
		_details.text = ItemSlot.details(_contents[index]) + "\nClick to take it."
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
	if keycode == KEY_SPACE:
		take_requested.emit(LootCommand.ALL)
		return true
	return false
