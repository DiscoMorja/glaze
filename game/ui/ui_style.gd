class_name UiStyle
extends RefCounted
## The one look every window shares: colours, panel and button styles, and a
## Theme set on the root window (apply()), so plain Buttons, Labels, line
## edits and tooltips match without per-panel overrides. Windows use
## window_style(); item grids use ItemSlot; titles use title().

const BG := Color(0.07, 0.08, 0.1, 0.95)
const BG_SOLID := Color(0.07, 0.08, 0.1, 0.98)
const BORDER := Color(0.35, 0.38, 0.42)
const SLOT_BG := Color(0.12, 0.13, 0.15)
const TEXT := Color(0.9, 0.91, 0.93)
const TEXT_DIM := Color(0.62, 0.65, 0.7)
const TEXT_WARM := Color(1.0, 0.92, 0.7)
const ACCENT := Color(1.0, 0.85, 0.3)
const WARNING := Color(1.0, 0.65, 0.3)
const GOOD := Color(0.55, 1.0, 0.6)
const BAD := Color(1.0, 0.45, 0.4)
const FONT_SIZE := 14
const SMALL := 12
const TITLE := 18

static var _theme: Theme


## Puts the shared theme on the root window (once per run is enough).
static func apply(tree: SceneTree) -> void:
	tree.root.theme = theme()


static func window_style(solid: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_SOLID if solid else BG
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	return style


## A window's title row text.
static func title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", TITLE)
	return label


static func dim(text: String, size: int = SMALL) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_DIM)
	return label


static func button(text: String, on_press: Callable, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	var states := {
		"normal": [Color(0.15, 0.16, 0.19), BORDER],
		"hover": [Color(0.2, 0.22, 0.26), Color(0.6, 0.63, 0.68)],
		"pressed": [Color(0.24, 0.21, 0.12), ACCENT],
		"disabled": [Color(0.11, 0.12, 0.14), Color(0.22, 0.23, 0.26)],
		"focus": [Color(0, 0, 0, 0), Color(0, 0, 0, 0)],
	}
	for type: String in ["Button", "OptionButton", "MenuButton"]:
		for state: String in states:
			var box := StyleBoxFlat.new()
			box.bg_color = states[state][0]
			box.border_color = states[state][1]
			box.set_border_width_all(1)
			box.set_corner_radius_all(4)
			box.content_margin_left = 10
			box.content_margin_right = 10
			box.content_margin_top = 5
			box.content_margin_bottom = 5
			if state == "focus":
				box.draw_center = false
			t.set_stylebox(state, type, box)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, ACCENT)
		t.set_color("font_disabled_color", type, Color(0.45, 0.47, 0.5))
	t.set_color("font_color", "Label", TEXT)
	var edit := StyleBoxFlat.new()
	edit.bg_color = Color(0.1, 0.11, 0.13)
	edit.border_color = BORDER
	edit.set_border_width_all(1)
	edit.set_corner_radius_all(4)
	edit.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", edit)
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = ACCENT
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_stylebox("panel", "PanelContainer", window_style())
	t.set_stylebox("panel", "PopupMenu", window_style(true))
	var tip := window_style(true)
	tip.border_color = Color(ACCENT, 0.8)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT_WARM)
	t.set_font_size("font_size", "TooltipLabel", 13)
	_theme = t
	return t
