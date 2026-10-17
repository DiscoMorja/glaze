extends Node3D
## M1 combat greybox. Every player and AI action is a SimCommand; hovering shows
## a preview computed by running the command on a copy of the sim.
##
## Select: click a party card, F1-F4, Tab (next with AP left), or left-click a
## party member when nothing is aimed.
## Move: right-click a cell, always (it also cancels aiming). Left-click moves
## too when nothing is aimed.
## Actions: the action bar (or keys 1-9) aims Attack or one of the selected
## character's abilities; left-click a target to use it. Hovering a button shows
## its tooltip, range and what it can target. Actions return to moving after
## use. Actions that would hurt your own party need a second click to confirm.
## Teleport takes two clicks: the target, then where to put it.
## Enter: end turn (asks first if anyone has AP left)   Esc: cancel   R: restart

const SLOT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
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
const COLOR_TARGETABLE := Color(1.0, 0.8, 0.15, 0.45)
const COLOR_RANGE := Color(0.35, 0.6, 1.0, 0.16)
const COLOR_NO_SIGHT := Color(1.0, 0.3, 0.25, 0.12)

var state: SimState

## Action being aimed (ActionInfo.ATTACK or an ability), or ActionInfo.NONE to move.
var _action := ActionInfo.NONE
## Action button under the mouse, for range and target highlights.
var _hovered_action := ActionInfo.NONE
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
var _fire_field: FireField
var _vfx: VfxPlayer
var _entity_renderer: SimEntityRenderer
var _markers: CellMarkers
var _range_markers: CellMarkers
var _rig: CameraRig
var _hud: Label
var _log_label: Label
var _party_bar: PartyBar
var _action_bar: ActionBar
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
		var slot := SLOT_KEYS.find(event.keycode)
		if slot >= 0:
			_aim_slot(slot)
			return
		match event.keycode:
			KEY_ESCAPE: _aim(ActionInfo.NONE)
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
				_left_click()
			MOUSE_BUTTON_RIGHT:
				_update_hover()
				_right_click()


# --- Flow ----------------------------------------------------------------------

func _restart() -> void:
	state = ArenaBuilder.build()
	_fire_field.clear()
	_log.clear()
	_selected_id = -1
	_busy = false
	_confirming_end_turn = false
	_dialog.visible = false
	_capture_turn_start_ap()
	_consume_events()
	_select_next()


func _can_command() -> bool:
	return not _busy and _is_players_turn()


func _left_click() -> void:
	if not _can_command() or _hover == null:
		return
	var cell: Vector3i = _hover
	var clicked := state.entity_at(cell)
	var own_unit := clicked != null and clicked.faction == SimEntity.Faction.PLAYERS and clicked.takes_turns()
	if own_unit and _action == ActionInfo.NONE:
		_select(clicked.id, false)
		return
	if _action == SimAbilities.Ability.TELEPORT and _teleport_target == null:
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
	_action = ActionInfo.NONE
	_teleport_target = null
	_after_action()


## Right-click always moves the selected character (and drops any aim).
func _right_click() -> void:
	if not _can_command():
		return
	if _action != ActionInfo.NONE:
		_aim(ActionInfo.NONE)
	if _hover == null:
		return
	var command := MoveCommand.new(_selected_id, _hover)
	if command.validate(state):
		state.apply_command(command)
		_after_action()


## Ends the players' turn. Asks first if anyone still has AP, unless confirmed.
func _end_turn(confirmed: bool = false) -> void:
	if not _can_command():
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
	_fire_field.sync(state.grid)
	_entity_renderer.render(state, events)
	_vfx.play(state, events)
	_refresh()


func _capture_turn_start_ap() -> void:
	_turn_start_ap.clear()
	for e in CombatRules.fighters(state, SimEntity.Faction.PLAYERS):
		_turn_start_ap[e.id] = e.ap


func _is_players_turn() -> bool:
	return state.combat.active and state.combat.side == SimEntity.Faction.PLAYERS


## Aims an action (or NONE to go back to moving).
func _aim(action: int) -> void:
	_action = action
	_teleport_target = null
	_confirm_cell = null
	_update_range()
	_update_preview()


## Aims the action in action-bar slot `slot` (0-based) for the selected character.
func _aim_slot(slot: int) -> void:
	var actor := state.get_entity(_selected_id)
	if actor == null:
		return
	var actions := ActionInfo.actions_for(actor)
	if slot < actions.size():
		_aim(actions[slot])


func _on_action_pressed(action: int) -> void:
	_aim(ActionInfo.NONE if _action == action else action)


