extends Node3D
## Plays a level scene: real-time exploration and turn-based combat. The level
## (layout, characters, props, lighting) is edited in its own scene; levels
## with start_in_combat begin straight in a fight (the arena).
##
## Exploration: the world ticks in real time; right-click (or left-click with
## nothing aimed) walks the party there, the others following in formation.
## Abilities work without AP. Enemy sight areas are tinted red; walking into one,
## or hurting an enemy, starts combat right where everyone stands. After a win
## the world goes back to real time.
##
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
## Enemy turns are paced so you can follow them; hold Space to fast-forward.
## Hold Alt to show every health bar. Actions against a target swing the camera
## to frame both sides, then back to the caster.

const SLOT_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
## Pause on an enemy's telegraphed action before it happens.
const ENEMY_AIM_SECONDS := 0.55
## Minimum time an enemy action gets to play out before the next one.
const ENEMY_ACTION_SECONDS := 0.6
## Time per visible world tick when the world advances between sides.
const WORLD_TICK_SECONDS := 0.3
const BANNER_SECONDS := 1.4
const FAST_FORWARD := 3.0
## Camera glide to frame a caster and target before the action lands.
const CAMERA_FRAME_SECONDS := 0.42
const LOG_LINES := 10
## Real-time sim rate outside combat (one cell of walking per tick).
const EXPLORE_TICKS_PER_SECOND := 4.0
const COLOR_DANGER := Color(1.0, 0.2, 0.15, 0.13)
## Only enemies this close (cells, per axis) to the party show their sight.
const DANGER_SHOW_RADIUS := 40
## Exploring: the walk preview waits this long after the hovered cell changes.
const EXPLORE_PREVIEW_DELAY_MSEC := 60

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
const COLOR_ENEMY_ACTOR := Color(1.0, 0.25, 0.2, 0.7)
const COLOR_ENEMY_TARGET := Color(1.0, 0.55, 0.1, 0.6)

## Level to explore. Empty = the combat arena.
@export var level_scene: PackedScene
## Prints the perf readout to the output every 2 s (stress-test levels).
@export var log_perf := false
## Retro presentation style to start with (P cycles them).
@export var retro_style := RetroLook.Style.OFF

var state: SimState
var _level: GameLevel
var _tick_accumulator := 0.0

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
## Mouse position and camera transform the hover was last picked with.
var _last_pick_view := []
## Set when the world changed under a still cursor (e.g. after an action).
var _force_pick := false
## State the HUD shows; a ghost copy while the world-advance is animating.
var _view: SimState
## Bumped on restart so running turn coroutines stop.
var _session := 0
## Frame timing for the HUD: worst frame in the current and previous 2 s window.
var _frame_worst := 0.0
var _frame_worst_shown := 0.0
var _frame_window := 0.0
## Last cost (ms) of the expensive steps, for the HUD: bake, tick, ai, preview, range.
var _perf := {}
## [watcher id, cell] -> floor cells that watcher sees (see _danger_cells).
var _danger_cache := {}
## When to refresh the hover preview while exploring (0 = nothing pending).
var _preview_due_msec := 0

var _grid_renderer: SimGridRenderer
var _retro: RetroLook
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
var _banner: Label
var _banner_tween: Tween
var _caption: Label


func _ready() -> void:
	PackVfx.preload_all()
	_build_scene()
	_fire_field.prewarm()
	_restart()


