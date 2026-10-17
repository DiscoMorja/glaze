class_name ActionBar
extends PanelContainer
## The selected character's actions as buttons (key, name, AP cost). Hovering
## a button shows its tooltip right away above the bar. Reports presses and
## hovers so the arena can aim and highlight.

signal action_pressed(action: int)
## ActionInfo.NONE when the mouse leaves the bar.
signal action_hovered(action: int)

var _row: HBoxContainer
var _tip_panel: PanelContainer
var _tip: Label
var _actions: Array[int] = []
var _tips: Array[String] = []
var _tip_index := -1


func _ready() -> void:
	# Pinned bottom centre, above the party bar.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -96
	offset_bottom = -96
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.13, 0.85)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(4)
	add_theme_stylebox_override("panel", style)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	add_child(_row)

	# Floats above the bar; top_level keeps it out of the bar's layout.
	_tip_panel = PanelContainer.new()
	_tip_panel.top_level = true
	_tip_panel.visible = false
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = Color(0.06, 0.06, 0.08, 0.95)
	tip_style.border_color = Color(1.0, 0.8, 0.15, 0.8)
	tip_style.set_border_width_all(1)
	tip_style.set_corner_radius_all(4)
	tip_style.set_content_margin_all(8)
	_tip_panel.add_theme_stylebox_override("panel", tip_style)
	_tip = Label.new()
	_tip.custom_minimum_size = Vector2(320, 0)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_tip_panel.add_child(_tip)
	add_child(_tip_panel)


func show_actions(actor: SimEntity, aimed: int, usable: bool) -> void:
	var actions: Array[int] = []
	if actor != null:
		actions = ActionInfo.actions_for(actor)
	if actions != _actions:
		_rebuild(actions)
	_tips.clear()
	for i in _actions.size():
		var button: Button = _row.get_child(i)
		var action := _actions[i]
		_tips.append(ActionInfo.tooltip(action, actor))
		var wait := ActionInfo.remaining(action, actor)
		button.text = _label(i, action, wait)
		button.disabled = not usable or actor.ap < ActionInfo.cost(action) or wait > 0
		button.set_pressed_no_signal(action == aimed)
	visible = not _actions.is_empty()
	if not visible:
		_tip_panel.visible = false
	elif _tip_panel.visible and _tip_index < _tips.size():
		_tip.text = _tips[_tip_index]


func _rebuild(actions: Array[int]) -> void:
	_actions = actions.duplicate()
	for child in _row.get_children():
		child.queue_free()
		_row.remove_child(child)
	for i in _actions.size():
		var action := _actions[i]
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(88, 56)
		button.text = _label(i, action, 0)
		button.pressed.connect(func() -> void: action_pressed.emit(action))
		button.mouse_entered.connect(func() -> void:
			_show_tip(i)
			action_hovered.emit(action))
		button.mouse_exited.connect(func() -> void:
			_tip_panel.visible = false
			action_hovered.emit(ActionInfo.NONE))
		_row.add_child(button)


## Key, name and AP cost; while cooling down, the turns left instead of the cost.
static func _label(slot: int, action: int, wait: int) -> String:
	var second := "ready in %d" % wait if wait > 0 else "%d AP" % ActionInfo.cost(action)
	return "%d  %s\n%s" % [slot + 1, ActionInfo.name_of(action), second]


func _show_tip(index: int) -> void:
	if index >= _tips.size():
		return
	_tip_index = index
	_tip.text = _tips[index]
	_tip_panel.visible = true
	_tip_panel.reset_size()
	_place_tip.call_deferred()


func _place_tip() -> void:
	var bar := get_global_rect()
	_tip_panel.global_position = Vector2(bar.position.x + (bar.size.x - _tip_panel.size.x) / 2.0, bar.position.y - _tip_panel.size.y - 6.0)
