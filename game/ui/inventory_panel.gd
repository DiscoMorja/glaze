class_name InventoryPanel
extends PanelContainer
## The selected character's items as a grid of slots, one item per slot (I
## toggles it). The grid always has a free row, so there is always room.
## Drag an item onto another slot to move it there (onto an empty slot: to the
## end), or onto a party member's card to give it to them (outside combat).
## Hover a slot for its details; click it to select it and use the give
## buttons, or Use / Equip it. Stolen items have a red border. Above the bag:
## the character sheet (level, XP, gold, what they wear, points to spend, and
## Rest). Footer: item count, total value and weight.

signal give_requested(from_id: int, to_id: int, index: int)
signal sort_requested(entity_id: int, from_index: int, to_index: int)
signal use_requested(entity_id: int, index: int)
## index EquipCommand.UNEQUIP takes off what is worn in `slot`.
signal equip_requested(entity_id: int, index: int, slot: String)
signal spend_requested(entity_id: int, stat: String)
signal rest_requested(entity_id: int)

## What a dragged item carries (PartyBar cards accept it too).
const DRAG_KIND := "glaze_item"

const COLUMNS := 6
const SLOT_SIZE := 54
## Rows shown before the grid scrolls.
const VISIBLE_ROWS := 2
const KIND_COLORS := {
	"valuable": Color(0.55, 0.45, 0.15),
	"food": Color(0.42, 0.3, 0.18),
	"key": Color(0.35, 0.38, 0.45),
	"document": Color(0.45, 0.42, 0.32),
	"misc": Color(0.3, 0.3, 0.33),
	"potion": Color(0.45, 0.2, 0.3),
	"weapon": Color(0.38, 0.4, 0.45),
	"armor": Color(0.3, 0.38, 0.32),
}
const STOLEN_BORDER := Color(1.0, 0.35, 0.3)
const SELECTED_BORDER := Color(1.0, 0.85, 0.3)

var _title: Label
var _sheet: Label
var _worn_row: HBoxContainer
var _points_row: HBoxContainer
var _grid: GridContainer
var _details: Label
var _give_row: HBoxContainer
var _footer: Label

var _owner: SimEntity
var _party: Array[SimEntity] = []
var _can_give := false
## This player's character: its items can be rearranged.
var _can_sort := false
var _selected := -1
var _hovered := -1
var _shown_key := []


func _ready() -> void:
	visible = false
	anchor_left = 1.0
	anchor_right = 1.0
	# Top right, under the log's first lines, clear of the bars at the bottom.
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = 64
	offset_right = -12
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.94)
	style.border_color = Color(0.35, 0.38, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	_sheet = Label.new()
	_sheet.add_theme_font_size_override("font_size", 13)
	_sheet.add_theme_color_override("font_color", Color(0.8, 0.82, 0.86))
	box.add_child(_sheet)
	_worn_row = HBoxContainer.new()
	box.add_child(_worn_row)
	_points_row = HBoxContainer.new()
	box.add_child(_points_row)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLUMNS * (SLOT_SIZE + 4), VISIBLE_ROWS * (SLOT_SIZE + 4))
	box.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)
	_details = Label.new()
	_details.custom_minimum_size = Vector2(COLUMNS * (SLOT_SIZE + 4), 40)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 13)
	box.add_child(_details)
	_give_row = HBoxContainer.new()
	box.add_child(_give_row)
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 12)
	_footer.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
	box.add_child(_footer)


## Shows `owner`'s items. `party`: everyone they can be given to; can_give:
## outside combat and the owner is this player's; can_sort: the owner is this
## player's.
func show_for(owner: SimEntity, party: Array[SimEntity], can_give: bool, can_sort: bool = false) -> void:
	if not visible or owner == null:
		return
	var names: Array[String] = []
	for p in party:
		names.append(p.name)
	var key := [owner.id, owner.inventory.duplicate(), owner.stolen.duplicate(), names, can_give, can_sort,
			owner.gold, owner.xp, owner.level, owner.points, owner.weapon, owner.armor_item, owner.hp, owner.max_hp]
	if key == _shown_key:
		return
	if _owner == null or owner.id != _owner.id or owner.inventory.size() <= _selected:
		_selected = -1
	_shown_key = key
	_owner = owner
	_party = party
	_can_give = can_give
	_can_sort = can_sort
	_rebuild()


func toggle() -> void:
	visible = not visible
	_shown_key = []
	_selected = -1


func _rebuild() -> void:
	_title.text = "%s's inventory" % _owner.name
	_show_sheet()
	for child in _grid.get_children():
		child.queue_free()
	var items := _owner.inventory
	# Always a free row at the end: the bag never fills up.
	var slots := (ceili(items.size() / float(COLUMNS)) + 1) * COLUMNS
	for i in slots:
		_grid.add_child(_make_slot(i, items[i] if i < items.size() else ""))
	_footer.text = "%d items   ·   %d gold   ·   %s" % [
		items.size(), SimItems.total_value(items), SimItems.weight_text(SimItems.total_weight(items))]
	_show_details()
	_show_give_buttons()