func _process(delta: float) -> void:
	if state == null:
		return
	_update_hover()
	if _preview_due_msec > 0 and Time.get_ticks_msec() >= _preview_due_msec:
		_preview_due_msec = 0
		_update_preview()
	if _exploring() and not _busy:
		_tick_accumulator += delta
		var tick_seconds := 1.0 / EXPLORE_TICKS_PER_SECOND
		while _tick_accumulator >= tick_seconds and _exploring():
			_tick_accumulator -= tick_seconds
			_explore_tick()
	# Hold Space to fast-forward the enemy turn and world animation.
	Engine.time_scale = FAST_FORWARD if _busy and Input.is_key_pressed(KEY_SPACE) else 1.0
	_entity_renderer.show_all_bars = Input.is_key_pressed(KEY_ALT)
	_frame_worst = maxf(_frame_worst, delta)
	_frame_window += delta
	if _frame_window >= 2.0:
		_frame_worst_shown = _frame_worst
		_frame_worst = 0.0
		_frame_window = 0.0
		_refresh()
		if log_perf:
			print("perf: ", _perf_text())


func _update_hover() -> void:
	var view := [_mouse_pos, _rig.camera.global_transform]
	if view == _last_pick_view and not _force_pick:
		return
	_last_pick_view = view
	var forced := _force_pick
	_force_pick = false
	var hover: Variant = _rig.pick_cell(state, _mouse_pos)
	if typeof(hover) != typeof(_hover) or hover != _hover:
		_hover = hover
		if _exploring() and not forced:
			# Route searches can take a few ms each: wait for the cursor to settle.
			_preview_due_msec = Time.get_ticks_msec() + EXPLORE_PREVIEW_DELAY_MSEC
		else:
			_preview_due_msec = 0
			_update_preview()
	elif forced and _preview_due_msec > 0:
		_preview_due_msec = 0
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
			KEY_P:
				_retro.cycle(_level)
				_refresh()
	elif event is InputEventMouseButton and event.pressed:
		if _confirming_end_turn:
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_force_pick = true
				_update_hover()
				_left_click()
			MOUSE_BUTTON_RIGHT:
				_force_pick = true
				_update_hover()
				_right_click()


# --- Flow ----------------------------------------------------------------------

func _restart() -> void:
	_session += 1
	var session := _session
	state = null
	if level_scene == null:
		push_error("No level_scene set on %s" % name)
		return
	if _level != null:
		_level.queue_free()
	_level = level_scene.instantiate() as GameLevel
	add_child(_level)
	var bake_start := Time.get_ticks_usec()
	var baked: SimState = await _level.bake()
	_perf["bake"] = (Time.get_ticks_usec() - bake_start) / 1000.0
	if session != _session:
		return
	state = baked
	_danger_cache.clear()
	if _retro.style == RetroLook.Style.OFF and retro_style != RetroLook.Style.OFF:
		_retro.set_style(retro_style, _level)
	else:
		_retro.apply(_level)
	_grid_renderer.show_solids = false
	_rig.position = Vector3(state.grid.size.x / 2.0, 2.0, state.grid.size.z / 2.0)
	_tick_accumulator = 0.0
	_view = null
	_fire_field.clear()
	_caption.text = ""
	_log.clear()
	_selected_id = -1
	_busy = false
	_confirming_end_turn = false
	_dialog.visible = false
	_capture_turn_start_ap()
	_consume_events()
	_select_next()
	_show_banner("Round 1 — Your turn" if state.combat.active else "Explore")


func _can_command() -> bool:
	return state != null and not _busy and (_is_players_turn() or _exploring())


## Real time: no fight is on and the party is alive.
func _exploring() -> bool:
	return state != null and not state.combat.active \
			and not CombatRules.fighters(state, SimEntity.Faction.PLAYERS).is_empty()


## One real-time tick. If it starts combat (someone was spotted), switch over.
func _explore_tick() -> void:
	var t0 := Time.get_ticks_usec()
	state.step()
	_perf["tick"] = (Time.get_ticks_usec() - t0) / 1000.0
	_present(state, state.drain_events())
	if state.combat.active:
		_tick_accumulator = 0.0
		_show_banner("Combat!")
		_select_next(true)
		_update_range()
		_update_preview()


