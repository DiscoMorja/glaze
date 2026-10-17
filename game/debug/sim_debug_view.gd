extends Node3D
## Debug view for the material sim: loads a level scene (the arena by
## default), renders its sim cells and lets you poke the sim through commands.
## Characters in the level are ignored here.
##
## Tools: 1 water  2 oil  3 fire  4 chill  5 steam  | LMB apply  | [ ] radius
## Sim:   Space pause  . single step  R reset
## Camera: WASD pan  Q/E rotate  mouse wheel zoom

const TICKS_PER_SECOND := 4.0

enum Tool { WATER, OIL, FIRE, CHILL, STEAM }
const TOOL_NAMES := ["Water", "Oil", "Fire", "Chill", "Steam"]

## Level to load; edit the layout in that scene.
@export var level_scene: PackedScene = preload("res://levels/arena/arena.tscn")

var state: SimState
var _level: GameLevel

var _tool: Tool = Tool.WATER
var _radius := 1
var _paused := false
var _accumulator := 0.0
var _event_log: Array[String] = []

var _renderer: SimGridRenderer
var _rig: CameraRig
var _label: Label


func _ready() -> void:
	_build_scene()
	_reset()


func _process(delta: float) -> void:
	if state == null:
		return
	if not _paused:
		_accumulator += delta
		var tick_time := 1.0 / TICKS_PER_SECOND
		while _accumulator >= tick_time:
			_accumulator -= tick_time
			_step()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _tool = Tool.WATER
			KEY_2: _tool = Tool.OIL
			KEY_3: _tool = Tool.FIRE
			KEY_4: _tool = Tool.CHILL
			KEY_5: _tool = Tool.STEAM
			KEY_BRACKETLEFT: _radius = maxi(_radius - 1, 0)
			KEY_BRACKETRIGHT: _radius = mini(_radius + 1, 5)
			KEY_SPACE: _paused = not _paused
			KEY_PERIOD: _step()
			KEY_R: _reset()
		_update_label()
	elif state != null and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_apply_tool(event.position)


func _reset() -> void:
	state = null
	if _level != null:
		_level.queue_free()
	_level = level_scene.instantiate() as GameLevel
	_level.start_in_combat = false
	add_child(_level)
	var baked: SimState = await _level.bake()
	state = baked
	_rig.position = Vector3(state.grid.size.x / 2.0, 2.0, state.grid.size.z / 2.0)
	_event_log.clear()
	_refresh()


func _step() -> void:
	state.step()
	_refresh()


func _apply_tool(screen_pos: Vector2) -> void:
	var target: Variant = _rig.pick_cell(state, screen_pos)
	if target == null:
		return
	var cell: Vector3i = target
	var command: SimCommand
	match _tool:
		Tool.WATER: command = SpawnSurfaceCommand.new(cell, SimMaterials.Surface.WATER, 60, _radius)
		Tool.OIL: command = SpawnSurfaceCommand.new(cell, SimMaterials.Surface.OIL, 60, _radius)
		Tool.FIRE: command = IgniteCommand.new(cell, _radius)
		Tool.CHILL: command = ChillCommand.new(cell, _radius)
		Tool.STEAM: command = SpawnGasCommand.new(cell, SimMaterials.Gas.STEAM, 80, _radius)
	if state.apply_command(command):
		_refresh()


func _refresh() -> void:
	for e in state.drain_events():
		_event_log.push_front("t%d  %s at %s" % [state.tick, SimEvent.Type.keys()[e.type], e.cell])
	if _event_log.size() > 8:
		_event_log.resize(8)
	_renderer.render(state.grid)
	_update_label()


func _build_scene() -> void:
	_renderer = SimGridRenderer.new()
	_renderer.show_solids = false  # the level's own geometry is visible
	add_child(_renderer)
	_rig = CameraRig.new()
	_rig.zoom = 30.0
	add_child(_rig)

	var hud := CanvasLayer.new()
	add_child(hud)
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_label)


func _update_label() -> void:
	if _label == null or state == null:
		return
	var lines: Array[String] = [
		"Tick %d  %s   Tool: %s  radius %d" % [state.tick, "PAUSED" if _paused else "running", TOOL_NAMES[_tool], _radius],
		"1 water  2 oil  3 fire  4 chill  5 steam  |  LMB apply  [ ] radius",
		"Space pause  . step  R reset  |  WASD pan  Q/E rotate  wheel zoom",
		"",
	]
	lines.append_array(_event_log)
	_label.text = "\n".join(lines)
