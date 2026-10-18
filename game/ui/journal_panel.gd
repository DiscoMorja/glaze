class_name JournalPanel
extends PanelContainer
## Known quests (J toggles it): title, where things stand, and how they ended.

var _text: RichTextLabel
var _shown := {}


func _ready() -> void:
	visible = false
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 12
	offset_top = 180
	custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.94)
	style.border_color = Color(0.45, 0.42, 0.32)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(356, 0)
	add_child(_text)


func toggle() -> void:
	visible = not visible
	_shown = {}


func show_journal(state: SimState) -> void:
	if not visible or state.quests == _shown:
		return
	_shown = state.quests.duplicate(true)
	var text := "[b]Journal[/b]   [color=#888888](J to close)[/color]\n\n"
	var any := false
	for id in QuestRules.order:
		if not state.quests.get(id, {}).get("known", false):
			continue
		any = true
		var entry := QuestRules.journal(state, id)
		var mark := "[color=#8fd18f]Done[/color]" if entry[2] else "[color=#e0c070]Active[/color]"
		text += "[b]%s[/b]  %s\n%s\n\n" % [entry[0], mark, entry[1]]
	if not any:
		text += "[i]Nothing yet. Talk to people.[/i]"
	_text.text = text.strip_edges()