## Walks the selected character to `dest`; the rest of the party follows to
## free cells around it, nearest first.
func _travel_party(dest: Vector3i) -> void:
	var leader := state.get_entity(_selected_id)
	if leader == null or not TravelCommand.new(leader.id, dest).validate(state):
		return
	state.apply_command(TravelCommand.new(leader.id, dest))
	var taken := {dest: true}
	for member in CombatRules.fighters(state, SimEntity.Faction.PLAYERS):
		if member.id == leader.id:
			continue
		var spot: Variant = _formation_cell(dest, taken, member.id)
		if spot != null:
			taken[spot] = true
			state.apply_command(TravelCommand.new(member.id, spot))
	_rig.follow(_entity_renderer.view_of(leader.id), leader.travel.size() / EXPLORE_TICKS_PER_SECOND + 0.5)
	_after_action()


## The nearest standable cell to `dest` (breadth-first over walkable steps)
## that nobody else has been sent to.
func _formation_cell(dest: Vector3i, taken: Dictionary, mover_id: int) -> Variant:
	var queue: Array[Vector3i] = [dest]
	var seen := {dest: true}
	while not queue.is_empty() and seen.size() < 200:
		var c: Vector3i = queue.pop_front()
		for n in SimPathfinder.neighbors(state, c, mover_id):
			if seen.has(n):
				continue
			seen[n] = true
			if not taken.has(n):
				return n
			queue.append(n)
	return null


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
	if command is TravelCommand:
		_travel_party(cell)
		return
	if not _preview_hurts_allies.is_empty() and _confirm_cell != _hover:
		_confirm_cell = cell
		_update_preview()
		return
	_action = ActionInfo.NONE
	_teleport_target = null
	_perform(command)


## Applies a player command. Actions against a target first swing the camera
## to frame caster and target, play out, then swing back to the caster.
func _perform(command: SimCommand) -> void:
	var session := _session
	var actor := _actor_of(command)
	var target: Variant = _target_point(command, actor)
	if actor == null or target == null:
		state.apply_command(command)
		_after_action()
		return
	_busy = true
	_update_range()
	_update_preview()
	_rig.frame_pair(_body_point(actor.cell), target, CAMERA_FRAME_SECONDS)
	await get_tree().create_timer(CAMERA_FRAME_SECONDS).timeout
	if session != _session:
		return
	state.apply_command(command)
	var events := state.drain_events()
	_present(state, events)
	await get_tree().create_timer(_action_seconds(events)).timeout
	if session != _session:
		return
	var caster := state.get_entity(actor.id)
	_rig.restore(SimEntityRenderer.cell_position(caster.cell))
	_busy = false
	_confirm_cell = null
	_update_range()
	_update_preview()


## Where an action lands, if it is aimed at something other than the actor.
func _target_point(command: SimCommand, actor: SimEntity) -> Variant:
	if actor == null:
		return null
	if command is AttackCommand:
		var target := state.get_entity((command as AttackCommand).target_id)
		return _body_point(target.cell) if target != null else null
	if command is CastCommand:
		var cast := command as CastCommand
		if cast.target == actor.cell:
			return null
		return _body_point(cast.target)
	return null


static func _body_point(c: Vector3i) -> Vector3:
	return WorldSpace.cell_to_world(c) + Vector3(0, 0.8, 0)


## Right-click always moves the selected character (and drops any aim).
func _right_click() -> void:
	if not _can_command():
		return
	if _action != ActionInfo.NONE:
		_aim(ActionInfo.NONE)
	if _hover == null:
		return
	if _exploring():
		_travel_party(_hover)
		return
	var command := MoveCommand.new(_selected_id, _hover)
	if command.validate(state):
		state.apply_command(command)
		_after_action()


## Ends the players' turn. Asks first if anyone still has AP, unless confirmed.
func _end_turn(confirmed: bool = false) -> void:
	if not _can_command() or not _is_players_turn():
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
	_play_round_rest()


## Players are done: animate the world, run the enemy side, hand back control.
func _play_round_rest() -> void:
	var session := _session
	await _finish_side(SimEntity.Faction.PLAYERS)
	if session != _session:
		return
	if state.combat.active and state.combat.side == SimEntity.Faction.ENEMIES:
		await _run_enemy_turn()
		if session != _session:
			return
	_begin_player_turn()


