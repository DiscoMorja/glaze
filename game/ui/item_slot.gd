class_name ItemSlot
extends Control
## One item slot as every window shows it (inventory, paperdoll, trade, loot):
## the item's icon on a plate tinted by its kind (its name if it has no
## icon), a corner number (a price, a count), and a border for its state.
## Empty slots can show a faint label (paperdoll: "Head").
##
## What clicks, hovers and drags do is up to the window: set the callables.
## Left click fires on release, so a press can start a drag instead.

const SIZE := 52.0
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
## Border states, strongest last wins in draw order: none, stolen, selected.
const IDLE_BORDER := Color(0.3, 0.32, 0.36)
const HOVER_BORDER := Color(0.8, 0.82, 0.88)
const STOLEN_BORDER := Color(1.0, 0.35, 0.3)
const SELECTED_BORDER := UiStyle.ACCENT

var item := ""
## Small number or text in the bottom-right corner ("" = none).
var corner := ""
var corner_color := Color.WHITE
## Faint label in an empty slot.
var empty_label := ""
var stolen := false
var selected := false
## Greyed out (can't be taken, can't afford...).
var dimmed := false

## (right: bool) -> void
var on_click: Callable
## (inside: bool) -> void
var on_hover: Callable
## () -> Variant (drag data, or null)
var drag_data: Callable
## (data: Variant) -> bool
var can_drop: Callable
## (data: Variant) -> void
var drop: Callable

var _icon: Texture2D
var _hovered := false
var _pressing := false


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw()
		if on_hover.is_valid():
			on_hover.call(true))
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw()
		# A window rebuilding its slots frees the one under the mouse: that
		# isn't the mouse leaving, so the details stay.
		if on_hover.is_valid() and not is_queued_for_deletion():
			on_hover.call(false))


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
	if SimItems.amount(item, "ranged") > 0:
		parts.append("range %d" % SimItems.amount(item, "ranged"))
	var scales: String = SimItems.info(item).get("scales", "")
	if scales != "":
		parts.append({"str": "Strength", "dex": "Dexterity", "mind": "Mind"}.get(scales, scales))
	if SimItems.has_property(item, "ammo"):
		parts.append("arrow for Loaded Shot")
	var skill := SimItems.teaches(item)
	if skill >= 0:
		parts.append("teaches %s (%s %d)" % [SimAbilities.NAMES[skill], StatRules.SCHOOLS[SimAbilities.SCHOOL[skill]].capitalize(), SimAbilities.RANK[skill]])
	return "   ·   ".join(parts)


## The details every window shows for an item: name, value and weight;
## stats; description.
static func details(item: String) -> String:
	var info := SimItems.info(item)
	var lines: Array[String] = ["%s   ·   %d gold   ·   %s" % [item, info.value, SimItems.weight_text(info.weight)]]
	var stats := stats_text(item)
	if stats != "":
		lines.append(stats)
	if info.blurb != "":
		lines.append(info.blurb)
	return "\n".join(lines)


func show_item(p_item: String, p_corner: String = "") -> void:
	item = p_item
	corner = p_corner
	_icon = GameIcons.for_item(item) if item != "" else null
	queue_redraw()


## A drag preview showing this slot's icon.
func make_preview() -> Control:
	if _icon == null:
		var label := Label.new()
		label.text = item
		return label
	var preview := TextureRect.new()
	preview.texture = _icon
	preview.size = Vector2(SIZE, SIZE)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.modulate.a = 0.85
	return preview


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var back := StyleBoxFlat.new()
	back.set_corner_radius_all(5)
	back.bg_color = KIND_COLORS.get(SimItems.kind_of(item), KIND_COLORS.misc) if item != "" else UiStyle.SLOT_BG
	draw_style_box(back, rect)
	var font := ThemeDB.fallback_font
	var tint := Color(0.45, 0.45, 0.48) if dimmed else Color.WHITE
	if _icon != null:
		draw_texture_rect(_icon, rect.grow(-3), false, tint)
	elif item != "":
		draw_multiline_string(font, Vector2(3, 16), item, HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, 11, 3, tint)
	elif empty_label != "":
		draw_string(font, Vector2(0, size.y / 2 + 4), empty_label, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color(0.45, 0.47, 0.52))
	if corner != "" and item != "":
		var at := Vector2(0, size.y - 4)
		draw_string_outline(font, at, corner, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, 4, Color(0, 0, 0, 0.9))
		draw_string(font, at, corner, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, corner_color)
	var border := IDLE_BORDER
	if _hovered:
		border = HOVER_BORDER
	if stolen and item != "":
		border = STOLEN_BORDER
	if selected and item != "":
		border = SELECTED_BORDER
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
			if on_click.is_valid():
				on_click.call(false)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if on_click.is_valid():
			on_click.call(true)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_pressing = false


func _get_drag_data(_at: Vector2) -> Variant:
	if not drag_data.is_valid():
		return null
	var data: Variant = drag_data.call()
	if data != null:
		set_drag_preview(make_preview())
	return data


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return can_drop.is_valid() and can_drop.call(data)


func _drop_data(_at: Vector2, data: Variant) -> void:
	if drop.is_valid():
		drop.call(data)