func _make_slot(index: int, item: String) -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.set_border_width_all(2)
	if item == "":
		style.bg_color = Color(0.13, 0.14, 0.16)
		style.border_color = Color(0.2, 0.21, 0.24)
	else:
		style.bg_color = KIND_COLORS.get(SimItems.kind_of(item), KIND_COLORS.misc)
		style.border_color = Color(0.5, 0.52, 0.56)
		if CrimeRules.is_stolen(_owner, item):
			style.border_color = STOLEN_BORDER
		if index == _selected:
			style.border_color = SELECTED_BORDER
	slot.add_theme_stylebox_override("panel", style)
	slot.set_drag_forwarding(
		func(_at: Vector2) -> Variant: return _drag_from(slot, index, item),
		func(_at: Vector2, data: Variant) -> bool: return _accepts(data),
		func(_at: Vector2, data: Variant) -> void: _drop_on(index, data))
	if item != "":
		var label := Label.new()
		label.text = item
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)
		slot.mouse_entered.connect(func() -> void:
			_hovered = index
			_show_details())
		slot.mouse_exited.connect(func() -> void:
			if _hovered == index:
				_hovered = -1
				_show_details())
		slot.gui_input.connect(func(event: InputEvent) -> void:
			# Select on release: a press may be the start of a drag.
			if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_selected = -1 if _selected == index else index
				_rebuild()
				slot.accept_event())
	return slot


func _drag_from(slot: Control, index: int, item: String) -> Variant:
	if item == "" or not (_can_sort or _can_give):
		return null
	var preview := Label.new()
	preview.text = item
	preview.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	preview.add_theme_constant_override("outline_size", 4)
	preview.add_theme_color_override("font_outline_color", Color.BLACK)
	slot.set_drag_preview(preview)
	return {"kind": DRAG_KIND, "from_id": _owner.id, "index": index, "item": item}


func _accepts(data: Variant) -> bool:
	return _can_sort and data is Dictionary and data.get("kind") == DRAG_KIND and data.from_id == _owner.id


## Dropped on slot `index`: move the item there (past the last item: to the end).
func _drop_on(index: int, data: Variant) -> void:
	var to := mini(index, _owner.inventory.size() - 1)
	if to != data.index:
		_selected = -1
		sort_requested.emit(_owner.id, data.index, to)


## Details of the hovered slot (else the selected one). Hovering only changes
## this text, so the give buttons stay put under the mouse.
func _show_details() -> void:
	var index := _hovered if _hovered >= 0 else _selected
	var items := _owner.inventory
	if index < 0 or index >= items.size():
		_details.text = "Hover an item for details; click it to select."
	else:
		var item := items[index]
		var info := SimItems.info(item)
		var lines: Array[String] = ["%s   ·   %d gold   ·   %s" % [item, info.value, SimItems.weight_text(info.weight)]]
		if info.blurb != "":
			lines.append(info.blurb)
		if CrimeRules.is_stolen(_owner, item):
			lines.append("Stolen — its owners will recognize it.")
		_details.text = "\n".join(lines)


## Level, XP, gold; what they wear (take off); points to spend; Rest.
func _show_sheet() -> void:
	var e := _owner
	var next := ProgressionRules.xp_for_level(e.level + 1)
	_sheet.text = "Level %d   ·   %d / %d XP   ·   %d gold   ·   HP %d/%d   ·   %d damage%s" % [
		e.level, e.xp, next, e.gold, e.hp, e.max_hp, e.attack_damage(),
		"   ·   armour %d" % e.armor if e.armor > 0 else ""]
	for row: HBoxContainer in [_worn_row, _points_row]:
		for child in row.get_children():
			child.queue_free()
	for slot: String in ["weapon", "armor"]:
		var worn := EquipCommand.worn(e, slot)
		var label := Label.new()
		label.text = "%s: %s" % ["Weapon" if slot == "weapon" else "Armour", worn if worn != "" else "—"]
		label.add_theme_font_size_override("font_size", 13)
		_worn_row.add_child(label)
		if worn != "" and _can_give:
			_worn_row.add_child(_button("Take off", func() -> void: equip_requested.emit(e.id, EquipCommand.UNEQUIP, slot)))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(12, 0)
		_worn_row.add_child(gap)
	if _can_give:
		var push := Control.new()
		push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_worn_row.add_child(push)
		_worn_row.add_child(_button("Rest", func() -> void: rest_requested.emit(e.id), "Heal the party with a bedroll (no enemies near)"))
	if e.points > 0 and _can_sort:
		var label := Label.new()
		label.text = "%d point%s:" % [e.points, "s" if e.points > 1 else ""]
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		_points_row.add_child(label)
		for stat: String in ProgressionRules.STATS:
			_points_row.add_child(_button(stat.capitalize(), func() -> void: spend_requested.emit(e.id, stat), ProgressionRules.STATS[stat]))


func _button(text: String, on_press: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	return button


## Use / Equip and give buttons for the selected slot (rebuilt when the
## selection changes).
func _show_give_buttons() -> void:
	var items := _owner.inventory
	for child in _give_row.get_children():
		child.queue_free()
	if _selected < 0 or _selected >= items.size():
		return
	var item := items[_selected]
	var index := _selected
	var owner_id := _owner.id
	if _can_sort and SimItems.is_usable(item):
		_give_row.add_child(_button("Use", func() -> void:
			_selected = -1
			use_requested.emit(owner_id, index)))
	if _can_give and SimItems.slot_of(item) != "":
		_give_row.add_child(_button("Equip", func() -> void:
			_selected = -1
			equip_requested.emit(owner_id, index, SimItems.slot_of(item))))
	if not _can_give:
		var note := Label.new()
		note.text = "Items are passed around and worn outside combat."
		note.add_theme_font_size_override("font_size", 12)
		_give_row.add_child(note)
		return
	var give_label := Label.new()
	give_label.text = "Give to:"
	_give_row.add_child(give_label)
	for p in _party:
		if p.id == _owner.id:
			continue
		var give := Button.new()
		give.text = p.name
		give.focus_mode = Control.FOCUS_NONE
		var to_id := p.id
		var from_id := _owner.id
		var index_to_give := _selected
		give.pressed.connect(func() -> void:
			_selected = -1
			give_requested.emit(from_id, to_id, index_to_give))
		_give_row.add_child(give)
