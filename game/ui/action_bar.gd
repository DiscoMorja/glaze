class_name ActionBar
extends PanelContainer
## The selected character's action bar, bottom centre: HotbarLayout.SLOTS
## same-sized slots with icons, on HotbarLayout.PAGES pages (the arrows, or
## [ and ], switch pages). A slot holds an action (Attack or an ability) or a
## usable item from the bag (with how many are left). Hovering any slot shows
## its tooltip above the bar. Arrange it by dragging: slots onto slots swap,
## inventory items onto a slot put them there; right-click clears a slot.

signal action_pressed(action: int)
signal item_pressed(item: String)
## ActionInfo.NONE when the mouse leaves the bar or is over an item.
signal action_hovered(action: int)

const SLOT_SIZE := 60.0
const SLOT_GAP := 4
## What a slot dragged from the bar carries.
const DRAG_KIND := "glaze_bar_slot"
const KEY_NAMES := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

var page := 0
var _row: HBoxContainer
## The selected character's AP above the slots (combat): every point it can
## hold, filled ones available, orange ones the aimed action would spend.
var _ap_row: HBoxContainer
var _ap: ApPips
var _ap_label: Label
var _page_label: Label
var _note: Label
var _tip_panel: PanelContainer
var _tip: Label
var _slots: Array[_Slot] = []
var _actor: SimEntity
var _aimed := ActionInfo.NONE
var _usable := false
var _needs_ap := false
var _tip_index := -1


func _ready() -> void:
	visible = false  # until a character is selected
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -24
	offset_bottom = -24
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_theme_stylebox_override("panel", UiStyle.window_style())
	var column := VBoxContainer.new()
	add_child(column)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	_note.visible = false
	column.add_child(_note)
	_ap_row = HBoxContainer.new()
	_ap_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ap_row.add_theme_constant_override("separation", 8)
	column.add_child(_ap_row)
	_ap = ApPips.new()
	_ap.radius = 9.0
	_ap.spacing = 24.0
	_ap_row.add_child(_ap)
	_ap_label = UiStyle.dim("", 13)
	_ap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ap_row.add_child(_ap_label)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", SLOT_GAP)
	column.add_child(_row)
	_row.add_child(_arrow("◀", -1))
	for i in HotbarLayout.SLOTS:
		var slot := _Slot.new(self, i)
		_slots.append(slot)
		_row.add_child(slot)
	_row.add_child(_arrow("▶", 1))
	_page_label = Label.new()
	_page_label.custom_minimum_size = Vector2(30, 0)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
	_row.add_child(_page_label)
	_show_page_label()

	# Floats above the bar; top_level keeps it out of the bar's layout.
	_tip_panel = PanelContainer.new()
	_tip_panel.top_level = true
	_tip_panel.visible = false
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_style := UiStyle.window_style(true)
	tip_style.border_color = Color(UiStyle.ACCENT, 0.8)
	tip_style.set_content_margin_all(10)
	_tip_panel.add_theme_stylebox_override("panel", tip_style)
	_tip = Label.new()
	_tip.custom_minimum_size = Vector2(340, 0)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", UiStyle.TEXT_WARM)
	_tip_panel.add_child(_tip)
	add_child(_tip_panel)