func _cancel_end_turn() -> void:
	_confirming_end_turn = false
	_dialog.visible = false


func _after_action() -> void:
	_confirm_cell = null
	_consume_events()
	_update_range()
	_update_preview()


## Plays the world advancing between sides one tick at a time, then applies the
## real EndTurnCommand. The sim is deterministic, so the ghost copy being
## animated ends exactly where the command does; the command's own tick events
## are skipped so effects don't play twice.
func _finish_side(faction: int) -> void:
	var session := _session
	_busy = true
	_update_range()
	_update_preview()
	_markers.clear()
	var ghost := state.duplicate_state()
	_view = ghost
	for _i in CombatRules.TICKS_PER_SIDE_TURN:
		# A copy-on-write snapshot: the tick writes to fresh arrays.
		var before := ghost.grid.duplicate_grid()
		ghost.step()
		var events := ghost.drain_events()
		if events.is_empty() and _looks_same(ghost.grid, before):
			continue
		_present(ghost, events)
		await get_tree().create_timer(WORLD_TICK_SECONDS).timeout
		if session != _session:
			return
	_view = null
	state.apply_command(EndTurnCommand.new(faction))
	var flow: Array[SimEvent] = []
	for e in state.drain_events():
		if e.type in [SimEvent.Type.TURN_STARTED, SimEvent.Type.COMBAT_ENDED, SimEvent.Type.COMBAT_STARTED]:
			flow.append(e)
	_present(state, flow)
	if not state.combat.active:
		_show_banner("Defeat" if CombatRules.fighters(state, SimEntity.Faction.PLAYERS).is_empty() else "Victory!")


## Whether the player would see any difference, to skip ticks where nothing changes.
static func _looks_same(a: SimGrid, b: SimGrid) -> bool:
	return a.surface_type == b.surface_type and a.surface_amount == b.surface_amount 			and a.gas_type == b.gas_type and a.fire == b.fire


## Enemy side: each action is thought out off the main thread, telegraphed
## (camera, markers, caption), applied, and given time to play out.
func _run_enemy_turn() -> void:
	var session := _session
	_busy = true
	_show_banner("Enemy turn")
	await get_tree().create_timer(0.5).timeout
	while session == _session and state.combat.active and state.combat.side == SimEntity.Faction.ENEMIES:
		var command: SimCommand = await _think()
		if session != _session:
			return
		if command is EndTurnCommand:
			_caption.text = ""
			await _finish_side(SimEntity.Faction.ENEMIES)
			return
		var actor := _actor_of(command)
		var target: Variant = _target_point(command, actor)
		if actor != null:
			if target != null:
				_rig.frame_pair(_body_point(actor.cell), target, CAMERA_FRAME_SECONDS)
			else:
				_rig.restore(SimEntityRenderer.cell_position(actor.cell))
			_telegraph(command, actor)
			await get_tree().create_timer(ENEMY_AIM_SECONDS).timeout
			if session != _session:
				return
		if not state.apply_command(command):
			push_error("AI produced an invalid command: %s" % command.to_dict())
			return
		var events := state.drain_events()
		_present(state, events)
		_markers.clear()
		var seconds := _action_seconds(events)
		if command is MoveCommand and actor != null:
			_rig.follow(_entity_renderer.view_of(actor.id), seconds)
		await get_tree().create_timer(seconds).timeout
		if target != null and actor != null and session == _session:
			_rig.restore(SimEntityRenderer.cell_position(state.get_entity(actor.id).cell))
	_caption.text = ""


func _begin_player_turn() -> void:
	_busy = false
	_caption.text = ""
	var selected := state.get_entity(_selected_id)
	if selected != null:
		_rig.restore(SimEntityRenderer.cell_position(selected.cell))
	if state.combat.active:
		_show_banner("Round %d — Your turn" % state.combat.round_number)
	_select_next(true)
	_update_range()
	_update_preview()


