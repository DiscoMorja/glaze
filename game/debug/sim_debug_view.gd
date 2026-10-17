extends Node3D
## Debug view for the material sim: renders SimState cells and lets you poke
## the sim through commands.
##
## Tools: 1 water  2 oil  3 fire  4 chill  5 steam  | LMB apply  | [ ] radius
## Sim:   Space pause  . single step  R reset
## Camera: WASD pan  Q/E rotate  mouse wheel zoom

const GRID_SIZE := Vector3i(32, 7, 32)
const TICKS_PER_SECOND := 4.0

enum Tool { WATER, OIL, FIRE, CHILL, STEAM }
const TOOL_NAMES := ["Water", "Oil", "Fire", "Chill", "Steam"]

var state: SimState

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
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_apply_tool(event.position)


func _reset() -> void:
	state = SimState.new(_build_arena(), 1)
	_event_log.clear()
	# Oil pool on the platform (it will run down the stairs) and water in the pit.
	state.apply_command(SpawnSurfaceCommand.new(Vector3i(24, 4, 9), SimMaterials.Surface.OIL, 120, 2))
	state.apply_command(SpawnSurfaceCommand.new(Vector3i(7, 1, 23), SimMaterials.Surface.WATER, 150, 2))
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


## Floor two cells thick (walk layer y = 2) with a pit, a raised platform with a
## stair, and a wall with a gap.
func _build_arena() -> SimGrid:
	var grid := SimGrid.new(GRID_SIZE)
	var max_x := GRID_SIZE.x - 1
	var max_z := GRID_SIZE.z - 1
	grid.fill_solid(Vector3i(0, 0, 0), Vector3i(max_x, 1, max_z))
	grid.fill_solid(Vector3i(3, 1, 19), Vector3i(11, 1, 28), false)  # pit, floor at y = 0
	grid.fill_solid(Vector3i(20, 2, 4), Vector3i(29, 3, 14))  # platform, walk layer y = 4
	grid.fill_solid(Vector3i(18, 2, 7), Vector3i(19, 2, 11))  # stair step, walk layer y = 3
	grid.fill_solid(Vector3i(14, 2, 16), Vector3i(14, 3, max_z))  # wall
	grid.fill_solid(Vector3i(14, 2, 22), Vector3i(14, 3, 23), false)  # gap in the wall
	return grid


func _refresh() -> void:
	for e in state.drain_events():
		_event_log.push_front("t%d  %s at %s" % [state.tick, SimEvent.Type.keys()[e.type], e.cell])
	if _event_log.size() > 8:
		_event_log.resize(8)
	_renderer.render(state.grid)
	_update_label()


func _build_scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.11)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	_renderer = SimGridRenderer.new()
	add_child(_renderer)
	_rig = CameraRig.new()
	_rig.position = Vector3(GRID_SIZE.x / 2.0, 2.0, GRID_SIZE.z / 2.0)
	_rig.zoom = 34.0
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