func _on_action_hovered(action: int) -> void:
	_hovered_action = action
	_update_range()


func _mode_name() -> String:
	return "Move" if _action == ActionInfo.NONE else ActionInfo.name_of(_action)


## Selects a party member and centres the camera on them (unless they were
## clicked in the world, where they are already on screen).
func _select(id: int, focus_camera: bool = true) -> void:
	var changed := id != _selected_id
	_selected_id = id
	var e := state.get_entity(id)
	if e != null and changed and focus_camera:
		_rig.focus(SimEntityRenderer.cell_position(e.cell))
	_aim(ActionInfo.NONE)


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
	match _action:
		ActionInfo.NONE:
			return MoveCommand.new(actor.id, cell)
		ActionInfo.ATTACK:
			var target := state.entity_at(cell)
			return AttackCommand.new(actor.id, target.id) if target != null else null
		SimAbilities.Ability.TELEPORT:
			if _teleport_target == null:
				return null
			return CastCommand.new(actor.id, _action, _teleport_target, cell)
	return CastCommand.new(actor.id, _action, cell)


## First Teleport click: is this entity something the selected character can teleport?
func _can_teleport_target(target: SimEntity) -> bool:
	var actor := state.get_entity(_selected_id)
	return actor != null and _teleportable(state, actor, target) and actor.ap >= SimAbilities.AP_COST[SimAbilities.Ability.TELEPORT]


static func _teleportable(s: SimState, actor: SimEntity, target: SimEntity) -> bool:
	var ability := SimAbilities.Ability.TELEPORT
	return (target != null and target != actor and target.is_alive()
			and target.mass <= SimAbilities.TELEPORT_MAX_MASS
			and SimAbilities.can_reach(ability, actor.cell, target.cell)
			and SimLos.has_line_of_sight(s.grid, actor.cell, target.cell))


## Entities the action can target from where the actor stands, ignoring AP so
## hovering shows options even when the actor can't afford them yet.
func _targetable_ids(actor: SimEntity, action: int) -> Dictionary:
	var ids := {}
	if action == ActionInfo.NONE or action == SimAbilities.Ability.BLINK:
		return ids
	if action == SimAbilities.Ability.TELEPORT and _teleport_target != null and action == _action:
		return ids  # second click picks a cell, not an entity
	var probe := state.duplicate_state()
	var me := probe.get_entity(actor.id)
	me.ap = CombatRules.AP_CAP
	for e in probe.entities:
		if not e.is_alive():
			continue
		var ok: bool
		if action == ActionInfo.ATTACK:
			ok = AttackCommand.new(me.id, e.id).validate(probe)
		elif action == SimAbilities.Ability.TELEPORT:
			ok = _teleportable(probe, me, e)
		else:
			ok = CastCommand.new(me.id, action, e.cell).validate(probe)
		if ok:
			ids[e.id] = true
	return ids


## Why a command is invalid, for the HUD. Only checks what the player can fix.
func _target_reason(command: SimCommand) -> String:
	var actor := state.get_entity(_selected_id)
	if actor == null:
		return "No one selected"
	if command is CastCommand:
		var cast := command as CastCommand
		if actor.ap < SimAbilities.AP_COST[cast.ability]:
			return "Not enough AP"
		if not SimAbilities.can_reach(cast.ability, actor.cell, cast.target) and not (cast.ability == SimAbilities.Ability.MEND and cast.target == actor.cell):
			return "Out of range"
		if SimAbilities.needs_line_of_sight(cast.ability) and not SimLos.has_line_of_sight(state.grid, actor.cell, cast.target):
			return "No line of sight"
		return "No valid target there"
	elif command is AttackCommand:
		if actor.ap < CombatRules.ATTACK_AP:
			return "Not enough AP"
		return "Too far to hit"
	elif command is MoveCommand:
		if MoveCommand.path_for(state, actor, (command as MoveCommand).destination).is_empty():
			return "Can't get there"
		return "Not enough AP"
	return "" if command.validate(state) else "Can't do that"


# --- Range & targets -----------------------------------------------------------

