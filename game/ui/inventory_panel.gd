class_name InventoryPanel
extends PanelContainer
## The selected character's sheet (I toggles it): the paperdoll on the left
## (eleven equipment slots around a figure), the bag on the right (one item
## per slot, always a free row), and their level, gold and stats on top.
##
## Drag an item onto another bag slot to move it, onto a paperdoll slot to
## wear it, onto a party frame to give it away, or onto the action bar. Drag
## a worn item into the bag to take it off. Right-click: wear or use it (worn:
## take it off). Click to select it and use the buttons below. Hover anything
## for details. Wearing and passing items around work outside combat.

signal give_requested(from_id: int, to_id: int, index: int)
signal sort_requested(entity_id: int, from_index: int, to_index: int)
signal use_requested(entity_id: int, index: int)
## index EquipCommand.UNEQUIP takes off what is worn in `slot`; slot "" =
## the item's own slot.
signal equip_requested(entity_id: int, index: int, slot: String)
signal spend_requested(entity_id: int, stat: String)
signal rest_requested(entity_id: int)

## What a dragged bag item carries (party frames and action-bar slots accept it too).
const DRAG_KIND := "glaze_item"
## What a dragged worn item carries.
const WORN_KIND := "glaze_worn"

const COLUMNS := 6
const SLOT_SIZE := 52.0
const GAP := 6.0
## Bag rows shown before it scrolls.
const VISIBLE_ROWS := 6
const KIND_COLORS := {
	"valuable": Color(0.4, 0.33, 0.12),
	"food": Color(0.32, 0.22, 0.13),
	"key": Color(0.25, 0.28, 0.34),
	"document": Color(0.34, 0.32, 0.24),
	"misc": Color(0.22, 0.22, 0.25),
	"potion": Color(0.34, 0.15, 0.22),
	"weapon": Color(0.27, 0.29, 0.33),
	"armor": Color(0.22, 0.28, 0.23),
	"trinket": Color(0.3, 0.22, 0.36),
}
const STOLEN_BORDER := Color(1.0, 0.35, 0.3)
const SELECTED_BORDER := Color(1.0, 0.85, 0.3)
const HOVER_BORDER := Color(0.8, 0.82, 0.88)
const IDLE_BORDER := Color(0.3, 0.32, 0.36)
## Paperdoll slot -> position in slot units (columns: 0 left, 1-2 figure, 3 right).
const DOLL := {
	"head": Vector2(0, 0), "neck": Vector2(0, 1), "body": Vector2(0, 2),
	"waist": Vector2(0, 3), "legs": Vector2(0, 4), "feet": Vector2(0, 5),
	"hands": Vector2(3, 0), "ring1": Vector2(3, 1), "ring2": Vector2(3, 2),
	"main_hand": Vector2(1, 5), "off_hand": Vector2(2, 5),
}

var _title: Label
var _sheet: Label
var _points_row: HBoxContainer
var _doll: Control
var _doll_slots := {}  # slot name -> _ItemSlot
var _grid: GridContainer
var _details: Label
var _give_row: HBoxContainer
var _footer: Label
var _rest: Button

var _owner: SimEntity
var _party: Array[SimEntity] = []
var _can_give := false
## This player's character: its items can be rearranged.
var _can_sort := false
var _selected := -1
## What the mouse is over: ["bag", index] or ["worn", slot], or [].
var _hovered: Array = []
var _shown_key := []


