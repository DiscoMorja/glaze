extends Node3D
## M1 combat greybox. Every player and AI action is a SimCommand; hovering shows
## a preview computed by running the command on a copy of the sim.
##
## Select: click a party card, F1-F4, Tab (next with AP left), or click a party
## member in Move mode. Selecting always returns to Move mode.
## Modes: M move (default)  A attack  1 Firebolt  2 Rain  3 Teleport  4 Shove  5 Steal
## Abilities return to Move mode after use. Actions that would hurt your own
## party need a second click to confirm.
## Teleport takes two clicks: the target, then where to put it.
## Enter: end turn (asks first if anyone has AP left)   Esc / RMB: cancel   R: restart

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
const COLOR_PATH := Color(0.3, 0.9, 1.0, 0.5)
const COLOR_FIRE := Color(1.0, 0.45, 0.05, 0.55)
const COLOR_SURFACE := Color(0.6, 0.8, 1.0, 0.45)
const COLOR_SELECTED := Color(0.3, 1.0, 0.4, 0.75)
const COLOR_HAS_AP := Color(0.3, 1.0, 0.4, 0.3)
const COLOR_TARGET := Color(1.0, 0.85, 0.2, 0.6)
const COLOR_RANGE := Color(0.35, 0.6, 1.0, 0.16)
const COLOR_NO_SIGHT := Color(1.0, 0.3, 0.25, 0.12)

var state: SimState

var _mode: Mode = Mode.MOVE
var _selected_id := -1
var _teleport_target: Variant = null
var _hover: Variant = null
var _busy := false
var _log: Array[String] = []
var _preview_text := ""
var _preview_cost := 0
var _preview_hurts_allies: Array[String] = []
var _confirm_cell: Variant = null
var _confirming_end_turn := false
var _turn_start_ap := {}
var _mouse_pos := Vector2.ZERO

var _grid_renderer: SimGridRenderer
var _entity_renderer: SimEntityRenderer
var _markers: CellMarkers
var _range_markers: CellMarkers
var _rig: CameraRig
var _hud: Label
var _log_label: Label
var _party_bar: PartyBar
var _dialog: PanelContainer
var _dialog_label: Label


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
		if _confirming_end_turn:
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER, KEY_Y: _end_turn(true)
				KEY_ESCAPE, KEY_N: _cancel_end_turn()
			return
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
			KEY_F1: _select_index(0)
			KEY_F2: _select_index(1)
			KEY_F3: _select_index(2)
			KEY_F4: _select_index(3)
			KEY_ENTER, KEY_KP_ENTER: _end_turn()
			KEY_R: _restart()
	elif event is InputEventMouseButton and event.pressed:
		if _confirming_end_turn:
			return
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
	_confirming_end_turn = false
	_dialog.visible = false
	_capture_turn_start_ap()
	_consume_events()
	_select_next()


func _click() -> void:
	if _busy or _hover == null or not _is_players_turn():
		return
	var cell: Vector3i = _hover
	var clicked := state.entity_at(cell)
	var own_unit := clicked != null and clicked.faction == SimEntity.Faction.PLAYERS and clicked.takes_turns()
	if own_unit and (_mode == Mode.MOVE or _mode == Mode.ATTACK):
		_select(clicked.id)
		return
	if _mode == Mode.TELEPORT and _teleport_target == null:
		if _can_teleport_target(clicked):
			_teleport_target = cell
			_update_range()
			_update_preview()
		return
	var command := _build_command(cell)
	if command == null or not command.validate(state):
		return
	if not _preview_hurts_allies.is_empty() and _confirm_cell != _hover:
		_confirm_cell = cell
		_update_preview()
		return
	state.apply_command(command)
	if not command is MoveCommand:
		_mode = Mode.MOVE
		_teleport_target = null
	_after_action()


## Ends the players' turn. Asks first if anyone still has AP, unless confirmed.
func _end_turn(confirmed: bool = false) -> void:
	if _busy or not _is_players_turn():
		return
	var idle: Array[String] = []
	for e in CombatRules.fighters(state, SimEntity.Faction.PLAYERS):
		if e.ap > 0:
			idle.append("%s (%d AP)" % [e.name, e.ap])
	if not confirmed and not idle.is_empty():
		_confirming_end_turn = true
		_dialog_label.text = "Unspent AP: %s\n\nEnd the turn anyway?\n\nEnter / Y: end turn      Esc / N: keep playing" % ", ".join(idle)
		_dialog.visible = true
		return
	_cancel_end_turn()
	state.apply_command(EndTurnCommand.new(SimEntity.Faction.PLAYERS))
	_after_action()


func _cancel_end_turn() -> void:
	_confirming_end_turn = false
	_dialog.visible = false


func _after_action() -> void:
	_confirm_cell = null
	_consume_events()
	_update_range()
	_update_preview()
	if state.combat.active and state.combat.side == SimEntity.Faction.ENEMIES:
		_run_enemy_turn()