## Highlights the hovered (or else aimed) action: cells in range (red where
## there is no line of sight) and the entities it can target. When moving,
## shows reachable cells.
func _update_range() -> void:
	var cells: Array[Vector3i] = []
	var colors: Array[Color] = []
	var targetable := {}
	var actor := state.get_entity(_selected_id)
	var action := _hovered_action if _hovered_action != ActionInfo.NONE else _action
	if _can_command() and actor != null and actor.is_alive():
		if action == ActionInfo.NONE:
			var reach := SimPathfinder.reachable(state, actor.cell, actor.ap * CombatRules.MOVE_COST_PER_AP, actor.id)
			for c: Vector3i in reach:
				cells.append(c)
				colors.append(COLOR_RANGE)
		else:
			var reach_cells := ActionInfo.range_of(action)
			if action == SimAbilities.Ability.MEND:
				cells.append(actor.cell)
				colors.append(COLOR_RANGE)
			for c in _floor_cells_near(actor.cell, reach_cells):
				if reach_cells == 1:
					if SimAbilities.is_adjacent(actor.cell, c):
						cells.append(c)
						colors.append(COLOR_RANGE)
				elif c != actor.cell and SimAbilities.in_range(actor.cell, c, reach_cells):
					cells.append(c)
					colors.append(COLOR_RANGE if SimLos.has_line_of_sight(state.grid, actor.cell, c) else COLOR_NO_SIGHT)
			targetable = _targetable_ids(actor, action)
			for id: int in targetable:
				cells.append(state.get_entity(id).cell)
				colors.append(COLOR_TARGETABLE)
	_range_markers.show_cells(cells, colors, 0.03)
	_entity_renderer.set_targetable(targetable)
	_refresh()


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

	if _can_command() and _hover != null and actor != null:
		var cell: Vector3i = _hover
		var command := _build_command(cell)
		if command == null:
			cells.append(cell)
			colors.append(COLOR_CURSOR)
			if _action == SimAbilities.Ability.TELEPORT:
				_preview_text = "Pick something to teleport"
			elif _action == ActionInfo.ATTACK:
				_preview_text = "Pick someone to hit"
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
		elif now_hp > e.hp:
			parts.append("+%d" % (now_hp - e.hp))
		elif now_hp != e.hp:
			parts.append("-%d" % (e.hp - now_hp))
		if now_hp > 0 and later_hp == 0:
			parts.append("dies by turn end")
		elif later_hp < now_hp:
			parts.append("-%d by turn end" % (now_hp - later_hp))
		texts[e.id] = "  ".join(parts)

	_preview_cost = actor.ap - after.get_entity(actor.id).ap
	_preview_text = "%s: %d AP" % [_mode_name(), _preview_cost]
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
	_grid_renderer.show_fire = false
	add_child(_grid_renderer)
	_fire_field = FireField.new()
	add_child(_fire_field)
	_vfx = VfxPlayer.new()
	add_child(_vfx)
	_entity_renderer = SimEntityRenderer.new()
	add_child(_entity_renderer)
	_range_markers = CellMarkers.new()
	add_child(_range_markers)
	_markers = CellMarkers.new()
	add_child(_markers)

	_rig = CameraRig.new()
	_rig.position = Vector3(ArenaBuilder.SIZE.x / 2.0, 2.0, ArenaBuilder.SIZE.z / 2.0)
	_rig.zoom = 18.0
	add_child(_rig)
	_vfx.shake_requested.connect(_rig.shake)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = _make_label(canvas, Vector2(12, 10))
	_log_label = _make_label(canvas, Vector2(12, 150))

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

	_action_bar = ActionBar.new()
	canvas.add_child(_action_bar)
	_action_bar.action_pressed.connect(_on_action_pressed)
	_action_bar.action_hovered.connect(_on_action_hovered)

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
	_party_bar.update_party(CombatRules.fighters(state, SimEntity.Faction.PLAYERS), _selected_id, _turn_start_ap, _preview_cost, _can_command())
	var actor := state.get_entity(_selected_id)
	_action_bar.show_actions(actor if actor != null and actor.is_alive() else null, _action, _can_command())
	var lines: Array[String] = []
	if state.combat.active:
		lines.append("Round %d — %s" % [state.combat.round_number, "Your turn" if _is_players_turn() else "Enemy turn..."])
	else:
		lines.append("Combat over — press R to restart")
	if actor != null:
		var items := ", ".join(actor.inventory) if not actor.inventory.is_empty() else "nothing"
		lines.append("%s the %s   weapon: %s   carrying: %s" % [actor.name, SimArchetypes.title(actor.archetype), actor.weapon if actor.weapon != "" else "none", items])
	lines.append("%s   %s" % [_mode_name(), _preview_text])
	lines.append("RMB move   LMB use / select   1-9 actions   Esc cancel   F1-F4 / Tab select   Enter end turn   R restart")
	lines.append("WASD pan   Q/E rotate   wheel zoom")
	_hud.text = "\n".join(lines)
	_log_label.text = "\n".join(_log)
