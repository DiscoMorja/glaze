extends Node3D
## M1 combat greybox. Every player and AI action is a SimCommand; hovering shows
## a preview computed by running the command on a copy of the sim.
##
## Click a party member to select it. Tab cycles party members.
## Modes: M move (default)  A attack  1 Firebolt  2 Rain  3 Teleport  4 Shove  5 Steal
## Teleport takes two clicks: the target, then where to put it.
## Enter: end turn   Esc / RMB: back to move   R: restart

enum Mode { MOVE, ATTACK, FIREBOLT, RAIN, TELEPORT, SHOVE, STEAL }
const MODE_NAMES := ["Move", "Attack", "Firebolt", "Rain", "Teleport", "Shove", "Steal"]
const MODE_ABILITY := {
	Mode.FIREBOLT: SimAbilities.Ability.FIREBOLT,
	Mode.RAIN: SimAbilities.Ability.RAIN,
	Mode.TELEPORT: SimAbilities.Ability.TELEPORT,
	Mode.SHOVE: SimAbilities.Ability.SHOVE,
	Mode.STEAL: SimAbilities.Ability.STEAL,
}
const ENEMY_ACTION_DELAY := 0.45
const LOG_LINES := 14

const COLOR_CURSOR := Color(1, 1, 1, 0.45)
const COLOR_INVALID := Color(1, 0.15, 0.1, 0.5)
const COLOR_PATH := Color(0.3, 0.9, 1.0, 0.45)
const COLOR_FIRE := Color(1.0, 0.45, 0.05, 0.55)
const COLOR_SURFACE := Color(0.6, 0.8, 1.0, 0.45)
const COLOR_SELECTED := Color(0.3, 1.0, 0.4, 0.6)
const COLOR_TARGET := Color(1.0, 0.85, 0.2, 0.6)

var state: SimState

var _mode: Mode = Mode.MOVE
var _selected_id := -1
var _teleport_target: Variant = null
var _hover: Variant = null
var _busy := false
var _log: Array[String] = []
var _preview_text := ""
var _mouse_pos := Vector2.ZERO

var _grid_renderer: SimGridRenderer
var _entity_renderer: SimEntityRenderer
var _markers: CellMarkers
var _rig: CameraRig
var _hud: Label
var _log_label: Label


func _ready() -> void:
	_build_scene()
	_restart()


func _process(_delta: float) -> void:
	_update_hover()


func _update_hover() -> void:
	var hover: Variant = _rig.pick_cell(state, _mouse_pos)
	if typeof(hover) != typeof(_hover) or hover != _hover:
		_hover = hover
		_update_preview()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_pos = event.position
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_M: _set_mode(Mode.MOVE)
			KEY_A: _set_mode(Mode.ATTACK)
			KEY_1: _set_mode(Mode.FIREBOLT)
			KEY_2: _set_mode(Mode.RAIN)
			KEY_3: _set_mode(Mode.TELEPORT)
			KEY_4: _set_mode(Mode.SHOVE)
			KEY_5: _set_mode(Mode.STEAL)
			KEY_ESCAPE: _set_mode(Mode.MOVE)
			KEY_TAB: _select_next()
			KEY_ENTER, KEY_KP_ENTER: _end_turn()
			KEY_R: _restart()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_update_hover()
				_click()
			MOUSE_BUTTON_RIGHT: _set_mode(Mode.MOVE)


# --- Flow ----------------------------------------------------------------------

func _restart() -> void:
	state = ArenaBuilder.build()
	_log.clear()
	_selected_id = -1
	_busy = false
	_consume_events()
	_select_next()
	_set_mode(Mode.MOVE)


func _click() -> void:
	if _busy or _hover == null or not _is_players_turn():
		return
	var cell: Vector3i = _hover
	var clicked := state.entity_at(cell)
	var own_unit := clicked != null and clicked.faction == SimEntity.Faction.PLAYERS and clicked.takes_turns()
	if own_unit and (_mode == Mode.MOVE or _mode == Mode.ATTACK):
		_selected_id = clicked.id
		_refresh()
		return
	if _mode == Mode.TELEPORT and _teleport_target == null:
		if clicked != null:
			_teleport_target = cell
			_update_preview()
		return
	var command := _build_command(cell)
	if command != null and state.apply_command(command):
		if _mode == Mode.TELEPORT:
			_set_mode(Mode.MOVE)
		_after_action()