func _run_enemy_turn() -> void:
	_busy = true
	_update_range()
	_update_preview()
	while state.combat.active and state.combat.side == SimEntity.Faction.ENEMIES:
		await get_tree().create_timer(ENEMY_ACTION_DELAY).timeout
		if not state.apply_command(UtilityAi.next_command(state)):
			push_error("AI produced an invalid command")
			break
		_consume_events()
	_busy = false
	_select_next(true)


func _consume_events() -> void:
	var events := state.drain_events()
	for e in events:
		if e.type == SimEvent.Type.TURN_STARTED and e.amount == SimEntity.Faction.PLAYERS:
			_capture_turn_start_ap()
	for line in Narrator.describe_all(state, events):
		_log.push_front(line)
	if _log.size() > LOG_LINES:
		_log.resize(LOG_LINES)
	_grid_renderer.render(state.grid)
	_entity_renderer.render(state, events)
	_refresh()


func _capture_turn_start_ap() -> void:
	_turn_start_ap.clear()
	for e in CombatRules.fighters(state, SimEntity.Faction.PLAYERS):
		_turn_start_ap[e.id] = e.ap


func _is_players_turn() -> bool:
	return state.combat.active and state.combat.side == SimEntity.Faction.PLAYERS


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_teleport_target = null
	_confirm_cell = null
	_update_range()
	_update_preview()


func _select(id: int) -> void:
	_selected_id = id
	_set_mode(Mode.MOVE)


func _select_index(index: int) -> void:
	var party := CombatRules.fighters(state, SimEntity.Faction.PLAYERS)
	if index < party.size():
		_select(party[index].id)


## Selects the next party member, preferring ones with AP left. With
## keep_current, the current selection stays if it can still act.
func _select_next(keep_current: bool = false) -> void:
	var party := CombatRules.fighters(state, SimEntity.Faction.PLAYERS)
	if party.is_empty():
		_select(-1)
		return
	var current := 0
	for i in party.size():
		if party[i].id == _selected_id:
			current = i
			if keep_current and party[i].ap > 0:
				_select(_selected_id)
				return
	var start := current if _selected_id == -1 or state.get_entity(_selected_id) == null else current + 1
	for offset in party.size():
		var candidate := party[(start + offset) % party.size()]
		if candidate.ap > 0:
			_select(candidate.id)
			return
	_select(party[start % party.size()].id)


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


## First Teleport click: is this entity something the selected character can teleport?
func _can_teleport_target(target: SimEntity) -> bool:
	var actor := state.get_entity(_selected_id)
	var ability := SimAbilities.Ability.TELEPORT
	return (actor != null and target != null and target != actor
			and target.mass <= SimAbilities.TELEPORT_MAX_MASS
			and actor.ap >= SimAbilities.AP_COST[ability]
			and SimAbilities.can_reach(ability, actor.cell, target.cell)
			and SimLos.has_line_of_sight(state.grid, actor.cell, target.cell))


## Why a command is invalid, for the HUD. Only checks what the player can fix.
func _target_reason(command: SimCommand) -> String:
	var actor := state.get_entity(_selected_id)
	if actor == null:
		return "No one selected"
	if command is CastCommand:
		var cast := command as CastCommand
		if actor.ap < SimAbilities.AP_COST[cast.ability]:
			return "Not enough AP"
		if not SimAbilities.can_reach(cast.ability, actor.cell, cast.target):
			return "Out of range"
		if SimAbilities.needs_line_of_sight(cast.ability) and not SimLos.has_line_of_sight(state.grid, actor.cell, cast.target):
			return "No line of sight"
	elif command is AttackCommand:
		if actor.ap < CombatRules.ATTACK_AP:
			return "Not enough AP"
	elif command is MoveCommand:
		if MoveCommand.path_for(state, actor, (command as MoveCommand).destination).is_empty():
			return "Can't get there"
		return "Not enough AP"
	return "" if command.validate(state) else "Can't do that"


# --- Range ---------------------------------------------------------------------

## Highlights where the current mode can act: reachable cells for Move, cells
## in range for abilities (red where there is no line of sight).
func _update_range() -> void:
	var cells: Array[Vector3i] = []
	var colors: Array[Color] = []
	var actor := state.get_entity(_selected_id)
	if not _busy and _is_players_turn() and actor != null and actor.is_alive():
		match _mode:
			Mode.MOVE:
				var reach := SimPathfinder.reachable(state, actor.cell, actor.ap * CombatRules.MOVE_COST_PER_AP, actor.id)
				for c: Vector3i in reach:
					cells.append(c)
					colors.append(COLOR_RANGE)
			Mode.ATTACK, Mode.SHOVE, Mode.STEAL:
				for c in _floor_cells_near(actor.cell, 1):
					if SimAbilities.is_adjacent(actor.cell, c):
						cells.append(c)
						colors.append(COLOR_RANGE)
			_:
				var ability: int = MODE_ABILITY[_mode]
				for c in _floor_cells_near(actor.cell, SimAbilities.RANGE[ability]):
					if not SimAbilities.in_range(actor.cell, c, SimAbilities.RANGE[ability]) or c == actor.cell:
						continue
					cells.append(c)
					colors.append(COLOR_RANGE if SimLos.has_line_of_sight(state.grid, actor.cell, c) else COLOR_NO_SIGHT)
	_range_markers.show_cells(cells, colors, 0.03)