## Runs the AI on a worker thread against a copy of the sim, so frames keep
## coming while it thinks. The sim is plain data, so the copy is safe to use
## off the main thread.
func _think() -> SimCommand:
	var t0 := Time.get_ticks_usec()
	var command: SimCommand = await _think_on_worker()
	_perf["ai"] = (Time.get_ticks_usec() - t0) / 1000.0
	return command


func _think_on_worker() -> SimCommand:
	var snapshot := state.duplicate_state()
	var result: Array = [null]
	var task := WorkerThreadPool.add_task(func() -> void: result[0] = UtilityAi.next_command(snapshot))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return result[0]


func _actor_of(command: SimCommand) -> SimEntity:
	if command is MoveCommand:
		return state.get_entity((command as MoveCommand).entity_id)
	if command is AttackCommand:
		return state.get_entity((command as AttackCommand).attacker_id)
	if command is CastCommand:
		return state.get_entity((command as CastCommand).caster_id)
	return null


## Shows what an enemy is about to do: who, where, and a caption.
func _telegraph(command: SimCommand, actor: SimEntity) -> void:
	var cells: Array[Vector3i] = [actor.cell]
	var colors: Array[Color] = [COLOR_ENEMY_ACTOR]
	var text := actor.name
	if command is MoveCommand:
		for c in MoveCommand.path_for(state, actor, (command as MoveCommand).destination):
			cells.append(c)
			colors.append(COLOR_ENEMY_TARGET)
		text += " moves"
	elif command is AttackCommand:
		var target := state.get_entity((command as AttackCommand).target_id)
		cells.append(target.cell)
		colors.append(COLOR_ENEMY_TARGET)
		text += " attacks %s" % target.name
	elif command is CastCommand:
		var cast := command as CastCommand
		cells.append(cast.target)
		colors.append(COLOR_ENEMY_TARGET)
		var victim := state.entity_at(cast.target)
		text += ": %s" % SimAbilities.NAMES[cast.ability]
		if victim != null and victim != actor:
			text += " → %s" % victim.name
		if cast.ability == SimAbilities.Ability.TELEPORT:
			cells.append(cast.destination)
			colors.append(COLOR_ENEMY_TARGET)
	_markers.show_cells(cells, colors)
	_caption.text = text


## How long to let an action's animation and effects play.
func _action_seconds(events: Array[SimEvent]) -> float:
	var seconds := ENEMY_ACTION_SECONDS
	for e in events:
		match e.type:
			SimEvent.Type.MOVED:
				seconds = maxf(seconds, e.cells.size() * SimEntityRenderer.MOVE_SECONDS_PER_CELL + 0.35)
			SimEvent.Type.CAST:
				if VfxPlayer.ABILITY_PROJECTILES.has(e.amount):
					seconds = maxf(seconds, VfxPlayer.PROJECTILE_SECONDS + 0.6)
	return seconds


func _consume_events() -> void:
	_present(state, state.drain_events())


## Draws a state and plays its events: log, grid, flames, entities, effects.
func _present(s: SimState, events: Array[SimEvent]) -> void:
	_force_pick = true  # entities may have moved under the cursor
	for e in events:
		if e.type == SimEvent.Type.TURN_STARTED and e.amount == SimEntity.Faction.PLAYERS:
			_capture_turn_start_ap()
	for line in Narrator.describe_all(s, events):
		_log.push_front(line)
	if _log.size() > LOG_LINES:
		_log.resize(LOG_LINES)
	for e in events:
		if e.type == SimEvent.Type.COMBAT_ENDED:
			_show_banner("Victory!" if e.amount == SimEntity.Faction.PLAYERS else "Defeat")
	_entity_renderer.walk_seconds = 1.0 / EXPLORE_TICKS_PER_SECOND if not s.combat.active else 0.0
	_grid_renderer.render(s.grid)
	_fire_field.sync(s.grid)
	_entity_renderer.render(s, events)
	_vfx.play(s, events)
	_refresh()