func _ready() -> void:
	visible = false
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = 48
	offset_right = -16
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.95)
	style.border_color = Color(0.35, 0.38, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_rest = _button("Rest", func() -> void: rest_requested.emit(_owner.id), "Heal the party with a bedroll (no enemies near)")
	top.add_child(_rest)
	_sheet = Label.new()
	_sheet.add_theme_font_size_override("font_size", 13)
	_sheet.add_theme_color_override("font_color", Color(0.8, 0.82, 0.86))
	box.add_child(_sheet)
	_points_row = HBoxContainer.new()
	box.add_child(_points_row)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	box.add_child(columns)
	_doll = Control.new()
	_doll.custom_minimum_size = Vector2(4 * SLOT_SIZE + 3 * GAP, 6 * SLOT_SIZE + 5 * GAP)
	columns.add_child(_doll)
	var figure_back := Panel.new()
	var figure_style := StyleBoxFlat.new()
	figure_style.bg_color = Color(0.11, 0.12, 0.14)
	figure_style.set_corner_radius_all(6)
	figure_back.add_theme_stylebox_override("panel", figure_style)
	figure_back.position = Vector2(SLOT_SIZE + GAP, 0)
	figure_back.size = Vector2(2 * SLOT_SIZE + GAP, 5 * SLOT_SIZE + 4 * GAP)
	figure_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doll.add_child(figure_back)
	var figure := TextureRect.new()
	figure.texture = GameIcons.portrait()
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.set_anchors_preset(Control.PRESET_FULL_RECT)
	figure.modulate = Color(1, 1, 1, 0.3)
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	figure_back.add_child(figure)
	for slot: String in DOLL:
		var cell: Vector2 = DOLL[slot]
		var item_slot := _ItemSlot.new(self, "worn", slot)
		item_slot.position = cell * (SLOT_SIZE + GAP)
		_doll.add_child(item_slot)
		_doll_slots[slot] = item_slot

	var bag := VBoxContainer.new()
	columns.add_child(bag)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(COLUMNS * (SLOT_SIZE + 4) + 4, VISIBLE_ROWS * (SLOT_SIZE + 4))
	bag.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 12)
	_footer.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
	bag.add_child(_footer)

	_details = Label.new()
	_details.custom_minimum_size = Vector2(0, 58)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 13)
	box.add_child(_details)
	_give_row = HBoxContainer.new()
	box.add_child(_give_row)


## Shows `owner`'s things. `party`: everyone they can be given to; can_give:
## outside combat and the owner is this player's; can_sort: the owner is this
## player's.
func show_for(owner: SimEntity, party: Array[SimEntity], can_give: bool, can_sort: bool = false) -> void:
	if not visible or owner == null:
		return
	var names: Array[String] = []
	for p in party:
		names.append(p.name)
	var key := [owner.id, owner.inventory.duplicate(), owner.stolen.duplicate(), owner.worn.duplicate(), owner.weapon, names,
			can_give, can_sort, owner.gold, owner.xp, owner.level, owner.points, owner.hp, owner.max_hp]
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
	_title.text = _owner.name
	_rest.visible = _can_give
	_show_sheet()
	for slot: String in _doll_slots:
		_doll_slots[slot].show_item(EquipRules.worn(_owner, slot))
	for child in _grid.get_children():
		child.queue_free()
	var items := _owner.inventory
	# Always a free row, and the visible rows filled.
	var count := maxi(ceili(items.size() / float(COLUMNS)) + 1, VISIBLE_ROWS) * COLUMNS
	for i in count:
		var item_slot := _ItemSlot.new(self, "bag", i)
		item_slot.show_item(items[i] if i < items.size() else "")
		_grid.add_child(item_slot)
	_footer.text = "%d items   ·   %d gold worth   ·   %s" % [
		items.size(), SimItems.total_value(items), SimItems.weight_text(SimItems.total_weight(items))]
	_show_details()
	_show_give_buttons()


func _show_sheet() -> void:
	var e := _owner
	var role := SimArchetypes.title(e.archetype)
	var next := ProgressionRules.xp_for_level(e.level + 1)
	_sheet.text = "%sLevel %d   ·   %d / %d XP   ·   %d gold\nHP %d/%d   ·   %d damage   ·   armour %d   ·   power %d" % [
		role + "   ·   " if role != "" else "", e.level, e.xp, next, e.gold,
		e.hp, e.max_hp, e.attack_damage(), e.armor, e.spell_power()]
	for child in _points_row.get_children():
		child.queue_free()
	if e.points > 0 and _can_sort:
		var label := Label.new()
		label.text = "%d point%s to spend:" % [e.points, "s" if e.points > 1 else ""]
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


