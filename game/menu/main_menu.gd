extends Control
## Start screen: play alone, host a co-op session, or join one by address.
## The same choices work from the command line (after "--"), for testing two
## instances on one machine:
##   --solo | --host | --join=ADDRESS   [--level=arena|start|highlands]

const LEVELS := {
	"start": {"label": "Start area", "scene": "res://game/world/world.tscn"},
	"arena": {"label": "Arena", "scene": "res://game/combat/combat_arena.tscn"},
	"highlands": {"label": "Highlands (stress test)", "scene": "res://game/world/highlands.tscn"},
}
## A guest's scene: the host's level is loaded into it once the snapshot arrives.
const GUEST_SCENE := "res://game/world/world.tscn"

@onready var _level: OptionButton = %Level
@onready var _address: LineEdit = %Address
@onready var _status: Label = %Status


func _ready() -> void:
	for key: String in LEVELS:
		_level.add_item(LEVELS[key].label)
		_level.set_item_metadata(_level.item_count - 1, key)
	%Solo.pressed.connect(_solo)
	%Host.pressed.connect(_host)
	%Join.pressed.connect(_join)
	if Net.last_error != "":
		_status.text = Net.last_error
	var addresses := NetSession.host_addresses()
	%HostInfo.text = "Hosting: your partner joins with %s (port %d, UDP)." % [
		" or ".join(addresses) if not addresses.is_empty() else "your IP address", NetSession.DEFAULT_PORT]
	DisplayServer.window_set_title("glaze")
	_run_command_line.call_deferred()  # changing scene inside _ready isn't allowed


func _run_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--level="):
			var key := arg.trim_prefix("--level=")
			for i in _level.item_count:
				if _level.get_item_metadata(i) == key:
					_level.select(i)
	for arg in args:
		if arg == "--solo":
			_solo()
		elif arg == "--host":
			_host()
		elif arg.begins_with("--join="):
			_address.text = arg.trim_prefix("--join=")
			_join()


func _scene() -> String:
	return LEVELS[_level.get_item_metadata(_level.selected)].scene


func _solo() -> void:
	Net.start_solo("")
	get_tree().change_scene_to_file(_scene())


func _host() -> void:
	if Net.host("") != OK:
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
