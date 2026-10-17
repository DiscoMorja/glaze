extends Node3D
## Debug view for the material sim: renders SimState cells with MultiMeshes and
## lets you poke the sim through commands.
##
## Tools: 1 water  2 oil  3 fire  4 chill  5 steam  | LMB apply  | [ ] radius
## Sim:   Space pause  . single step  R reset
## Camera: WASD pan  Q/E rotate  mouse wheel zoom

const GRID_SIZE := Vector3i(32, 7, 32)
const TICKS_PER_SECOND := 4.0

enum Tool { WATER, OIL, FIRE, CHILL, STEAM }
const TOOL_NAMES := ["Water", "Oil", "Fire", "Chill", "Steam"]

const SURFACE_COLORS := {
	SimMaterials.Surface.WATER: Color(0.2, 0.45, 0.95, 0.8),
	SimMaterials.Surface.OIL: Color(0.12, 0.08, 0.03, 0.95),
	SimMaterials.Surface.ICE: Color(0.8, 0.93, 1.0, 0.9),
}
const GAS_COLORS := {
	SimMaterials.Gas.STEAM: Color(0.95, 0.95, 1.0),
	SimMaterials.Gas.SMOKE: Color(0.2, 0.2, 0.2),
}

var state: SimState

var _tool: Tool = Tool.WATER
var _radius := 1
var _paused := false
var _accumulator := 0.0
var _event_log: Array[String] = []

var _pivot: Node3D
var _camera: Camera3D
var _yaw := 45.0
var _zoom := 34.0
var _label: Label

var _solid_layer: MultiMeshInstance3D
var _surface_layer: MultiMeshInstance3D
var _gas_layer: MultiMeshInstance3D
var _fire_layer: MultiMeshInstance3D


func _ready() -> void:
	_build_scene()
	_reset()


func _process(delta: float) -> void:
	_update_camera(delta)
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
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _apply_tool(event.position)
			MOUSE_BUTTON_WHEEL_UP: _zoom = maxf(_zoom - 2.0, 8.0)
			MOUSE_BUTTON_WHEEL_DOWN: _zoom = minf(_zoom + 2.0, 80.0)


# --- Sim -----------------------------------------------------------------------

func _reset() -> void:
	state = SimState.new(_build_arena(), 1)
	_event_log.clear()
	# Oil pool on the platform (it will run down the stairs) and water in the pit.
	state.apply_command(SpawnSurfaceCommand.new(Vector3i(24, 4, 9), SimMaterials.Surface.OIL, 120, 2))
	state.apply_command(SpawnSurfaceCommand.new(Vector3i(7, 1, 23), SimMaterials.Surface.WATER, 150, 2))
	_refresh()


func _step() -> void:
	state.step()
	_log_events()
	_refresh()


func _apply_tool(screen_pos: Vector2) -> void:
	var target: Variant = _pick_cell(screen_pos)
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
		_log_events()
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


func _log_events() -> void:
	for e in state.drain_events():
		_event_log.push_front("t%d  %s at %s" % [state.tick, SimEvent.Type.keys()[e.type], e.cell])
	if _event_log.size() > 8:
		_event_log.resize(8)


## Ray-marches from the camera to the first solid cell and returns the open cell above it.
func _pick_cell(screen_pos: Vector2) -> Variant:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var grid := state.grid
	var t := 0.0
	while t < 300.0:
		var p := origin + dir * t
		var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		if grid.in_bounds(c) and grid.is_solid(c):
			var above := c + Vector3i.UP
			return above if grid.in_bounds(above) and not grid.is_solid(above) else null
		t += 0.05
	return null


