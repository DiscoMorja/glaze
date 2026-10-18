class_name LootPanel
extends PanelContainer
## What's inside a chest or on a body the selected character opened: click an
## item to take it, or take everything (Space). Esc closes it. Warns when the
## things belong to townsfolk (taking them is theft).

signal take_requested(index: int)
signal closed

var container_id := -1
var _title: Label
var _warning: Label
var _items: VBoxContainer
var _shown: Array[String] = []
var _shown_warning := false


func _ready() -> void:
	visible = false
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -300
	offset_right = -24
	offset_top = -120
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(276, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.95)
	style.border_color = Color(0.5, 0.45, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	box.add_child(_title)
	_warning = Label.new()
	_warning.text = "Not yours: taking is theft if seen."
	_warning.add_theme_color_override("font_color", Color(1.0, 0.65, 0.3))
	_warning.add_theme_font_size_override("font_size", 12)
	box.add_child(_warning)
	_items = VBoxContainer.new()
	box.add_child(_items)
	var row := HBoxContainer.new()
	box.add_child(row)
	var take_all := Button.new()
	take_all.text = "Take all  (Space)"
	take_all.focus_mode = Control.FOCUS_NONE
	take_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_all.pressed.connect(func() -> void: take_requested.emit(LootCommand.ALL))
	row.add_child(take_all)
	var close_button := Button.new()
	close_button.text = "Close  (Esc)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	row.add_child(close_button)


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
	_shown_warning = theft
	_title.text = container.name if container.takes_turns() or container.is_alive() else "%s (broken)" % container.name
	_warning.visible = theft
	for child in _items.get_children():
		child.queue_free()
	if container.inventory.is_empty():
		var empty := Label.new()
		empty.text = "Empty."
		_items.add_child(empty)
	for i in container.inventory.size():
		var item := container.inventory[i]
		var button := Button.new()
		button.text = "%s   (%d gold, %s)" % [item, SimItems.value_of(item), SimItems.weight_text(SimItems.weight_of(item))]
		button.tooltip_text = SimItems.info(item).blurb
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: take_requested.emit(i))
		_items.add_child(button)


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