func _show_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = _banner.create_tween()
	_banner_tween.tween_interval(BANNER_SECONDS)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


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
			if _exploring():
				return TravelCommand.new(actor.id, cell)
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
		if state.combat.active and actor.ap < SimAbilities.AP_COST[cast.ability]:
			return "Not enough AP"
		if actor.cooldown(cast.ability) > 0:
			return "On cooldown (ready in %d)" % actor.cooldown(cast.ability)
		if not SimAbilities.can_reach(cast.ability, actor.cell, cast.target) and not (cast.ability == SimAbilities.Ability.MEND and cast.target == actor.cell):
			return "Out of range"
		if SimAbilities.needs_line_of_sight(cast.ability) and not SimLos.has_line_of_sight(state.grid, actor.cell, cast.target):
			return "No line of sight"
		return "No valid target there"
	elif command is AttackCommand:
		if state.combat.active and actor.ap < CombatRules.ATTACK_AP:
			return "Not enough AP"
		return "Too far to hit"
	elif command is TravelCommand:
		var walker := state.get_entity((command as TravelCommand).entity_id)
		if walker != null and TravelCommand.too_far(walker.cell, (command as TravelCommand).destination):
			return "Too far — walk closer first"
		return "Can't get there"
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
	var t0 := Time.get_ticks_usec()
	_update_range_now()
	_perf["range"] = (Time.get_ticks_usec() - t0) / 1000.0


func _update_range_now() -> void:
	if state == null:
		return
	var cells: Array[Vector3i] = []
	var colors: Array[Color] = []
	var targetable := {}
	var actor := state.get_entity(_selected_id)
	var action := _hovered_action if _hovered_action != ActionInfo.NONE else _action
	if _can_command() and actor != null and actor.is_alive():
		if action == ActionInfo.NONE and _exploring():
			for c in _danger_cells():
				cells.append(c)
				colors.append(COLOR_DANGER)
		elif action == ActionInfo.NONE:
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


## Floor cells some watchful enemy near the party can see: walking in starts
## combat. Each watcher's cells are cached until it moves.
func _danger_cells() -> Array[Vector3i]:
	var party := CombatRules.fighters(state, SimEntity.Faction.PLAYERS)
	var occupied := SimPathfinder.occupancy(state)
	var result: Array[Vector3i] = []
	var seen := {}
	for watcher in CombatRules.fighters(state, SimEntity.Faction.ENEMIES):
		if watcher.sight <= 0 or not _near_any(watcher.cell, party, DANGER_SHOW_RADIUS):
			continue
		var key := [watcher.id, watcher.cell]
		if not _danger_cache.has(key):
			_danger_cache[key] = _cells_seen_by(watcher, occupied)
		for c: Vector3i in _danger_cache[key]:
			if not seen.has(c):
				seen[c] = true
				result.append(c)
	return result


static func _near_any(c: Vector3i, others: Array[SimEntity], radius: int) -> bool:
	for o in others:
		if absi(o.cell.x - c.x) <= radius and absi(o.cell.z - c.z) <= radius:
			return true
	return false


