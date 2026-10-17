class_name PartyBar
extends PanelContainer
## Bottom bar: one card per party member (name, HP, AP pips) plus an End turn
## button. Clicking a card selects that character.

signal member_selected(id: int)
signal end_turn_pressed

const COLOR_SELECTED := Color(0.3, 1.0, 0.4)
const COLOR_IDLE := Color(0.25, 0.27, 0.3)
const COLOR_DONE := Color(0.5, 0.5, 0.5)

var _row: HBoxContainer
var _cards := {}  # entity id -> _Card
var _end_turn: Button


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


## turn_start_ap: entity id -> AP at the start of this turn (sets pip count).
func update_party(party: Array[SimEntity], selected_id: int, turn_start_ap: Dictionary, pending_ap: int, players_turn: bool) -> void:
	var seen := {}
	for e in party:
		seen[e.id] = true
		var card: _Card = _cards.get(e.id)
		if card == null:
			card = _Card.new(e.id)
			card.clicked.connect(func(id: int) -> void: member_selected.emit(id))
			_row.add_child(card)
			_row.move_child(card, _row.get_child_count() - 2)
			_cards[e.id] = card
		var selected := e.id == selected_id
		var border := COLOR_SELECTED if selected else (COLOR_IDLE if e.ap > 0 else COLOR_DONE)
		card.show_member(e, turn_start_ap.get(e.id, e.ap), pending_ap if selected else 0, border)
	for id: int in _cards.keys():
		if not seen.has(id):
			_cards[id].queue_free()
			_cards.erase(id)
	_end_turn.disabled = not players_turn


class _Card:
	extends PanelContainer

	signal clicked(id: int)

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

	func show_member(e: SimEntity, turn_start_ap: int, pending: int, border: Color) -> void:
		var role := SimArchetypes.title(e.archetype)
		_name.text = "%s  %d/%d" % [e.name, e.hp, e.max_hp] if role == "" else "%s · %s  %d/%d" % [e.name, role, e.hp, e.max_hp]
		_hp.max_value = e.max_hp
		_hp.value = e.hp
		_pips.set_points(e.ap, turn_start_ap, pending)
		_style.border_color = border

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(_id)
			accept_event()
