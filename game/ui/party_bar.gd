class_name PartyBar
extends VBoxContainer
## Party frames down the left edge: one same-sized frame per party member
## with a portrait, name, role and level, HP bar and AP pips. Clicking a frame
## selects that character; dropping an inventory item on it gives it to them.
## Chained characters' frames sit together, joined by a link; dragging a frame
## away unchains it, dragging it onto another frame chains the two.

signal member_selected(id: int)
## An inventory item was dragged onto a member's frame (give it to them).
signal item_dropped(to_id: int, from_id: int, index: int)
## A frame was dragged onto another member's frame (onto_id), or away from
## every frame (onto_id -1).
signal chain_dropped(id: int, onto_id: int)

const DRAG_KIND := "party_frame"
## Extra room between chains.
const CHAIN_GAP := 14
const LINK_COLOR := Color(0.72, 0.66, 0.5)

const FRAME_SIZE := Vector2(250, 78)
const PORTRAIT_SIZE := 62.0
const COLOR_SELECTED := Color(0.3, 1.0, 0.4)
const COLOR_IDLE := UiStyle.BORDER
const COLOR_DONE := Color(0.18, 0.19, 0.21)
## The partner's characters: blue border when selected (inspect only), and a
## "partner" tag; their frames are dimmed.
const COLOR_PARTNER_SELECTED := Color(0.45, 0.7, 1.0)
const PARTNER_DIM := Color(0.75, 0.82, 1.0, 0.7)
const HP_COLOR := Color(0.78, 0.18, 0.18)
const HP_LOW_COLOR := Color(0.95, 0.45, 0.1)
const FALLEN_DIM := Color(0.55, 0.55, 0.55)

var _cards := {}  # entity id -> _Card
var _layout := []  # [ids in shown order, linked flags] last laid out
var _spacers: Array[Control] = []


func _ready() -> void:
	# Left edge, a little above the middle (the HUD text is at the top left).
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = 16
	offset_top = -190
	grow_vertical = Control.GROW_DIRECTION_END
	add_theme_constant_override("separation", 8)


## turn_start_ap: entity id -> AP at the start of this turn (sets pip count).
## partner_ids: entity id -> true for characters the partner controls.
func update_party(party: Array[SimEntity], selected_id: int, turn_start_ap: Dictionary, pending_ap: int, partner_ids: Dictionary = {}, chains: PartyChains = null) -> void:
	var seen := {}
	for e in party:
		seen[e.id] = true
		var card: _Card = _cards.get(e.id)
		if card == null:
			card = _Card.new(e.id)
			card.clicked.connect(func(id: int) -> void: member_selected.emit(id))
			card.item_dropped.connect(func(to_id: int, from_id: int, index: int) -> void: item_dropped.emit(to_id, from_id, index))
			card.chain_dropped.connect(func(id: int, onto_id: int) -> void: chain_dropped.emit(id, onto_id))
			add_child(card)
			_cards[e.id] = card
		var selected := e.id == selected_id
		var partner := partner_ids.has(e.id)
		var border := COLOR_SELECTED if selected else (COLOR_IDLE if e.ap > 0 else COLOR_DONE)
		if partner and selected:
			border = COLOR_PARTNER_SELECTED
		card.show_member(e, turn_start_ap.get(e.id, e.ap), pending_ap if selected and not partner else 0, border, partner)
	for id: int in _cards.keys():
		if not seen.has(id):
			_cards[id].queue_free()
			_cards.erase(id)
	_lay_out(party, partner_ids, chains)


## Orders the frames chain by chain (the partner's after), with a gap between
## chains and a link between chained neighbours.
func _lay_out(party: Array[SimEntity], partner_ids: Dictionary, chains: PartyChains) -> void:
	var ids: Array[int] = []
	var linked: Array[bool] = []
	if chains != null:
		var layout := chains.layout()
		var prev := -1
		for id: int in layout[0]:
			if _cards.has(id) and not partner_ids.has(id):
				linked.append(prev != -1 and chains.together(prev, id))
				ids.append(id)
				prev = id
	for e in party:
		if not ids.has(e.id):
			ids.append(e.id)
			linked.append(false)
	var key := [ids, linked]
	if key == _layout:
		return
	_layout = key
	for spacer in _spacers:
		remove_child(spacer)
		spacer.free()
	_spacers.clear()
	var at := 0
	for i in ids.size():
		if i > 0 and not linked[i]:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, CHAIN_GAP)
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(spacer)
			move_child(spacer, at)
			_spacers.append(spacer)
			at += 1
		var card: _Card = _cards[ids[i]]
		move_child(card, at)
		card.set_linked(linked[i])
		at += 1