## Open cells within `radius` columns that stand on solid ground or hold an
## entity, at any height (ability ranges ignore height).
func _floor_cells_near(center: Vector3i, radius: int) -> Array[Vector3i]:
	var grid := state.grid
	var occupied := SimPathfinder.occupancy(state)
	var result: Array[Vector3i] = []
	for z in range(center.z - radius, center.z + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			for y in grid.size.y:
				var c := Vector3i(x, y, z)
				if grid.in_bounds(c) and not grid.is_solid(c) and (grid.is_supported(c) or occupied.has(c)):
					result.append(c)
	return result


func _cells_seen_by(watcher: SimEntity, occupied: Dictionary) -> Array[Vector3i]:
	var grid := state.grid
	var r := watcher.sight
	var result: Array[Vector3i] = []
	for z in range(watcher.cell.z - r, watcher.cell.z + r + 1):
		for x in range(watcher.cell.x - r, watcher.cell.x + r + 1):
			for y in range(maxi(watcher.cell.y - r, 0), mini(watcher.cell.y + r + 1, grid.size.y)):
				var c := Vector3i(x, y, z)
				if not grid.in_bounds(c) or grid.is_solid(c) or not (grid.is_supported(c) or occupied.has(c)):
					continue
				if SimAbilities.in_range(watcher.cell, c, r) and SimLos.has_line_of_sight(grid, watcher.cell, c):
					result.append(c)
	return result


# --- Preview -------------------------------------------------------------------

## Runs the hovered command on a copy of the sim and shows what would happen:
## immediately, and by the end of the turn once the world has advanced.
func _update_preview() -> void:
	var t0 := Time.get_ticks_usec()
	_update_preview_now()
	_perf["preview"] = (Time.get_ticks_usec() - t0) / 1000.0


func _update_preview_now() -> void:
	if state == null:
		return
	var hovered := state.entity_at(_hover) if _hover != null else null
	_entity_renderer.set_hovered(hovered.id if hovered != null else -1)
	if _busy:
		# Enemy turn or world advancing: the markers belong to the telegraph.
		_preview_text = ""
		_preview_cost = 0
		_entity_renderer.set_preview({})
		_refresh()
		return
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
	# A walk in real time changes nothing until the world ticks: just show the
	# route (found while validating) without copying the world.
	if command is TravelCommand:
		for c in (command as TravelCommand).route(state):
			cells.append(c)
			colors.append(COLOR_PATH)
		return
	# The caller has validated the command, so run it straight on the copy (no
	# second validation) and read the path from what it did, rather than
	# searching for it again.
	var after := state.duplicate_state()
	command.execute(after)
	CombatRules.check_end(after)
	var moved_cells: Array[Vector3i] = []
	for e in after.drain_events():
		if e.type == SimEvent.Type.MOVED and e.entity_id == actor.id:
			moved_cells = e.cells
	for c in moved_cells:
		cells.append(c)
		colors.append(COLOR_PATH)

	# Turn-end forecast (fire spreading, burning) only matters in combat; in real
	# time there is no turn end to forecast.
	var forecast := after
	if state.combat.active:
		forecast = after.duplicate_state()
		forecast.step_ticks(CombatRules.TICKS_PER_SIDE_TURN)
	if command is CastCommand and (command as CastCommand).ability == SimAbilities.Ability.TELEPORT:
		var moved := after.get_entity(state.entity_at((command as CastCommand).target).id)
		cells.append(moved.cell)
		colors.append(COLOR_TARGET)

	# New fire and changed surfaces, found with native array compares and
	# searches so the cost depends on what changed, not on the grid size.
	var grid := state.grid
	var marked := {}
	if forecast.grid.fire != grid.fire:
		for i in forecast.grid.burning_cells():
			if grid.fire[i] == 0:
				marked[i] = true
				cells.append(grid.coord(i))
				colors.append(COLOR_FIRE)
	if after.grid.surface_type != grid.surface_type:
		var kinds := [SimMaterials.Surface.WATER, SimMaterials.Surface.OIL, SimMaterials.Surface.ICE]
		var candidates := SimGrid.indices_of(after.grid.surface_type, kinds)
		candidates.append_array(SimGrid.indices_of(grid.surface_type, kinds))
		for i in candidates:
			if not marked.has(i) and after.grid.surface_type[i] != grid.surface_type[i]:
				marked[i] = true
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
		texts[e.id] = [now_hp, later_hp]

	_preview_cost = actor.ap - after.get_entity(actor.id).ap
	if state.combat.active:
		_preview_text = "%s: %d AP" % [_mode_name(), _preview_cost]
	else:
		_preview_text = "Walk" if command is TravelCommand else _mode_name()
	if not _preview_hurts_allies.is_empty():
		if _confirm_cell != null and _confirm_cell == _hover:
			_preview_text += "   HITS %s — click again to confirm" % ", ".join(_preview_hurts_allies).to_upper()
		else:
			_preview_text += "   Warning: hits %s" % ", ".join(_preview_hurts_allies)


# --- Scene & HUD ---------------------------------------------------------------

func _build_scene() -> void:
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

	_retro = RetroLook.new()
	add_child(_retro)
	add_child(ScreenLabels.new())

	_rig = CameraRig.new()
	_rig.zoom = 18.0
	add_child(_rig)
	_vfx.shake_requested.connect(_rig.shake)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = _make_label(canvas, Vector2(12, 10))
	_log_label = _make_label(canvas, Vector2.ZERO)
	# Combat log in the top-right corner, newest line first.
	_log_label.anchor_left = 1.0
	_log_label.anchor_right = 1.0
	_log_label.offset_left = -460
	_log_label.offset_right = -12
	_log_label.offset_top = 280
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

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

	_banner = _make_centered_label(canvas, 160, 52)
	_banner.modulate.a = 0.0
	_caption = _make_centered_label(canvas, 228, 28)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.75, 0.5))

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


