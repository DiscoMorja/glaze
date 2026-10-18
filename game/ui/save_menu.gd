class_name SaveMenu
extends PanelContainer
## The in-game menu (Esc with nothing aimed): save under a name, load or
## delete a save, quit to the main menu. Only the host saves and loads; a
## guest just sees the quit button.

signal save_requested(title: String)
signal load_requested(slot: String)
signal quit_requested

var _name: LineEdit
var _save_button: Button
var _note: Label
var _list: VBoxContainer
var _can_save_reason := ""


func _ready() -> void:
	visible = false
	custom_minimum_size = Vector2(560, 0)
	add_theme_stylebox_override("panel", UiStyle.window_style(true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(UiStyle.title("Menu   (Esc to close)"))
	var row := HBoxContainer.new()
	box.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = "Save name"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_submitted.connect(func(_text: String) -> void: _save())
	row.add_child(_name)
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(_save)
	row.add_child(_save_button)
	_note = Label.new()
	_note.add_theme_color_override("font_color", UiStyle.TEXT_DIM)
	_note.add_theme_font_size_override("font_size", 13)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var quit := Button.new()
	quit.text = "Quit to main menu"
	quit.pressed.connect(func() -> void: quit_requested.emit())
	box.add_child(quit)


## Opens the menu. can_save_reason: empty if saving is possible right now,
## else why not. is_host: guests can't save or load.
func open(is_host: bool, can_save_reason: String) -> void:
	visible = true
	_can_save_reason = can_save_reason
	_name.editable = is_host
	_save_button.disabled = not is_host or can_save_reason != ""
	if not is_host:
		_note.text = "The host saves and loads the game."
	elif can_save_reason != "":
		_note.text = can_save_reason
	else:
		_note.text = "F5 quicksave, F9 quickload. The game also autosaves."
	_name.text = ""
	_fill(is_host)
	_center.call_deferred()  # once the new rows have their size
	if is_host:
		_name.grab_focus()


func _center() -> void:
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).floor()


func close() -> void:
	visible = false
	_name.release_focus()


func _save() -> void:
	if _save_button.disabled:
		return
	save_requested.emit(_name.text.strip_edges())


## Rebuilds the list of saves (after saving or deleting).
func _fill(is_host: bool) -> void:
	for child in _list.get_children():
		child.queue_free()
	if not is_host:
		return
	var saves := SaveStore.list()
	if saves.is_empty():
		var none := Label.new()
		none.text = "No saves yet."
		_list.add_child(none)
	for header in saves:
		var row := HBoxContainer.new()
		_list.add_child(row)
		var info := Label.new()
		info.text = "%s\n%s" % [SaveStore.describe(header), header.get("party", "")]
		info.add_theme_font_size_override("font_size", 13)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		row.add_child(info)
		var slot: String = header.slot
		var load_button := Button.new()
		load_button.text = "Load"
		load_button.pressed.connect(func() -> void: load_requested.emit(slot))
		row.add_child(load_button)
		var delete := Button.new()
		delete.text = "Delete"
		delete.pressed.connect(func() -> void:
			if delete.text != "Sure?":
				delete.text = "Sure?"  # second click deletes
				return
			SaveStore.remove(slot)
			_fill(true)
			_center.call_deferred())
		row.add_child(delete)


## Called after a save went through: refresh the list.
func saved() -> void:
	_name.text = ""
	_fill(true)
	_center.call_deferred()
