extends Control
## Start screen: play alone, host a co-op session, or join one by address;
## a new game on a level, or a saved game (solo or hosted).
## The same choices work from the command line (after "--"), for testing two
## instances on one machine:
##   --solo | --host | --join=ADDRESS   [--level=slice|start|arena|highlands]
##   [--load=SLOT | --load=latest]

const LEVELS := {
	"slice": {"label": "Vertical slice", "scene": "res://game/world/vertical_slice.tscn"},
	"start": {"label": "Start area (test)", "scene": "res://game/world/world.tscn"},
	"arena": {"label": "Arena", "scene": "res://game/combat/combat_arena.tscn"},
	"highlands": {"label": "Highlands (stress test)", "scene": "res://game/world/highlands.tscn"},
}
## A guest's scene: the host's level is loaded into it once the snapshot arrives.
const GUEST_SCENE := "res://game/world/world.tscn"

@onready var _save: OptionButton = %Save
@onready var _level: OptionButton = %Level
@onready var _address: LineEdit = %Address
@onready var _status: Label = %Status


func _ready() -> void:
	for key: String in LEVELS:
		_level.add_item(LEVELS[key].label)
		_level.set_item_metadata(_level.item_count - 1, key)
	_save.add_item("New game")
	_save.set_item_metadata(0, "")
	for header in SaveStore.list():
		_save.add_item("Continue: " + SaveStore.describe(header))
		_save.set_item_metadata(_save.item_count - 1, header.slot)
	_save.item_selected.connect(func(_index: int) -> void: _level.disabled = _save_slot() != "")
	%Solo.pressed.connect(_solo)
	%Host.pressed.connect(_host)
	%Join.pressed.connect(_join)
	if Net.last_error != "":
		_status.text = Net.last_error
	var addresses := NetSession.host_addresses()
	%HostInfo.text = "Hosting: your partner joins with %s (port %d, UDP)." % [
		" or ".join(addresses) if not addresses.is_empty() else "your IP address", NetSession.DEFAULT_PORT]
	DisplayServer.window_set_title("glaze")
	UiStyle.apply(get_tree())
	_fit_window()
	_run_command_line.call_deferred()  # changing scene inside _ready isn't allowed


## The window opens at 1920x1080 (project settings); on a smaller screen it
## shrinks to fit and centres. The UI scales with it (canvas_items stretch).
static func _fit_window() -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED or OS.has_feature("editor_hint"):
		return
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := DisplayServer.window_get_size()
	if size.x <= screen.size.x and size.y <= screen.size.y:
		return
	var fit := minf(screen.size.x * 0.92 / size.x, screen.size.y * 0.92 / size.y)
	size = Vector2i(roundi(size.x * fit), roundi(size.y * fit))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


func _run_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--level="):
			var key := arg.trim_prefix("--level=")
			for i in _level.item_count:
				if _level.get_item_metadata(i) == key:
					_level.select(i)
	for arg in args:
		if arg.begins_with("--load="):
			var slot := arg.trim_prefix("--load=")
			for i in _save.item_count:
				if _save.get_item_metadata(i) == slot or (slot == "latest" and i == 1):
					_save.select(i)
					_level.disabled = true
	for arg in args:
		if arg == "--solo":
			_solo()
		elif arg == "--host":
			_host()
		elif arg.begins_with("--join="):
			_address.text = arg.trim_prefix("--join=")
			_join()


func _scene() -> String:
	if _save_slot() != "":
		return GUEST_SCENE  # any game scene: the save says which level to load
	return LEVELS[_level.get_item_metadata(_level.selected)].scene


func _save_slot() -> String:
	return _save.get_item_metadata(_save.selected)


## Reads the picked save for the game scene to start from. False (with the
## reason shown) if it can't be read.
func _pick_save() -> bool:
	SaveStore.pending = {}
	if _save_slot() == "":
		return true
	SaveStore.pending = SaveStore.read(_save_slot())
	if SaveStore.pending.is_empty():
		_status.text = "That save can't be loaded (damaged, or from a newer version)."
		return false
	return true


func _solo() -> void:
	if not _pick_save():
		return
	Net.start_solo("")
	get_tree().change_scene_to_file(_scene())


func _host() -> void:
	if not _pick_save():
		return
	if Net.host("") != OK:
		SaveStore.pending = {}
		_status.text = Net.last_error
		return
	get_tree().change_scene_to_file(_scene())


func _join() -> void:
	var address := _address.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	if Net.join(address) != OK:
		_status.text = Net.last_error
		return
	_status.text = "Connecting to %s..." % address
	get_tree().change_scene_to_file(GUEST_SCENE)