func _end_turn() -> void:
	if _busy or not _is_players_turn():
		return
	state.apply_command(EndTurnCommand.new(SimEntity.Faction.PLAYERS))
	_after_action()


func _after_action() -> void:
	_consume_events()
	_update_preview()
	if state.combat.active and state.combat.side == SimEntity.Faction.ENEMIES:
		_run_enemy_turn()


func _run_enemy_turn() -> void:
	_busy = true
	_update_preview()
	while state.combat.active and state.combat.side == SimEntity.Faction.ENEMIES:
		await get_tree().create_timer(ENEMY_ACTION_DELAY).timeout
		if not state.apply_command(SimpleAi.next_command(state)):
			push_error("AI produced an invalid command")
			break
		_consume_events()
	_busy = false
	var selected := state.get_entity(_selected_id)
	if selected == null or not selected.is_alive():
		_select_next()
	_update_preview()


func _consume_events() -> void:
	var events := state.drain_events()
	for line in Narrator.describe_all(state, events):
		_log.push_front(line)
	if _log.size() > LOG_LINES:
		_log.resize(LOG_LINES)
	_grid_renderer.render(state.grid)
	_entity_renderer.render(state, events)
	_refresh()


func _is_players_turn() -> bool:
	return state.combat.active and state.combat.side == SimEntity.Faction.PLAYERS


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_teleport_target = null
	_update_preview()


func _select_next() -> void:
	var party := CombatRules.fighters(state, SimEntity.Faction.PLAYERS)
	if party.is_empty():
		_selected_id = -1
	else:
		var index := 0
		for i in party.size():
			if party[i].id == _selected_id:
				index = (i + 1) % party.size()
		_selected_id = party[index].id
	_refresh()


func _build_command(cell: Vector3i) -> SimCommand:
	var actor := state.get_entity(_selected_id)
	if actor == null:
		return null
	match _mode:
		Mode.MOVE:
			return MoveCommand.new(actor.id, cell)
		Mode.ATTACK:
			var target := state.entity_at(cell)
			return AttackCommand.new(actor.id, target.id) if target != null else null
		Mode.TELEPORT:
			if _teleport_target == null:
				return null
			return CastCommand.new(actor.id, SimAbilities.Ability.TELEPORT, _teleport_target, cell)
	return CastCommand.new(actor.id, MODE_ABILITY[_mode], cell)


# --- Preview -------------------------------------------------------------------

## Runs the hovered command on a copy of the sim and shows what would happen:
## immediately, and by the end of the turn once the world has advanced.
func _update_preview() -> void:
	_preview_text = ""
	var cells: Array[Vector3i] = []
	var colors: Array[Color] = []
	var texts := {}
	var actor := state.get_entity(_selected_id)
	if actor != null and actor.is_alive():
		cells.append(actor.cell)
		colors.append(COLOR_SELECTED)
	if _teleport_target != null:
		cells.append(_teleport_target)
		colors.append(COLOR_TARGET)

	if not _busy and _hover != null and _is_players_turn() and actor != null:
		var cell: Vector3i = _hover
		var command := _build_command(cell)
		if command == null:
			cells.append(cell)
			colors.append(COLOR_CURSOR)
			if _mode == Mode.TELEPORT:
				_preview_text = "Pick something to teleport"
		elif not command.validate(state):
			cells.append(cell)
			colors.append(COLOR_INVALID)
			_preview_text = "Can't do that"
		else:
			_preview_outcome(command, actor, cells, colors, texts)
			cells.append(cell)
			colors.append(COLOR_CURSOR)

	_markers.show_cells(cells, colors)
	_entity_renderer.set_preview(texts)
	_refresh()