## A label spanning the top of the screen, text centred.
func _make_centered_label(parent: Node, top: float, font_size: int) -> Label:
	var label := Label.new()
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.offset_top = top
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	parent.add_child(label)
	return label


func _make_label(parent: Node, pos: Vector2) -> Label:
	var label := Label.new()
	label.position = pos
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


func _perf_text() -> String:
	var fighting := 0
	for e in state.entities:
		if e.in_combat:
			fighting += 1
	var parts: Array[String] = [
		"FPS %d   worst frame %d ms" % [Engine.get_frames_per_second(), int(_frame_worst_shown * 1000.0)],
		"%d entities (%d fighting)" % [state.entities.size(), fighting],
		"cpu %.1f ms   %d draws   %d objects   %dk prims" % [
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000],
	]
	for key: String in ["bake", "tick", "ai", "preview", "range"]:
		if _perf.has(key):
			parts.append("%s %.1f ms" % [key, _perf[key]])
	return "   ".join(parts)


func _refresh() -> void:
	if _hud == null or state == null:
		return
	_entity_renderer.set_selected(_selected_id)
	var shown := _view if _view != null else state
	_party_bar.update_party(CombatRules.fighters(shown, SimEntity.Faction.PLAYERS), _selected_id, _turn_start_ap, _preview_cost, _can_command() and _is_players_turn())
	var actor := state.get_entity(_selected_id)
	_action_bar.show_actions(actor if actor != null and actor.is_alive() else null, _action, _can_command(), state.combat.active)
	var lines: Array[String] = []
	if state.combat.active:
		lines.append("Round %d — %s" % [state.combat.round_number, "Your turn" if _is_players_turn() else "Enemy turn..."])
	elif _exploring():
		lines.append("Exploring — red ground is in an enemy's sight")
	else:
		lines.append("Combat over — press R to restart")
	if actor != null:
		var items := ", ".join(actor.inventory) if not actor.inventory.is_empty() else "nothing"
		lines.append("%s the %s   weapon: %s   carrying: %s" % [actor.name, SimArchetypes.title(actor.archetype), actor.weapon if actor.weapon != "" else "none", items])
	lines.append("%s   %s" % [_mode_name(), _preview_text])
	lines.append("RMB move   LMB use / select   1-9 actions   Esc cancel   F1-F4 / Tab select   Enter end turn   Space (hold) fast-forward   R restart")
	lines.append("WASD pan   Q/E rotate   wheel zoom   P look: %s" % _retro.style_name())
	lines.append(_perf_text())
	_hud.text = "\n".join(lines)
	_log_label.text = "\n".join(_log)