## Open cells within `radius` columns that stand on solid ground or hold an entity.
func _floor_cells_near(center: Vector3i, radius: int) -> Array[Vector3i]:
	var grid := state.grid
	var result: Array[Vector3i] = []
	for z in range(center.z - radius, center.z + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			for y in grid.size.y:
				var c := Vector3i(x, y, z)
				if grid.in_bounds(c) and not grid.is_solid(c) and (grid.is_supported(c) or state.entity_at(c) != null):
					result.append(c)
	return result


# --- Preview -------------------------------------------------------------------

## Runs the hovered command on a copy of the sim and shows what would happen:
## immediately, and by the end of the turn once the world has advanced.
func _update_preview() -> void:
	_preview_text = ""
	_preview_cost = 0
	_preview_hurts_allies.clear()
	var cells: Array[Vector3i] = []
	var colors: Array[Color] = []
	var texts := {}
	var actor := state.get_entity(_selected_id)
	if _is_players_turn():
		for e in CombatRules.fighters(state, SimEntity.Faction.PLAYERS):
			if e.id == _selected_id:
				cells.append(e.cell)
				colors.append(COLOR_SELECTED)
			elif e.ap > 0:
				cells.append(e.cell)
				colors.append(COLOR_HAS_AP)
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
			_preview_text = _target_reason(command)
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
		for c in MoveCommand.path_for(state, actor, (command as MoveCommand).destination):
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
		if e.faction == SimEntity.Faction.PLAYERS and now_hp < e.hp:
			_preview_hurts_allies.append(e.name)
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

	_preview_cost = actor.ap - after.get_entity(actor.id).ap
	_preview_text = "%s: %d AP" % [MODE_NAMES[_mode], _preview_cost]
	if not _preview_hurts_allies.is_empty():
		if _confirm_cell != null and _confirm_cell == _hover:
			_preview_text += "   HITS %s — click again to confirm" % ", ".join(_preview_hurts_allies).to_upper()
		else:
			_preview_text += "   Warning: hits %s" % ", ".join(_preview_hurts_allies)


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
	_range_markers = CellMarkers.new()
	add_child(_range_markers)
	_markers = CellMarkers.new()
	add_child(_markers)

	_rig = CameraRig.new()
	_rig.position = Vector3(ArenaBuilder.SIZE.x / 2.0, 2.0, ArenaBuilder.SIZE.z / 2.0)
	_rig.zoom = 24.0
	add_child(_rig)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = _make_label(canvas, Vector2(12, 10))
	_log_label = _make_label(canvas, Vector2(12, 200))

	_party_bar = PartyBar.new()
	canvas.add_child(_party_bar)
	_party_bar.member_selected.connect(func(id: int) -> void:
		if not _busy and not _confirming_end_turn:
			_select(id))
	_party_bar.end_turn_pressed.connect(func() -> void:
		if _confirming_end_turn:
			_end_turn(true)
		else:
			_end_turn())

	_dialog = PanelContainer.new()
	_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.13, 0.95)
	style.border_color = Color(1.0, 0.6, 0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	_dialog.add_theme_stylebox_override("panel", style)
	_dialog_label = Label.new()
	_dialog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog.add_child(_dialog_label)
	_dialog.visible = false
	canvas.add_child(_dialog)


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
	_party_bar.update_party(CombatRules.fighters(state, SimEntity.Faction.PLAYERS), _selected_id, _turn_start_ap, _preview_cost, _is_players_turn() and not _busy)
	var lines: Array[String] = []
	if state.combat.active:
		lines.append("Round %d — %s" % [state.combat.round_number, "Your turn" if _is_players_turn() else "Enemy turn..."])
	else:
		lines.append("Combat over — press R to restart")
	var actor := state.get_entity(_selected_id)
	if actor != null:
		var items := ", ".join(actor.inventory) if not actor.inventory.is_empty() else "nothing"
		lines.append("%s   weapon: %s   carrying: %s" % [actor.name, actor.weapon if actor.weapon != "" else "none", items])
	lines.append("Mode: %s   %s" % [MODE_NAMES[_mode], _preview_text])
	lines.append("")
	lines.append("M move  A attack (2)  1 Firebolt (2)  2 Rain (2)  3 Teleport (2)  4 Shove (1)  5 Steal (1)")
	lines.append("F1-F4 / Tab / party cards: select   Enter: end turn   Esc/RMB: cancel   R: restart")
	lines.append("WASD pan   Q/E rotate   wheel zoom")
	_hud.text = "\n".join(lines)
	_log_label.text = "\n".join(_log)