func _preview_outcome(command: SimCommand, actor: SimEntity, cells: Array[Vector3i], colors: Array[Color], texts: Dictionary) -> void:
	var after := state.duplicate_state()
	after.apply_command(command)
	var forecast := after.duplicate_state()
	forecast.step_ticks(CombatRules.TICKS_PER_SIDE_TURN)

	if command is MoveCommand:
		for c in SimPathfinder.find_path(state, actor.cell, (command as MoveCommand).destination, actor.id):
			cells.append(c)
			colors.append(COLOR_PATH)
	if command is CastCommand and (command as CastCommand).ability == SimAbilities.Ability.TELEPORT:
		var moved := after.get_entity(state.entity_at((command as CastCommand).target).id)
		cells.append(moved.cell)
		colors.append(COLOR_TARGET)

	var grid := state.grid
	for i in grid.cell_count:
		if forecast.grid.fire[i] > 0 and grid.fire[i] == 0:
			cells.append(grid.coord(i))
			colors.append(COLOR_FIRE)
		elif after.grid.surface_type[i] != grid.surface_type[i]:
			cells.append(grid.coord(i))
			colors.append(COLOR_SURFACE)

	for e in state.entities:
		if not e.is_alive():
			continue
		var now_hp := after.get_entity(e.id).hp
		var later_hp := forecast.get_entity(e.id).hp
		if now_hp == e.hp and later_hp == e.hp:
			continue
		var parts: Array[String] = []
		if now_hp == 0:
			parts.append("dies")
		elif now_hp != e.hp:
			parts.append("-%d" % (e.hp - now_hp))
		if now_hp > 0 and later_hp == 0:
			parts.append("dies by turn end")
		elif later_hp != now_hp:
			parts.append("-%d by turn end" % (now_hp - later_hp))
		texts[e.id] = "  ".join(parts)

	var cost := actor.ap - after.get_entity(actor.id).ap
	_preview_text = "%s: %d AP" % [MODE_NAMES[_mode], cost]


# --- Scene & HUD ---------------------------------------------------------------

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

	_grid_renderer = SimGridRenderer.new()
	add_child(_grid_renderer)
	_entity_renderer = SimEntityRenderer.new()
	add_child(_entity_renderer)
	_markers = CellMarkers.new()
	add_child(_markers)

	_rig = CameraRig.new()
	_rig.position = Vector3(ArenaBuilder.SIZE.x / 2.0, 2.0, ArenaBuilder.SIZE.z / 2.0)
	_rig.zoom = 24.0
	add_child(_rig)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = _make_label(canvas, Vector2(12, 10))
	_log_label = _make_label(canvas, Vector2(12, 230))


func _make_label(parent: Node, pos: Vector2) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


func _refresh() -> void:
	if _hud == null or state == null:
		return
	_entity_renderer.set_selected(_selected_id)
	var lines: Array[String] = []
	if state.combat.active:
		lines.append("Round %d — %s" % [state.combat.round_number, "Your turn" if _is_players_turn() else "Enemy turn..."])
	else:
		lines.append("Combat over — press R to restart")
	var actor := state.get_entity(_selected_id)
	if actor != null:
		var items := ", ".join(actor.inventory) if not actor.inventory.is_empty() else "nothing"
		lines.append("%s  HP %d/%d  AP %d   weapon: %s   carrying: %s" % [actor.name, actor.hp, actor.max_hp, actor.ap, actor.weapon if actor.weapon != "" else "none", items])
	lines.append("Mode: %s   %s" % [MODE_NAMES[_mode], _preview_text])
	lines.append("")
	lines.append("M move  A attack (2)  1 Firebolt (2)  2 Rain (2)  3 Teleport (2)  4 Shove (1)  5 Steal (1)")
	lines.append("Click party member / Tab: select   Enter: end turn   Esc/RMB: cancel   R: restart")
	lines.append("WASD pan   Q/E rotate   wheel zoom")
	_hud.text = "\n".join(lines)
	_log_label.text = "\n".join(_log)
