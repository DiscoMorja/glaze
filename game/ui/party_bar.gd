class_name PartyBar
extends PanelContainer
## Bottom bar: one card per party member (name, HP, AP pips) plus an End turn
## button. Clicking a card selects that character.

signal member_selected(id: int)
signal end_turn_pressed
## An inventory item was dragged onto a member's card (give it to them).
signal item_dropped(to_id: int, from_id: int, index: int)

const COLOR_SELECTED := Color(0.3, 1.0, 0.4)
const COLOR_IDLE := Color(0.25, 0.27, 0.3)
const COLOR_DONE := Color(0.5, 0.5, 0.5)
## The partner's characters: blue border when selected (inspect only), and a
## "partner" tag; their cards are dimmed.
const COLOR_PARTNER_SELECTED := Color(0.45, 0.7, 1.0)
const PARTNER_DIM := Color(0.75, 0.82, 1.0, 0.7)

## How the End turn button looks: normal, lit up (nothing left to do), or
## waiting for the partner after pressing it.
enum EndTurn { NORMAL, SUGGESTED, WAITING }

var _row: HBoxContainer
var _cards := {}  # entity id -> _Card
var _end_turn: Button
var _end_turn_lit: StyleBoxFlat
var _pulse: Tween


func _ready() -> void:
	# Pinned to the bottom centre; grows up and outwards as cards are added.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	offset_top = -12
	offset_bottom = -12
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)
	_end_turn = Button.new()
	_end_turn.text = "End turn"
	_end_turn.custom_minimum_size = Vector2(110, 0)
	_end_turn.focus_mode = Control.FOCUS_NONE
	_end_turn.pressed.connect(func() -> void: end_turn_pressed.emit())
	_row.add_child(_end_turn)
	_end_turn_lit = StyleBoxFlat.new()
	_end_turn_lit.bg_color = Color(0.16, 0.45, 0.2)
	_end_turn_lit.border_color = Color(0.4, 1.0, 0.5)
	_end_turn_lit.set_border_width_all(2)
	_end_turn_lit.set_corner_radius_all(4)


## turn_start_ap: entity id -> AP at the start of this turn (sets pip count).
## partner_ids: entity id -> true for characters the partner controls.
func update_party(party: Array[SimEntity], selected_id: int, turn_start_ap: Dictionary, pending_ap: int, players_turn: bool, partner_ids: Dictionary = {}, end_turn: EndTurn = EndTurn.NORMAL) -> void:
	var seen := {}
	for e in party:
		seen[e.id] = true
		var card: _Card = _cards.get(e.id)
		if card == null:
			card = _Card.new(e.id)
			card.clicked.connect(func(id: int) -> void: member_selected.emit(id))
			card.item_dropped.connect(func(to_id: int, from_id: int, index: int) -> void: item_dropped.emit(to_id, from_id, index))
			_row.add_child(card)
			_row.move_child(card, _row.get_child_count() - 2)
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
	_end_turn.disabled = not players_turn
	_show_end_turn(end_turn)


func _show_end_turn(look: EndTurn) -> void:
	_end_turn.text = "Waiting for partner..." if look == EndTurn.WAITING else "End turn"
	var lit := look == EndTurn.SUGGESTED
	for state_name in ["normal", "hover", "pressed"]:
		if lit:
			_end_turn.add_theme_stylebox_override(state_name, _end_turn_lit)
		else:
			_end_turn.remove_theme_stylebox_override(state_name)
	if lit and _pulse == null:
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_end_turn, "modulate", Color(1.25, 1.25, 1.25), 0.6)
		_pulse.tween_property(_end_turn, "modulate", Color.WHITE, 0.6)
	elif not lit and _pulse != null:
		_pulse.kill()
		_pulse = null
		_end_turn.modulate = Color.WHITE


class _Card:
	extends PanelContainer

	signal clicked(id: int)
	signal item_dropped(to_id: int, from_id: int, index: int)

	var _id: int
	var _name: Label
	var _hp: ProgressBar
	var _pips: ApPips
	var _style: StyleBoxFlat

	func _init(id: int) -> void:
		_id = id
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(150, 0)
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.1, 0.11, 0.13, 0.9)
		_style.set_border_width_all(2)
		_style.set_corner_radius_all(4)
		_style.set_content_margin_all(6)
		add_theme_stylebox_override("panel", _style)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		_name = Label.new()
		box.add_child(_name)
		_hp = ProgressBar.new()
		_hp.show_percentage = false
		_hp.custom_minimum_size = Vector2(0, 8)
		_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.85, 0.2, 0.2)
		_hp.add_theme_stylebox_override("fill", fill)
		box.add_child(_hp)
		_pips = ApPips.new()
		box.add_child(_pips)

	func show_member(e: SimEntity, turn_start_ap: int, pending: int, border: Color, partner: bool = false) -> void:
		var role := SimArchetypes.title(e.archetype)
		_name.text = "%s  %d/%d" % [e.name, e.hp, e.max_hp] if role == "" else "%s · %s  %d/%d" % [e.name, role, e.hp, e.max_hp]
		if partner:
			_name.text += "  (partner)"
		modulate = PARTNER_DIM if partner else Color.WHITE
		_hp.max_value = e.max_hp
		_hp.value = e.hp
		_pips.set_points(e.ap, turn_start_ap, pending)
		_style.border_color = border

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("kind") == InventoryPanel.DRAG_KIND and data.from_id != _id

	func _drop_data(_at: Vector2, data: Variant) -> void:
		item_dropped.emit(_id, data.from_id, data.index)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(_id)
			accept_event()