func _arrow(text: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(26, SLOT_SIZE)
	button.tooltip_text = "Previous bar  ( [ )" if step < 0 else "Next bar  ( ] )"
	button.pressed.connect(func() -> void: turn_page(step))
	return button


func turn_page(step: int) -> void:
	page = posmod(page + step, HotbarLayout.PAGES)
	_show_page_label()
	_redraw()


func _show_page_label() -> void:
	if _page_label != null:
		_page_label.text = "%d/%d" % [page + 1, HotbarLayout.PAGES]


## needs_ap: in combat actions cost AP; outside combat they don't.
## note: shown above the slots when set (why they can't be used).
func show_actions(actor: SimEntity, aimed: int, usable: bool, needs_ap: bool = true, note: String = "") -> void:
	_note.text = note
	_note.visible = note != ""
	_actor = actor
	_aimed = aimed
	_usable = usable
	_needs_ap = needs_ap
	visible = actor != null
	if not visible:
		_tip_panel.visible = false
		return
	_redraw()


func _redraw() -> void:
	if _actor == null:
		return
	var entries := HotbarLayout.page(_actor, page)
	for i in _slots.size():
		_slots[i].show_entry(entries[i])
	if _tip_panel.visible and _tip_index >= 0:
		_tip.text = tooltip_for(_slots[_tip_index].entry)


## Action points above the slots: available of the CombatRules.AP_CAP it can
## hold, `pending` of them about to be spent. Hidden outside combat.
func show_ap(shown: bool, available: int, pending: int, per_turn: int) -> void:
	_ap_row.visible = shown
	if not shown:
		return
	_ap.set_points(available, CombatRules.AP_CAP, pending)
	# Points not spent carry over (up to the cap): saving them is a choice.
	var gain := mini(per_turn, CombatRules.AP_CAP - available)
	_ap_label.text = "%d / %d AP   ·   +%d next turn" % [available, CombatRules.AP_CAP, gain]


## Presses the slot (keys 1-0).
func press(index: int) -> void:
	if index >= 0 and index < _slots.size():
		_activate(_slots[index].entry)


func _activate(entry: String) -> void:
	if _actor == null or not _usable or not usable(entry):
		return
	if HotbarLayout.is_action(entry):
		action_pressed.emit(HotbarLayout.action_of(entry))
	elif HotbarLayout.is_item(entry):
		item_pressed.emit(HotbarLayout.item_of(entry))


## Whether the entry can be used now (AP, cooldown, has the item).
func usable(entry: String) -> bool:
	if HotbarLayout.is_action(entry):
		var action := HotbarLayout.action_of(entry)
		if not ActionInfo.actions_for(_actor).has(action):
			return false
		if action >= 0 and SimAbilities.lacks(_actor, action) != "":
			return false
		return not (_needs_ap and _actor.ap < ActionInfo.cost(action)) and ActionInfo.remaining(action, _actor) == 0
	if HotbarLayout.is_item(entry):
		var item := HotbarLayout.item_of(entry)
		var item_cost := UseItemCommand.AP_COST if SimItems.is_usable(item) else 0
		return _actor.inventory.has(item) and not (_needs_ap and _actor.ap < item_cost)
	return false


func tooltip_for(entry: String) -> String:
	if HotbarLayout.is_action(entry):
		return ActionInfo.tooltip(HotbarLayout.action_of(entry), _actor)
	if HotbarLayout.is_item(entry):
		var item := HotbarLayout.item_of(entry)
		var lines: Array[String] = ["%s — %d in the bag" % [item, _actor.inventory.count(item) if _actor != null else 0]]
		if SimItems.info(item).blurb != "":
			lines.append(SimItems.info(item).blurb)
		if SimItems.is_usable(item):
			lines.append("Use on yourself; %d AP in combat." % UseItemCommand.AP_COST)
		elif SimItems.has_property(item, "rest"):
			lines.append("Click to rest the party.")
		lines.append("Right-click to take it off the bar.")
		return "\n".join(lines)
	return "Empty slot. Drag an item from the inventory (I) or another slot here."


func _hover(index: int) -> void:
	_tip_index = index
	var entry := _slots[index].entry
	_tip.text = tooltip_for(entry)
	_tip_panel.visible = true
	_tip_panel.reset_size()
	_place_tip.call_deferred()
	action_hovered.emit(HotbarLayout.action_of(entry) if HotbarLayout.is_action(entry) else ActionInfo.NONE)


func _unhover() -> void:
	_tip_index = -1
	_tip_panel.visible = false
	action_hovered.emit(ActionInfo.NONE)


func _place_tip() -> void:
	var bar := get_global_rect()
	_tip_panel.global_position = Vector2(bar.position.x + (bar.size.x - _tip_panel.size.x) / 2.0, bar.position.y - _tip_panel.size.y - 8.0)


# --- Arranging -----------------------------------------------------------------

func _drag_data(index: int) -> Variant:
	var entry := _slots[index].entry
	if entry == HotbarLayout.EMPTY or _actor == null:
		return null
	var preview := TextureRect.new()
	preview.texture = _slots[index].icon
	preview.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.modulate.a = 0.8
	set_drag_preview(preview)
	return {"kind": DRAG_KIND, "page": page, "index": index}


func _accepts(data: Variant) -> bool:
	if _actor == null or not data is Dictionary:
		return false
	if data.get("kind") == DRAG_KIND:
		return true
	return data.get("kind") == InventoryPanel.DRAG_KIND and data.get("from_id") == _actor.id \
			and HotbarLayout.bar_item(data.get("item", ""))


func _drop(index: int, data: Variant) -> void:
	if data.kind == DRAG_KIND:
		HotbarLayout.swap(_actor, data.page, data.index, page, index)
	else:
		HotbarLayout.set_slot(_actor, page, index, HotbarLayout.item_entry(data.item))
	_redraw()


func _clear(index: int) -> void:
	if _actor != null:
		HotbarLayout.set_slot(_actor, page, index, HotbarLayout.EMPTY)
		_redraw()
		if _tip_index == index:
			_tip.text = tooltip_for(HotbarLayout.EMPTY)


class _Slot:
	extends Control

	var entry := HotbarLayout.EMPTY
	var icon: Texture2D
	var _bar: ActionBar
	var _index: int
	var _hovered := false
	var _shown := []

	func _init(bar: ActionBar, index: int) -> void:
		_bar = bar
		_index = index
		custom_minimum_size = Vector2(ActionBar.SLOT_SIZE, ActionBar.SLOT_SIZE)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hovered = true
			queue_redraw()
			_bar._hover(_index))
		mouse_exited.connect(func() -> void:
			_hovered = false
			queue_redraw()
			_bar._unhover())

	func show_entry(p_entry: String) -> void:
		var actor := _bar._actor
		var key := [p_entry, _bar._usable, _bar.usable(p_entry), _bar._aimed, actor.inventory.count(HotbarLayout.item_of(p_entry)) if HotbarLayout.is_item(p_entry) else 0,
				ActionInfo.remaining(HotbarLayout.action_of(p_entry), actor) if HotbarLayout.is_action(p_entry) else 0, _bar._needs_ap]
		if key == _shown:
			return
		_shown = key
		entry = p_entry
		if HotbarLayout.is_action(entry):
			icon = GameIcons.for_action(HotbarLayout.action_of(entry))
		elif HotbarLayout.is_item(entry):
			icon = GameIcons.for_item(HotbarLayout.item_of(entry))
		else:
			icon = null
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var font := ThemeDB.fallback_font
		var box := StyleBoxFlat.new()
		box.bg_color = UiStyle.SLOT_BG
		box.set_corner_radius_all(6)
		draw_style_box(box, rect)
		var actor := _bar._actor
		var ready := entry != HotbarLayout.EMPTY and _bar._usable and _bar.usable(entry)
		var label := ""
		if HotbarLayout.is_action(entry):
			label = ActionInfo.name_of(HotbarLayout.action_of(entry))
		elif HotbarLayout.is_item(entry):
			label = HotbarLayout.item_of(entry)
		if icon != null:
			draw_texture_rect(icon, rect.grow(-2), false, Color.WHITE if ready else Color(0.45, 0.45, 0.48))
		elif label != "":
			draw_string(font, Vector2(4, size.y / 2 + 5), label.substr(0, 7), HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, 12, Color.WHITE)
		# Cooldown: big number of turns over a dark veil.
		if HotbarLayout.is_action(entry) and actor != null:
			var wait := ActionInfo.remaining(HotbarLayout.action_of(entry), actor)
			if wait > 0:
				draw_rect(rect.grow(-2), Color(0, 0, 0, 0.45))
				_text(str(wait), Vector2(0, size.y / 2 + 9), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		# Corner numbers: key, AP cost (in combat), count of items left.
		_text(ActionBar.KEY_NAMES[_index], Vector2(4, 14), 12, Color(0.9, 0.9, 0.9))
		if HotbarLayout.is_action(entry) and _bar._needs_ap:
			_cost_dots(ActionInfo.cost(HotbarLayout.action_of(entry)))
		elif HotbarLayout.is_item(entry) and _bar._needs_ap and SimItems.is_usable(HotbarLayout.item_of(entry)):
			_cost_dots(UseItemCommand.AP_COST, 16.0)
		elif HotbarLayout.is_item(entry) and actor != null:
			_text("%d" % actor.inventory.count(HotbarLayout.item_of(entry)), Vector2(0, size.y - 4), 13, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4)
		# Border: gold when aimed, light when hovered.
		var border := ItemSlot.IDLE_BORDER
		if HotbarLayout.is_action(entry) and HotbarLayout.action_of(entry) == _bar._aimed:
			border = ItemSlot.SELECTED_BORDER
		elif _hovered:
			border = ItemSlot.HOVER_BORDER
		var outline := StyleBoxFlat.new()
		outline.draw_center = false
		outline.border_color = border
		outline.set_border_width_all(2)
		outline.set_corner_radius_all(6)
		draw_style_box(outline, rect)

	## The AP cost as little circles along the bottom edge (right-aligned,
	## leaving `right_gap` for an item count).
	func _cost_dots(cost: int, right_gap: float = 0.0) -> void:
		var r := 3.6
		for i in cost:
			var c := Vector2(size.x - 7.0 - right_gap - i * (r * 2.0 + 2.0), size.y - 7.0)
			draw_circle(c, r + 1.0, Color(0, 0, 0, 0.85))
			draw_circle(c, r, ApPips.COLOR_AVAILABLE)

	func _text(text: String, at: Vector2, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
		var font := ThemeDB.fallback_font
		draw_string_outline(font, at, text, align, width, font_size, 4, Color(0, 0, 0, 0.9))
		draw_string(font, at, text, align, width, font_size, color)

	## Left click uses the slot on release, so pressing and dragging it away
	## only moves it.
	var _pressing := false

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressing = true
			elif _pressing:
				_pressing = false
				_bar._activate(entry)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_bar._clear(_index)
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_BEGIN:
			_pressing = false

	func _get_drag_data(_at: Vector2) -> Variant:
		return _bar._drag_data(_index)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return _bar._accepts(data)

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_bar._drop(_index, data)