## "Main hand · 5 damage · two-handed", "Head · armour 1 · +2 max HP"...
static func stats_text(item: String) -> String:
	var parts: Array[String] = []
	var slot := SimItems.slot_of(item)
	if slot != "":
		parts.append("Ring" if slot == "ring" else EquipRules.SLOT_NAMES.get(slot, slot))
	var damage := SimItems.amount(item, "damage")
	if damage > 0:
		parts.append(("%d damage" if slot == EquipRules.MAIN else "+%d damage") % damage)
	if SimItems.has_property(item, "two_handed"):
		parts.append("two-handed")
	if SimItems.amount(item, "armor") > 0:
		parts.append("armour %d" % SimItems.amount(item, "armor"))
	if SimItems.amount(item, "power") > 0:
		parts.append("+%d power" % SimItems.amount(item, "power"))
	if SimItems.amount(item, "max_hp") > 0:
		parts.append("+%d max HP" % SimItems.amount(item, "max_hp"))
	if SimItems.amount(item, "heal") > 0:
		parts.append("heals %d" % SimItems.amount(item, "heal"))
	return "   ·   ".join(parts)


## Details of the hovered item (else the selected one). Hovering only changes
## this text, so the buttons stay put under the mouse.
func _show_details() -> void:
	var item := ""
	var worn_slot := ""
	if _hovered.size() == 2 and _hovered[0] == "worn":
		worn_slot = _hovered[1]
		item = EquipRules.worn(_owner, worn_slot)
	else:
		var index: int = _hovered[1] if _hovered.size() == 2 else _selected
		if index >= 0 and index < _owner.inventory.size():
			item = _owner.inventory[index]
	if item == "":
		if worn_slot != "":
			_details.text = "%s: empty. Drag something here to wear it." % EquipRules.SLOT_NAMES[worn_slot]
		else:
			_details.text = "Hover an item for details. Right-click to wear or use it; drag it to move, wear, give or put on the action bar."
		return
	var info := SimItems.info(item)
	var lines: Array[String] = ["%s   ·   %d gold   ·   %s" % [item, info.value, SimItems.weight_text(info.weight)]]
	var stats := stats_text(item)
	if stats != "":
		lines.append(stats)
	if info.blurb != "":
		lines.append(info.blurb)
	if CrimeRules.is_stolen(_owner, item):
		lines.append("Stolen — its owners will recognize it.")
	_details.text = "\n".join(lines)


## Use / Wear and give buttons for the selected bag item (rebuilt when the
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
		_give_row.add_child(_button("Wear", func() -> void:
			_selected = -1
			equip_requested.emit(owner_id, index, "")))
	if not _can_give:
		var note := Label.new()
		note.text = "Items are passed around and worn outside combat."
		note.add_theme_font_size_override("font_size", 12)
		_give_row.add_child(note)
		return
	var give_label := Label.new()
	give_label.text = "  Give to:"
	_give_row.add_child(give_label)
	for p in _party:
		if p.id == owner_id:
			continue
		var to_id := p.id
		_give_row.add_child(_button(p.name, func() -> void:
			_selected = -1
			give_requested.emit(owner_id, to_id, index)))


# --- Slots: dragging, dropping, clicking -----------------------------------------

func _drag_from(where: String, key: Variant, source: Control) -> Variant:
	var item := _item_at(where, key)
	if item == "" or not (_can_sort or _can_give):
		return null
	var icon := GameIcons.for_item(item)
	if icon != null:
		var preview := TextureRect.new()
		preview.texture = icon
		preview.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.modulate.a = 0.85
		source.set_drag_preview(preview)
	else:
		var label := Label.new()
		label.text = item
		source.set_drag_preview(label)
	if where == "worn":
		return {"kind": WORN_KIND, "from_id": _owner.id, "slot": key, "item": item}
	return {"kind": DRAG_KIND, "from_id": _owner.id, "index": key, "item": item}


func _item_at(where: String, key: Variant) -> String:
	if _owner == null:
		return ""
	if where == "worn":
		return EquipRules.worn(_owner, key)
	var index: int = key
	return _owner.inventory[index] if index < _owner.inventory.size() else ""


## A bag slot accepts this player's bag items (sort) and worn items (take off).
func _accepts(data: Variant) -> bool:
	if not data is Dictionary or _owner == null or data.get("from_id") != _owner.id:
		return false
	if data.get("kind") == DRAG_KIND:
		return _can_sort
	return data.get("kind") == WORN_KIND and _can_give


## Dropped on bag slot `index`: move the item there (past the last: to the end),
## or take a worn item off.
func _drop_on(index: int, data: Variant) -> void:
	if data.kind == WORN_KIND:
		equip_requested.emit(_owner.id, EquipCommand.UNEQUIP, data.slot)
		return
	var to := mini(index, _owner.inventory.size() - 1)
	if to != data.index:
		_selected = -1
		sort_requested.emit(_owner.id, data.index, to)


