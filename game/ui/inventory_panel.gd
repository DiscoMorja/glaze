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
const SLOT_SIZE := ItemSlot.SIZE
const GAP := 6.0
## Bag rows shown before it scrolls.
const VISIBLE_ROWS := 6
## Paperdoll slot -> position in slot units (columns: 0 left, 1-2 figure, 3 right).
const DOLL := {
	"head": Vector2(0, 0), "neck": Vector2(0, 1), "body": Vector2(0, 2),
	"waist": Vector2(0, 3), "legs": Vector2(0, 4), "feet": Vector2(0, 5),
	"hands": Vector2(3, 0), "ring1": Vector2(3, 1), "ring2": Vector2(3, 2),
	"main_hand": Vector2(1, 5), "off_hand": Vector2(2, 5),
}

var _title: Label
var _sheet: Label
## Attributes, schools and civil skills, with + buttons while points are left.
var _stats: VBoxContainer
var _doll: Control
var _doll_slots := {}  # slot name -> ItemSlot
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
	add_theme_stylebox_override("panel", UiStyle.window_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	_title = UiStyle.title("")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_rest = UiStyle.button("Rest", func() -> void: rest_requested.emit(_owner.id), "Heal the party with a bedroll (no enemies near)")
	top.add_child(_rest)
	_sheet = Label.new()
	_sheet.add_theme_font_size_override("font_size", 13)
	_sheet.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	box.add_child(_sheet)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 2)
	box.add_child(_stats)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	box.add_child(columns)
	_doll = Control.new()
	_doll.custom_minimum_size = Vector2(4 * SLOT_SIZE + 3 * GAP, 6 * SLOT_SIZE + 5 * GAP)
	columns.add_child(_doll)
	var figure_back := Panel.new()
	var figure_style := StyleBoxFlat.new()
	figure_style.bg_color = UiStyle.SLOT_BG.darkened(0.1)
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
		var item_slot := _make_slot("worn", slot)
		item_slot.empty_label = EquipRules.SLOT_NAMES[slot]
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
	_footer.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
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
			can_give, can_sort, owner.gold, owner.xp, owner.level, owner.points, owner.hp, owner.max_hp,
			owner.combat_points, owner.civil_points, owner.schools.duplicate(), _stat_values(owner)]
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
		var item_slot := _make_slot("bag", i)
		var item := items[i] if i < items.size() else ""
		item_slot.stolen = item != "" and CrimeRules.is_stolen(_owner, item)
		item_slot.selected = i == _selected
		item_slot.show_item(item)
		_grid.add_child(item_slot)
	_footer.text = "%d items   ·   %d gold worth   ·   %s" % [
		items.size(), SimItems.total_value(items), SimItems.weight_text(SimItems.total_weight(items))]
	_show_details()
	_show_give_buttons()


func _show_sheet() -> void:
	var e := _owner
	var role := SimArchetypes.title(e.archetype)
	var next := ProgressionRules.xp_for_level(e.level + 1)
	var carried := StatRules.carried(e)
	_sheet.text = "%sLevel %d   ·   %d / %d XP   ·   %d gold\nHP %d/%d   ·   %d damage   ·   armour %d   ·   spells +%d   ·   carrying %s / %s%s" % [
		role + "   ·   " if role != "" else "", e.level, e.xp, next, e.gold,
		e.hp, e.max_hp, e.attack_damage(), e.armor, e.spell_power(),
		SimItems.weight_text(carried), SimItems.weight_text(StatRules.carry_limit(e)),
		" (overloaded: slowed)" if StatRules.is_overloaded(e) else ""]
	for child in _stats.get_children():
		child.queue_free()
	_stat_row(e, "Attributes", StatRules.ATTRIBUTES, e.points)
	_stat_row(e, "Schools", StatRules.SCHOOLS, e.combat_points)
	_stat_row(e, "Civil", StatRules.CIVIL, e.civil_points)


## One line of stats ("Strength 3"), each with a + while a point is left to
## spend on it (this player's character only).
func _stat_row(e: SimEntity, heading: String, stats: Array[String], points: int) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	_stats.add_child(row)
	var head := Label.new()
	head.text = heading + (" (%d to spend)" % points if points > 0 else "") + ":"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", UiStyle.ACCENT if points > 0 and _can_sort else UiStyle.TEXT_DIM)
	row.add_child(head)
	for stat in stats:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.tooltip_text = StatRules.DESCRIPTIONS.get(stat, "")
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(cell)
		var value := StatRules.value(e, stat)
		var label := Label.new()
		label.text = "%s %d" % [stat.capitalize(), value]
		label.add_theme_font_size_override("font_size", 13)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		if value == 0:
			label.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
		cell.add_child(label)
		if _can_sort and ProgressionRules.can_spend(e, stat):
			var plus := UiStyle.button("+", func() -> void: spend_requested.emit(e.id, stat), "Spend a point: " + StatRules.DESCRIPTIONS.get(stat, ""))
			plus.add_theme_font_size_override("font_size", 12)
			plus.custom_minimum_size = Vector2(20, 18)
			cell.add_child(plus)


static func _stat_values(e: SimEntity) -> Array[int]:
	var values: Array[int] = []
	for stat in StatRules.ATTRIBUTES + StatRules.CIVIL:
		values.append(StatRules.value(e, stat))
	return values


## A bag ("bag", index) or paperdoll ("worn", slot) slot wired to this panel.
func _make_slot(where: String, key: Variant) -> ItemSlot:
	var slot := ItemSlot.new()
	slot.on_click = func(right: bool) -> void: _clicked(where, key, right)
	slot.on_hover = func(inside: bool) -> void: _hover(where, key, inside)
	slot.drag_data = func() -> Variant: return _drag_from(where, key)
	if where == "worn":
		slot.can_drop = func(data: Variant) -> bool: return _accepts_worn(key, data)
		slot.drop = func(data: Variant) -> void: _drop_on_worn(key, data)
	else:
		slot.can_drop = func(data: Variant) -> bool: return _accepts(data)
		slot.drop = func(data: Variant) -> void: _drop_on(key, data)
	return slot


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
	var lines: Array[String] = [ItemSlot.details(item)]
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
		_give_row.add_child(UiStyle.button("Use", func() -> void:
			_selected = -1
			use_requested.emit(owner_id, index)))
	if _can_give and SimItems.slot_of(item) != "":
		_give_row.add_child(UiStyle.button("Wear", func() -> void:
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
		_give_row.add_child(UiStyle.button(p.name, func() -> void:
			_selected = -1
			give_requested.emit(owner_id, to_id, index)))


# --- Slots: dragging, dropping, clicking -----------------------------------------

func _drag_from(where: String, key: Variant) -> Variant:
	var item := _item_at(where, key)
	if item == "" or not (_can_sort or _can_give):
		return null
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