class _Card:
	extends PanelContainer

	signal clicked(id: int)
	signal item_dropped(to_id: int, from_id: int, index: int)
	signal chain_dropped(id: int, onto_id: int)

	var _linked := false
	var _partner := false
	var _dragging := false

	var _id: int
	var _portrait_back: PanelContainer
	var _portrait_style: StyleBoxFlat
	var _portrait: TextureRect
	var _name: Label
	var _role: Label
	var _hp: ProgressBar
	var _hp_fill: StyleBoxFlat
	var _hp_text: Label
	var _pips: ApPips
	var _style: StyleBoxFlat
	var _shown := []

	func _init(id: int) -> void:
		_id = id
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = PartyBar.FRAME_SIZE
		_style = StyleBoxFlat.new()
		_style.bg_color = UiStyle.BG
		_style.set_border_width_all(2)
		_style.set_corner_radius_all(5)
		_style.set_content_margin_all(6)
		add_theme_stylebox_override("panel", _style)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		add_child(row)

		_portrait_back = PanelContainer.new()
		_portrait_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait_back.custom_minimum_size = Vector2(PartyBar.PORTRAIT_SIZE, PartyBar.PORTRAIT_SIZE)
		_portrait_style = StyleBoxFlat.new()
		_portrait_style.set_corner_radius_all(4)
		_portrait_style.set_border_width_all(1)
		_portrait_style.border_color = Color(0, 0, 0, 0.7)
		_portrait_back.add_theme_stylebox_override("panel", _portrait_style)
		row.add_child(_portrait_back)
		_portrait = TextureRect.new()
		_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait.texture = GameIcons.portrait()
		_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_portrait_back.add_child(_portrait)

		var info := VBoxContainer.new()
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		_name = Label.new()
		_name.add_theme_font_size_override("font_size", 16)
		_name.clip_text = true
		info.add_child(_name)
		_role = Label.new()
		_role.add_theme_font_size_override("font_size", 12)
		_role.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
		info.add_child(_role)
		_hp = ProgressBar.new()
		_hp.show_percentage = false
		_hp.custom_minimum_size = Vector2(0, 14)
		_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var back := StyleBoxFlat.new()
		back.bg_color = Color(0.18, 0.06, 0.06)
		back.set_corner_radius_all(2)
		_hp.add_theme_stylebox_override("background", back)
		_hp_fill = StyleBoxFlat.new()
		_hp_fill.bg_color = PartyBar.HP_COLOR
		_hp_fill.set_corner_radius_all(2)
		_hp.add_theme_stylebox_override("fill", _hp_fill)
		info.add_child(_hp)
		_hp_text = Label.new()
		_hp_text.add_theme_font_size_override("font_size", 11)
		_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hp_text.add_theme_constant_override("outline_size", 3)
		_hp_text.add_theme_color_override("font_outline_color", Color.BLACK)
		_hp.add_child(_hp_text)
		_pips = ApPips.new()
		info.add_child(_pips)

	func show_member(e: SimEntity, turn_start_ap: int, pending: int, border: Color, partner: bool = false) -> void:
		var unspent := e.points + e.combat_points + e.civil_points  # attribute, school and civil
		var key := [e.name, e.hp, e.max_hp, e.ap, turn_start_ap, pending, border, partner, e.level, unspent]
		if key == _shown:
			return
		_shown = key
		_name.text = e.name + ("  (partner)" if partner else "")
		var role := SimArchetypes.title(e.archetype)
		_role.text = ("%s · level %d" % [role, e.level] if role != "" else "level %d" % e.level) \
				+ ("   +%d point%s" % [unspent, "s" if unspent > 1 else ""] if unspent > 0 else "")
		_role.add_theme_color_override("font_color", UiStyle.ACCENT if unspent > 0 else UiStyle.TEXT_DIM)
		_portrait_style.bg_color = GameIcons.role_color(e.archetype)
		_hp.max_value = e.max_hp
		_hp.value = e.hp
		_hp_fill.bg_color = PartyBar.HP_LOW_COLOR if e.hp * 3 <= e.max_hp else PartyBar.HP_COLOR
		_hp_text.text = "%d / %d" % [e.hp, e.max_hp] if e.is_alive() else "Fallen"
		_pips.set_points(e.ap, turn_start_ap, pending)
		_style.border_color = border
		_partner = partner
		modulate = PartyBar.PARTNER_DIM if partner else Color.WHITE
		_portrait.modulate = Color.WHITE if e.is_alive() else PartyBar.FALLEN_DIM

	func set_linked(linked: bool) -> void:
		if linked != _linked:
			_linked = linked
			queue_redraw()

	# A chain link across the gap to the frame above when chained to it.
	func _draw() -> void:
		if not _linked:
			return
		var x := 8.0 + PartyBar.PORTRAIT_SIZE / 2.0
		draw_rect(Rect2(x - 3, -11, 6, 7), PartyBar.LINK_COLOR, false, 2.0)
		draw_rect(Rect2(x - 3, -6, 6, 7), PartyBar.LINK_COLOR, false, 2.0)

	func _get_drag_data(_at: Vector2) -> Variant:
		if _partner:
			return null
		_dragging = true
		if get_viewport().gui_is_dragging():
			set_drag_preview(_drag_preview())
		return {"kind": PartyBar.DRAG_KIND, "id": _id}

	func _drag_preview() -> Control:
		var preview := TextureRect.new()
		preview.texture = _portrait.texture
		preview.self_modulate = _portrait_style.bg_color.lightened(0.3)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.size = Vector2(PartyBar.PORTRAIT_SIZE, PartyBar.PORTRAIT_SIZE) * 0.8
		preview.position = -preview.size / 2.0
		var holder := Control.new()
		holder.add_child(preview)
		return holder

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END and _dragging:
			_dragging = false
			if not get_viewport().gui_is_drag_successful():
				chain_dropped.emit(_id, -1)  # let go away from every frame: unchain

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		if data.get("kind") == PartyBar.DRAG_KIND:
			return not _partner  # back on its own frame: nothing changes
		return data.get("kind") == InventoryPanel.DRAG_KIND and data.from_id != _id

	func _drop_data(_at: Vector2, data: Variant) -> void:
		if data.get("kind") == PartyBar.DRAG_KIND:
			if data.id != _id:
				chain_dropped.emit(data.id, _id)
		else:
			item_dropped.emit(_id, data.from_id, data.index)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(_id)
			accept_event()