# --- Rendering -------------------------------------------------------------------

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

	_pivot = Node3D.new()
	_pivot.position = Vector3(GRID_SIZE.x / 2.0, 2.0, GRID_SIZE.z / 2.0)
	add_child(_pivot)
	_camera = Camera3D.new()
	_pivot.add_child(_camera)

	_solid_layer = _make_layer(Vector3(1, 1, 1), false, false)
	_surface_layer = _make_layer(Vector3(0.96, 1, 0.96), true, false)
	_gas_layer = _make_layer(Vector3(0.95, 0.95, 0.95), true, true)
	_fire_layer = _make_layer(Vector3(0.55, 0.7, 0.55), false, true)

	var hud := CanvasLayer.new()
	add_child(hud)
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_label)


func _make_layer(box_size: Vector3, transparent: bool, unshaded: bool) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)
	return instance


func _refresh() -> void:
	var grid := state.grid
	var solids: Array[Transform3D] = []
	var solid_colors: Array[Color] = []
	var surfaces: Array[Transform3D] = []
	var surface_colors: Array[Color] = []
	var gases: Array[Transform3D] = []
	var gas_colors: Array[Color] = []
	var fires: Array[Transform3D] = []
	var fire_colors: Array[Color] = []

	for i in grid.cell_count:
		var c := grid.coord(i)
		var base := Vector3(c.x + 0.5, c.y, c.z + 0.5)
		if grid.solid[i] != 0:
			if not grid.is_solid(c + Vector3i.UP):
				var shade := 0.32 + 0.09 * c.y
				solids.append(Transform3D(Basis(), base + Vector3(0, 0.5, 0)))
				solid_colors.append(Color(shade, shade * 0.95, shade * 0.85))
			continue

		var surface: int = grid.surface_type[i]
		if surface != SimMaterials.Surface.NONE:
			var fill := clampf(grid.surface_amount[i] / float(SimMaterials.AMOUNT_FULL), 0.0, 1.0)
			var thickness := 0.04 + 0.3 * fill
			var basis := Basis().scaled(Vector3(1, thickness, 1))
			surfaces.append(Transform3D(basis, base + Vector3(0, thickness / 2.0, 0)))
			surface_colors.append(SURFACE_COLORS[surface])

		var gas: int = grid.gas_type[i]
		if gas != SimMaterials.Gas.NONE:
			var color: Color = GAS_COLORS[gas]
			color.a = clampf(grid.gas_amount[i] / float(SimMaterials.AMOUNT_FULL), 0.05, 0.6)
			gases.append(Transform3D(Basis(), base + Vector3(0, 0.5, 0)))
			gas_colors.append(color)

		var fire: int = grid.fire[i]
		if fire > 0:
			var heat := fire / float(SimMaterials.FIRE_MAX)
			var basis := Basis().scaled(Vector3(1, 0.3 + 0.7 * heat, 1))
			fires.append(Transform3D(basis, base + Vector3(0, 0.35 * (0.3 + 0.7 * heat), 0)))
			fire_colors.append(Color(1.0, 0.35 + 0.5 * heat, 0.05))

	_fill_layer(_solid_layer, solids, solid_colors)
	_fill_layer(_surface_layer, surfaces, surface_colors)
	_fill_layer(_gas_layer, gases, gas_colors)
	_fill_layer(_fire_layer, fires, fire_colors)
	_update_label()


func _fill_layer(layer: MultiMeshInstance3D, transforms: Array[Transform3D], colors: Array[Color]) -> void:
	var multimesh := layer.multimesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colors[i])


func _update_camera(delta: float) -> void:
	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): pan.z -= 1
	if Input.is_key_pressed(KEY_S): pan.z += 1
	if Input.is_key_pressed(KEY_A): pan.x -= 1
	if Input.is_key_pressed(KEY_D): pan.x += 1
	if Input.is_key_pressed(KEY_Q): _yaw += 90.0 * delta
	if Input.is_key_pressed(KEY_E): _yaw -= 90.0 * delta
	_pivot.rotation_degrees.y = _yaw
	_pivot.position += _pivot.basis * pan * 20.0 * delta
	var pitch := deg_to_rad(55.0)
	_camera.position = Vector3(0, sin(pitch), cos(pitch)) * _zoom
	_camera.look_at(_pivot.global_position)


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
