class_name DialoguePanel
extends PanelContainer
## The conversation in progress (state.conversation): who is talking, the
## lines of the current page, and the choices. Only the talking player can
## choose (buttons, or 1-9); the partner watches.

signal chosen(index: int)

const NPC_COLOR := Color(1.0, 0.85, 0.55)
const PLAYER_COLOR := Color(0.6, 0.85, 1.0)
const NARRATION_COLOR := Color(0.75, 0.75, 0.8)

var _title: Label
var _lines: RichTextLabel
var _choices: VBoxContainer
var _shown := {}
var _can_choose := false
var _choice_count := 0


func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -180
	offset_bottom = -180
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(620, 0)
	add_theme_stylebox_override("panel", UiStyle.window_style(true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = UiStyle.title("")
	_title.add_theme_color_override("font_color", NPC_COLOR)
	box.add_child(_title)
	_lines = RichTextLabel.new()
	_lines.bbcode_enabled = true
	_lines.fit_content = true
	_lines.scroll_active = false
	_lines.custom_minimum_size = Vector2(596, 0)
	box.add_child(_lines)
	_choices = VBoxContainer.new()
	box.add_child(_choices)


## Shows the conversation (empty: hidden). can_choose: this player is talking.
func show_conversation(state: SimState, can_choose: bool) -> void:
	var convo := state.conversation
	visible = not convo.is_empty()
	if not visible:
		_shown = {}
		return
	if convo == _shown and can_choose == _can_choose:
		return
	_shown = convo.duplicate(true)
	_can_choose = can_choose
	var npc := state.get_entity(convo.npc)
	var talker := state.get_entity(convo.talker)
	_title.text = "%s talks with %s" % [talker.name if talker else "?", npc.name if npc else "?"]
	var text := ""
	for line: Array in convo.lines:
		var speaker: String = line[0]
		var mine: bool = line[2]
		if mine:
			text += "[color=#%s]%s: %s[/color]\n" % [PLAYER_COLOR.to_html(false), talker.name if talker else "You", line[1]]
		elif speaker == "":
			text += "[color=#%s][i]%s[/i][/color]\n" % [NARRATION_COLOR.to_html(false), line[1]]
		else:
			text += "[color=#%s]%s:[/color] %s\n" % [NPC_COLOR.to_html(false), speaker, line[1]]
	_lines.text = text.strip_edges()
	for child in _choices.get_children():
		child.queue_free()
	var choices: Array = convo.choices
	_choice_count = choices.size()
	if not can_choose:
		var watching := Label.new()
		watching.text = "Your partner is talking..."
		watching.add_theme_color_override("font_color", NARRATION_COLOR)
		_choices.add_child(watching)
		return
	if choices.is_empty():
		_choices.add_child(_button("Leave  (Esc)", -1))
		return
	for i in choices.size():
		_choices.add_child(_button("%d.  %s" % [i + 1, choices[i].text], i))


func _button(text: String, index: int) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void: chosen.emit(index))
	return button


## Number keys pick choices, Esc / Enter leaves at the end. Returns true if
## the key was used.
func handle_key(keycode: int) -> bool:
	if not visible or not _can_choose:
		return false
	if keycode >= KEY_1 and keycode <= KEY_9:
		var index := keycode - KEY_1
		if index < _choice_count:
			chosen.emit(index)
			return true
	if keycode == KEY_ESCAPE or (_choice_count == 0 and keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
		chosen.emit(-1)
		return true
	return false