## A paperdoll slot accepts bag items that fit it.
func _accepts_worn(slot: String, data: Variant) -> bool:
	return (_can_give and data is Dictionary and data.get("kind") == DRAG_KIND and _owner != null
			and data.get("from_id") == _owner.id and EquipRules.fits(slot, data.get("item", "")))


func _drop_on_worn(slot: String, data: Variant) -> void:
	_selected = -1
	equip_requested.emit(_owner.id, data.index, slot)


func _clicked(where: String, key: Variant, right: bool) -> void:
	var item := _item_at(where, key)
	if right:
		if item == "" or not _can_sort:
			return
		if where == "worn":
			if _can_give:
				equip_requested.emit(_owner.id, EquipCommand.UNEQUIP, key)
		elif SimItems.slot_of(item) != "" and _can_give:
			equip_requested.emit(_owner.id, key, "")
		elif SimItems.is_usable(item):
			use_requested.emit(_owner.id, key)
		return
	if where == "bag" and item != "":
		_selected = -1 if _selected == key else key
		_rebuild()


func _hover(where: String, key: Variant, inside: bool) -> void:
	if _owner == null:
		return
	if inside:
		_hovered = [where, key]
	elif _hovered == [where, key]:
		_hovered = []
	_show_details()


func _is_selected(where: String, key: Variant) -> bool:
	return where == "bag" and key == _selected


class _ItemSlot:
	extends Control
	## One slot, in the bag ("bag", index) or on the paperdoll ("worn", slot).

	var _panel: InventoryPanel
	var _where: String
	var _key: Variant
	var _item := ""
	var _icon: Texture2D
	var _hovered := false
	## Select (or act) on release: a press may be the start of a drag.
	var _pressing := false

	func _init(panel: InventoryPanel, where: String, key: Variant) -> void:
		_panel = panel
		_where = where
		_key = key
		custom_minimum_size = Vector2(InventoryPanel.SLOT_SIZE, InventoryPanel.SLOT_SIZE)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hovered = true
			queue_redraw()
			_panel._hover(_where, _key, true))
		mouse_exited.connect(func() -> void:
			_hovered = false
			queue_redraw()
			_panel._hover(_where, _key, false))

	func show_item(item: String) -> void:
		_item = item
		_icon = GameIcons.for_item(item) if item != "" else null
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var back := StyleBoxFlat.new()
		back.set_corner_radius_all(5)
		back.bg_color = InventoryPanel.KIND_COLORS.get(SimItems.kind_of(_item), InventoryPanel.KIND_COLORS.misc) if _item != "" else Color(0.12, 0.13, 0.15)
		draw_style_box(back, rect)
		var font := ThemeDB.fallback_font
		if _icon != null:
			draw_texture_rect(_icon, rect.grow(-3), false)
		elif _item != "":
			draw_multiline_string(font, Vector2(3, 16), _item, HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, 11, 3, Color.WHITE)
		elif _where == "worn":
			draw_string(font, Vector2(0, size.y / 2 + 4), EquipRules.SLOT_NAMES[_key], HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color(0.45, 0.47, 0.52))
		var border := InventoryPanel.IDLE_BORDER
		if _item != "" and _where == "bag" and CrimeRules.is_stolen(_panel._owner, _item):
			border = InventoryPanel.STOLEN_BORDER
		if _panel._is_selected(_where, _key) and _item != "":
			border = InventoryPanel.SELECTED_BORDER
		elif _hovered:
			border = InventoryPanel.HOVER_BORDER
		var outline := StyleBoxFlat.new()
		outline.draw_center = false
		outline.border_color = border
		outline.set_border_width_all(2)
		outline.set_corner_radius_all(5)
		draw_style_box(outline, rect)

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressing = true
			elif _pressing:
				_pressing = false
				_panel._clicked(_where, _key, false)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_panel._clicked(_where, _key, true)
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			_pressing = false

	func _get_drag_data(_at: Vector2) -> Variant:
		return _panel._drag_from(_where, _key, self)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return _panel._accepts_worn(_key, data) if _where == "worn" else _panel._accepts(data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if _where == "worn":
			_panel._drop_on_worn(_key, data)
		else:
			_panel._drop_on(_key, data)
