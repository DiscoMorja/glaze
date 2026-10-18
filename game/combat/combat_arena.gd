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
## H: show the controls   `: show the perf readout
## Esc with nothing aimed: menu (save, load, quit). F5 quicksave, F9 quickload
## (host only); the host also autosaves (see _autosave_due()).
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
const MENU_SCENE := "res://game/menu/main_menu.tscn"
## A guest gives up joining after this long without the host's state.
const JOIN_TIMEOUT_SECONDS := 10.0
const COLOR_DANGER := Color(1.0, 0.2, 0.15, 0.13)
## Townsfolk's vision cones (seen there = witnesses), and a suspicious one's.
const COLOR_WATCHED := Color(1.0, 0.85, 0.2, 0.12)
const COLOR_SUSPICIOUS := Color(1.0, 0.55, 0.1, 0.18)
## Only enemies this close (cells, per axis) to the party show their sight.
const DANGER_SHOW_RADIUS := 40
## Exploring: the walk preview waits this long after the hovered cell changes.
const EXPLORE_PREVIEW_DELAY_MSEC := 60
## Autosave at least this often (seconds played), besides quest and combat starts.
const AUTOSAVE_SECONDS := 300.0

const COLOR_CURSOR := Color(1, 1, 1, 0.45)
const COLOR_INVALID := Color(1, 0.15, 0.1, 0.5)
const COLOR_PATH := Color(0.3, 0.9, 1.0, 0.5)
const COLOR_FIRE := Color(1.0, 0.45, 0.05, 0.55)
const COLOR_SURFACE := Color(0.6, 0.8, 1.0, 0.45)
const COLOR_SELECTED := Color(0.3, 1.0, 0.4, 0.75)
const COLOR_HAS_AP := Color(0.3, 1.0, 0.4, 0.3)
## A selected character the partner controls (inspect only).
const COLOR_PARTNER := Color(0.45, 0.7, 1.0, 0.6)
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
## The co-op op stream (NetSession) still to play, in order, and whether it is
## being played now (ops animate one after another).
var _ops: Array[Dictionary] = []
var _playing := false
## Host: the enemy side is being run.
var _enemy_turn_running := false
## Dev/testing ("--autoready" on the command line): this player presses End
## Turn on their own, so one person can test co-op with two instances.
var _autoready := OS.get_cmdline_user_args().has("--autoready")

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
var _inventory: InventoryPanel
var _dialogue: DialoguePanel
var _journal: JournalPanel
var _save_menu: SaveMenu
## The HUD's controls help (H) and perf readout (`), off by default.
var _show_help := false
var _show_perf := false
## Seconds played in this campaign (saved with it), the playtime at the last
## save, and why an autosave is due ("" = none, besides the timer).
var _playtime := 0.0
var _last_save_playtime := 0.0
var _autosave_reason := ""
var _dialog: PanelContainer
var _dialog_label: Label
var _banner: Label
var _banner_tween: Tween
var _caption: Label
## The state a level bake produced (see _load_level()).
var _baked: SimState


func _ready() -> void:
	Content.load_all()
	PackVfx.preload_all()
	_build_scene()
	_fire_field.prewarm()
	Net.op_received.connect(_on_op)
	Net.snapshot_received.connect(_on_snapshot)
	Net.players_changed.connect(_refresh)
	Net.session_ended.connect(_on_session_ended)
	Net.partner_changed.connect(_on_partner_changed)
	DisplayServer.window_set_title("glaze — %s" % ["hosting" if Net.mode == NetSession.Mode.HOST else ("joined" if Net.mode == NetSession.Mode.GUEST else "solo")])
	if Net.mode == NetSession.Mode.NONE:
		Net.start_solo(level_scene.resource_path if level_scene != null else "")
	if Net.mode == NetSession.Mode.GUEST:
		_caption.text = "Connecting to the host..."
		get_tree().create_timer(JOIN_TIMEOUT_SECONDS).timeout.connect(func() -> void:
			if state == null and Net.mode == NetSession.Mode.GUEST:
				Net.leave("Couldn't reach the host. Check the address, and that they are hosting (see HOW_TO_PLAY_TOGETHER)."))
		Net.claim_backlog()
	elif not SaveStore.pending.is_empty():
		var picked := SaveStore.pending
		SaveStore.pending = {}
		_start_save(picked)
	else:
		_restart()


func _process(delta: float) -> void:
	if state == null:
		return
	_playtime += delta / Engine.time_scale
	if _autosave_due() and _save_blocker() == "":
		_save(SaveStore.next_auto_slot(), "Autosave" + (": " + _autosave_reason if _autosave_reason != "" else ""))
		_log.push_front("Autosaved.")
		_refresh()
	_update_hover()
	if _preview_due_msec > 0 and Time.get_ticks_msec() >= _preview_due_msec:
		_preview_due_msec = 0
		_update_preview()
	if _autoready and _can_command() and _is_players_turn() and _ops.is_empty():
		Net.set_ready(true)
	# Only the host keeps the real-time clock; ticks reach everyone as ops.
	if Net.is_host() and _exploring() and not _busy and not Net.authority.combat.active:
		_tick_accumulator += delta
		var tick_seconds := 1.0 / EXPLORE_TICKS_PER_SECOND
		while _tick_accumulator >= tick_seconds and not Net.authority.combat.active:
			_tick_accumulator -= tick_seconds
			Net.host_tick()
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
	if _save_menu.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_save_menu.close()
		if event is InputEventKey or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if _dialogue.handle_key(event.keycode):
			return
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
			KEY_ESCAPE:
				if _action == ActionInfo.NONE and _teleport_target == null:
					_save_menu.open(Net.is_host(), _save_blocker())
				else:
					_aim(ActionInfo.NONE)
			KEY_H:
				_show_help = not _show_help
				_refresh()
			KEY_QUOTELEFT:
				_show_perf = not _show_perf
				_refresh()
			KEY_F5: _quicksave()
			KEY_F9: _quickload()
			KEY_TAB: _select_next()
			KEY_F1: _select_index(0)
			KEY_F2: _select_index(1)
			KEY_F3: _select_index(2)
			KEY_F4: _select_index(3)
			KEY_ENTER, KEY_KP_ENTER: _end_turn()
			KEY_R: _restart()  # host only
			KEY_F10: Net.leave()
			KEY_P:
				_retro.cycle(_level)
				_refresh()
			KEY_C: _toggle_sneak()
			KEY_I:
				_inventory.toggle()
				_refresh()
			KEY_J:
				_journal.toggle()
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

## Host (or alone): loads and bakes the level and plays from it; a connected
## guest is sent the new state. A guest waits for the host's snapshot instead.
func _restart() -> void:
	if not Net.is_host():
		return
	var session := await _load_level()
	if session != _session:
		return
	var baked := _baked
	_baked = null
	_playtime = 0.0
	_last_save_playtime = 0.0
	_autosave_reason = ""
	Net.level_path = level_scene.resource_path
	Net.set_authority(baked)
	_start_from(baked)


## Guest: the host's state (joining, catching up after a desync, or the host
## restarted). Loads the host's level first if it is a different one.
func _on_snapshot(snapshot: SimState, path: String) -> void:
	if _level == null or path != level_scene.resource_path:
		level_scene = load(path)
		var session := await _load_level()
		if session != _session:
			return
	_ops = _ops.filter(func(op: Dictionary) -> bool: return op.seq > Net.synced_seq())
	_start_from(snapshot)


## Instantiates and bakes level_scene (the bake also sets up WorldSpace for
## drawing). The baked state is left in _baked. Returns the restart counter.
func _load_level() -> int:
	_session += 1
	var session := _session
	state = null
	_ops.clear()
	_playing = false
	_enemy_turn_running = false
	if level_scene == null:
		push_error("No level_scene set on %s" % name)
		return session
	if _level != null:
		_level.queue_free()
	_level = level_scene.instantiate() as GameLevel
	add_child(_level)
	var bake_start := Time.get_ticks_usec()
	_baked = await _level.bake()
	_perf["bake"] = (Time.get_ticks_usec() - bake_start) / 1000.0
	return session


func _start_from(start: SimState) -> void:
	state = start
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
	if state.combat.active:
		_show_banner("Round %d — %s" % [state.combat.round_number, "Your turn" if _is_players_turn() else "Enemy turn"])
	else:
		_show_banner("Explore")
	_pump()
	_after_ops_drained()


## Whether this player controls the selected character (else it is only
## being looked at: the partner's).
func _selected_is_mine() -> bool:
	var actor := state.get_entity(_selected_id) if state != null else null
	return actor != null and Net.may_control(Net.local_slot, actor)


## Whether the selected character can be given orders right now.
func _can_order() -> bool:
	return _can_command() and _selected_is_mine()


## Whether one of this player's characters can still do anything this turn:
## step somewhere, or use an action it can afford that isn't cooling down.
func _has_moves(e: SimEntity) -> bool:
	if not e.is_alive() or e.ap <= 0:
		return false
	if CombatRules.move_budget(e) >= SimPathfinder.COST_STRAIGHT and not SimPathfinder.neighbors(state, e.cell, e.id).is_empty():
		return true
	for action in ActionInfo.actions_for(e):
		if action in [SimAbilities.Ability.REVIVE, SimAbilities.Ability.HELP_UP, SimAbilities.Ability.PICKPOCKET]:
			continue  # only usable in special situations; not "moves left"
		if e.ap >= ActionInfo.cost(action) and ActionInfo.remaining(action, e) == 0:
			return true
	for other in CombatRules.fighters(state, e.faction):
		if other.knocked_down and SimAbilities.is_adjacent(e.cell, other.cell) and e.ap >= ActionInfo.cost(SimAbilities.Ability.HELP_UP):
			return true
	return false


## Selected character (this player's) starts or stops sneaking.
func _toggle_sneak() -> void:
	var e := state.get_entity(_selected_id) if state != null else null
	if e == null or not _can_order() or state.combat.active:
		return
	Net.submit(SneakCommand.new(e.id, not e.sneaking))


## An NPC this player could start talking to (outside combat, not hostile).
func _talkable(e: SimEntity) -> bool:
	return (e != null and e.is_alive() and e.dialogue != "" and SimDialogue.knots.has(e.dialogue)
			and e.faction != SimEntity.Faction.ENEMIES and e.faction != SimEntity.Faction.PLAYERS
			and not state.combat.active and state.conversation.is_empty())


func _can_command() -> bool:
	return state != null and not _busy and not Net.ready_slots.has(Net.local_slot) \
			and (_is_players_turn() or _exploring())


## Real time: no fight is on and the party is alive.
func _exploring() -> bool:
	return state != null and not state.combat.active \
			and not CombatRules.fighters(state, SimEntity.Faction.PLAYERS).is_empty()


## One real-time tick from the op stream. If it starts combat (someone was
## spotted), switch over.
func _apply_tick() -> void:
	var t0 := Time.get_ticks_usec()
	var selected := state.get_entity(_selected_id)
	var was_walking := selected != null and not selected.travel.is_empty()
	state.step()
	_perf["tick"] = (Time.get_ticks_usec() - t0) / 1000.0
	_present(state, state.drain_events())
	if state.combat.active:
		_tick_accumulator = 0.0
		_show_banner("Combat!")
		_select_next(true)
		_update_range()
		_update_preview()
	elif was_walking and state.get_entity(_selected_id).travel.is_empty():
		_update_preview()  # arrived: what the cursor offers may have changed (e.g. talk)


## Walks the selected character to `dest`; the rest of this player's party
## follows to free cells around it, nearest first.
func _travel_party(dest: Vector3i) -> void:
	var leader := state.get_entity(_selected_id)
	if leader == null or not TravelCommand.new(leader.id, dest).validate(state):
		return
	Net.submit(TravelCommand.new(leader.id, dest))
	var taken := {dest: true}
	for member in _my_party():
		if member.id == leader.id:
			continue
		var spot: Variant = _formation_cell(dest, taken, member.id)
		if spot != null:
			taken[spot] = true
			Net.submit(TravelCommand.new(member.id, spot))


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
	if state == null or _hover == null:
		return
	var cell: Vector3i = _hover
	var clicked := state.entity_at(cell)
	var party_member := clicked != null and clicked.takes_turns() and clicked.faction == SimEntity.Faction.PLAYERS
	if party_member and _action == ActionInfo.NONE and not _busy:
		_select(clicked.id, false)  # the partner's too, to look at
		return
	if not _can_order():
		return
	if _action == ActionInfo.NONE and _talkable(clicked):
		var talk := TalkCommand.new(_selected_id, clicked.id)
		if talk.validate(state):
			Net.submit(talk)
		else:
			# Walk next to them first; click again to talk.
			var spot: Variant = _formation_cell(cell, {cell: true}, _selected_id)
			if spot != null:
				_travel_party(spot)
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
	_confirm_cell = null
	Net.submit(command)


## Plays a player command from the op stream. Actions against a target first
## swing the camera to frame caster and target, play out, then swing back
## (only for this player's own characters; the partner's camera is theirs).
func _play_action(command: SimCommand) -> void:
	var session := _session
	var actor := _actor_of(command)
	var own := actor != null and Net.may_control(Net.local_slot, actor)
	var target: Variant = _target_point(command, actor)
	if not own or target == null:
		_apply_or_resync(command)
		_after_action()
		if own and command is TravelCommand and actor.id == _selected_id:
			_rig.follow(_entity_renderer.view_of(actor.id), actor.travel.size() / EXPLORE_TICKS_PER_SECOND + 0.5)
		return
	_busy = true
	_update_range()
	_update_preview()
	_rig.frame_pair(_body_point(actor.cell), target, CAMERA_FRAME_SECONDS)
	await get_tree().create_timer(CAMERA_FRAME_SECONDS).timeout
	if session != _session:
		return
	_apply_or_resync(command)
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


## Applies a command from the host. The host already validated it, so failing
## here means this copy has drifted: ask for a fresh snapshot.
func _apply_or_resync(command: SimCommand) -> bool:
	if state.apply_command(command):
		return true
	push_warning("A command from the host doesn't apply here; resyncing: %s" % command.to_dict())
	Net.request_snapshot()
	return false


# --- Saving --------------------------------------------------------------------

## Why the game can't be saved right now, or "" if it can: only the host
## saves, and only between actions (in combat: on the party's turn).
func _save_blocker() -> String:
	if not Net.is_host():
		return "Only the host can save."
	if state == null or Net.authority == null:
		return "Nothing to save yet."
	if _busy or _playing or not _ops.is_empty() or _enemy_turn_running:
		return "Wait for the current action to finish."
	if state.combat.active and not _is_players_turn():
		return "Wait for your turn."
	return ""


func _autosave_due() -> bool:
	return Net.is_host() and (_autosave_reason != "" or _playtime - _last_save_playtime >= AUTOSAVE_SECONDS)


## Writes the host's state to `slot`. Returns whether it worked.
func _save(slot: String, title: String) -> bool:
	if title == "":
		title = Net.level_path.get_file().get_basename().capitalize()
	var error := SaveStore.write(slot, title, Net.authority, Net.level_path, int(_playtime))
	_last_save_playtime = _playtime
	_autosave_reason = ""
	if error != OK:
		_show_banner("Saving failed: %s" % error_string(error))
		return false
	return true


func _quicksave() -> void:
	var blocker := _save_blocker()
	if blocker != "":
		_show_banner(blocker)
	elif _save(SaveStore.QUICK, "Quicksave"):
		_show_banner("Quicksaved")


func _quickload() -> void:
	if SaveStore.read_header(SaveStore.QUICK).is_empty():
		_show_banner("No quicksave yet")
	else:
		_load_slot(SaveStore.QUICK)


## Host: replaces the world with a save (a connected guest is sent it, as on joining).
func _load_slot(slot: String) -> void:
	if not Net.is_host():
		_show_banner("Only the host can load.")
		return
	var data := SaveStore.read(slot)
	if data.is_empty():
		_show_banner("That save can't be loaded (damaged, or from a newer version).")
		return
	_start_save(data)


## Loads the save's level for its scenery, then plays from the saved state
## instead of the fresh bake.
func _start_save(data: Dictionary) -> void:
	var header: Dictionary = data.header
	var path: String = header.get("level", "")
	if not ResourceLoader.exists(path):
		_show_banner("That save's level is missing: %s" % path)
		if state == null:
			_restart()
		return
	level_scene = load(path)
	var session := await _load_level()
	if session != _session:
		return
	_baked = null
	var loaded: SimState = data.state
	Net.level_path = path
	Net.set_authority(loaded)
	_start_from(loaded)
	_playtime = header.get("playtime", 0)
	_last_save_playtime = _playtime
	_autosave_reason = ""
	_show_banner("Loaded: %s" % header.get("title", ""))


# --- The op stream ------------------------------------------------------------

## The session ended (couldn't connect, the host left, or we left): back to
## the menu, which shows why.
func _on_session_ended(reason: String) -> void:
	_session += 1  # stops anything still animating
	if reason != "":
		_show_banner(reason)
	await get_tree().create_timer(2.0 if reason != "" else 0.1).timeout
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_partner_changed(joined: bool) -> void:
	if joined:
		_show_banner("Your partner joined")
	else:
		_show_banner("Your partner left — you control their characters")
	_select_next(true)
	_refresh()


func _on_op(op: Dictionary) -> void:
	_ops.append(op)
	_pump()


## Plays queued ops one after another (each may animate).
func _pump() -> void:
	if _playing or state == null:
		return
	_playing = true
	var session := _session
	while not _ops.is_empty():
		var op: Dictionary = _ops.pop_front()
		await _play_op(op)
		if session != _session:
			return
		if state != null:
			Net.verify(state, op)
	_playing = false
	_after_ops_drained()


func _play_op(op: Dictionary) -> void:
	match op.k:
		"tick":
			_apply_tick()
		"cmd":
			var command := SimCommandRegistry.from_dict(op.c)
			if command is EndTurnCommand:
				await _play_end_turn(command as EndTurnCommand)
			elif op.slot == NetSession.AI_SLOT:
				await _play_enemy_action(command)
			else:
				await _play_action(command)


## Waits until every queued op has been played.
func _ops_idle() -> void:
	while _playing or not _ops.is_empty():
		await get_tree().process_frame


## Host: once the stream is played out, the enemies act if it is their side.
func _after_ops_drained() -> void:
	if Net.is_host() and state != null and state.combat.active \
			and state.combat.side == SimEntity.Faction.ENEMIES and not _enemy_turn_running:
		_run_enemy_turn()


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
	if not _can_order():
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
		Net.submit(command)


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
	Net.set_ready(true)


## A side's turn ended (from the stream): animate the world, then hand over to
## the next side.
func _play_end_turn(command: EndTurnCommand) -> void:
	var session := _session
	await _finish_side(command.faction)
	if session != _session:
		return
	if state.combat.active and state.combat.side == SimEntity.Faction.ENEMIES:
		_busy = true
		_show_banner("Enemy turn")
	else:
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
	# The ticks were already shown on the ghost; show the turn change and
	# everything that happens at the new turn's start (burning, joiners).
	var flow: Array[SimEvent] = []
	var turn_started := false
	for e in state.drain_events():
		turn_started = turn_started or e.type == SimEvent.Type.TURN_STARTED
		if turn_started or e.type in [SimEvent.Type.COMBAT_ENDED, SimEvent.Type.COMBAT_STARTED]:
			flow.append(e)
	_present(state, flow)
	if not state.combat.active:
		_show_banner("Defeat" if CombatRules.fighters(state, SimEntity.Faction.PLAYERS).is_empty() else "Victory!")


## Whether the player would see any difference, to skip ticks where nothing changes.
static func _looks_same(a: SimGrid, b: SimGrid) -> bool:
	return a.surface_type == b.surface_type and a.surface_amount == b.surface_amount 			and a.gas_type == b.gas_type and a.fire == b.fire


## Host: the enemy side. Each action is thought out off the main thread on the
## authoritative state and sent through the stream like a player's; the host
## waits for each to play out (here and, roughly, on the guest) before the next.
func _run_enemy_turn() -> void:
	_enemy_turn_running = true
	var session := _session
	await get_tree().create_timer(0.5).timeout
	while session == _session and Net.authority.combat.active and Net.authority.combat.side == SimEntity.Faction.ENEMIES:
		await _ops_idle()
		if session != _session:
			return
		var command: SimCommand = await _think()
		if session != _session:
			return
		var applied_before := Net.op_count()
		Net.submit_ai(command)
		if Net.op_count() == applied_before:
			push_error("AI produced an invalid command: %s" % command.to_dict())
			Net.submit_ai(EndTurnCommand.new(SimEntity.Faction.ENEMIES))
		await _ops_idle()
	_enemy_turn_running = false


## An enemy action from the stream: telegraphed (camera, markers, caption),
## applied, and given time to play out.
func _play_enemy_action(command: SimCommand) -> void:
	var session := _session
	_busy = true
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
	if not _apply_or_resync(command):
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
	var snapshot := Net.authority.duplicate_state()
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
		elif e.type == SimEvent.Type.QUEST_STARTED and QuestRules.quests.has(e.text):
			_show_banner("New quest: %s   (J: journal)" % QuestRules.quests[e.text].title)
			_autosave_reason = "new quest"
		elif e.type == SimEvent.Type.QUEST_ENDED and QuestRules.quests.has(e.text):
			_show_banner("Quest ended: %s" % QuestRules.quests[e.text].title)
			_autosave_reason = "quest ended"
		elif e.type == SimEvent.Type.COMBAT_STARTED:
			_autosave_reason = "fight"
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
	if actor == null or not _selected_is_mine():
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


## The party members this player controls.
func _my_party() -> Array[SimEntity]:
	var mine: Array[SimEntity] = []
	for e in CombatRules.fighters(state, SimEntity.Faction.PLAYERS):
		if Net.may_control(Net.local_slot, e):
			mine.append(e)
	return mine


func _select_index(index: int) -> void:
	var party := CombatRules.fighters(state, SimEntity.Faction.PLAYERS)
	if index < party.size():
		_select(party[index].id)


## Selects the next party member, preferring ones with AP left. With
## keep_current, the current selection stays if it can still act.
func _select_next(keep_current: bool = false) -> void:
	var party := _my_party()
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
		if cast.ability == SimAbilities.Ability.PICKPOCKET and state.combat.active:
			return "Pickpocketing works outside combat"
		if cast.ability == SimAbilities.Ability.REVIVE:
			if state.combat.active:
				return "Revive works after the fight"
			if state.corpse_at(cast.target) == null:
				return "Pick a fallen ally"
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
	if _can_order() and actor != null and actor.is_alive():
		if action == ActionInfo.NONE and _exploring():
			var watched := _watched_cells()
			cells.append_array(watched[0])
			colors.append_array(watched[1])
		elif action == ActionInfo.NONE:
			var reach := SimPathfinder.reachable(state, actor.cell, CombatRules.move_budget(actor), actor.id)
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


## Vision cones on the ground near the party: where enemies would spot you
## (red: a fight starts) and townsfolk would witness you (yellow, orange when
## suspicious). Drawn for the selected character's sneaking state. Each
## watcher's cells are cached until it moves or turns. Returns
## [cells, colors].
func _watched_cells() -> Array:
	var party := CombatRules.fighters(state, SimEntity.Faction.PLAYERS)
	var selected := state.get_entity(_selected_id)
	var sneaking := selected != null and selected.sneaking
	var occupied := SimPathfinder.occupancy(state)
	var cells: Array[Vector3i] = []
	var colors: Array[Color] = []
	var seen := {}
	for watcher in state.entities:
		var enemy := watcher.faction == SimEntity.Faction.ENEMIES
		var neutral := watcher.faction == SimEntity.Faction.NEUTRAL
		if not (enemy or neutral) or not watcher.is_alive() or watcher.sight <= 0:
			continue
		if not _near_any(watcher.cell, party, DANGER_SHOW_RADIUS):
			continue
		var key := [watcher.id, watcher.cell, watcher.facing, sneaking, watcher.sight]
		if not _danger_cache.has(key):
			_danger_cache[key] = _cells_seen_by(watcher, occupied, sneaking)
		var color := COLOR_DANGER if enemy else (COLOR_SUSPICIOUS if watcher.suspicious else COLOR_WATCHED)
		for c: Vector3i in _danger_cache[key]:
			if not seen.has(c):
				seen[c] = true
				cells.append(c)
				colors.append(color)
	return [cells, colors]


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


func _cells_seen_by(watcher: SimEntity, occupied: Dictionary, sneaking: bool) -> Array[Vector3i]:
	var grid := state.grid
	var r := watcher.sight
	var result: Array[Vector3i] = []
	for z in range(watcher.cell.z - r, watcher.cell.z + r + 1):
		for x in range(watcher.cell.x - r, watcher.cell.x + r + 1):
			for y in range(maxi(watcher.cell.y - r, 0), mini(watcher.cell.y + r + 1, grid.size.y)):
				var c := Vector3i(x, y, z)
				if not grid.in_bounds(c) or grid.is_solid(c) or not (grid.is_supported(c) or occupied.has(c)):
					continue
				if SimPerception.sees_cell(state, watcher, c, sneaking):
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
			var mine := Net.may_control(Net.local_slot, e)
			if e.id == _selected_id:
				cells.append(e.cell)
				colors.append(COLOR_SELECTED if mine else COLOR_PARTNER)
			elif e.ap > 0 and mine:
				cells.append(e.cell)
				colors.append(COLOR_HAS_AP)
	if _teleport_target != null:
		cells.append(_teleport_target)
		colors.append(COLOR_TARGET)

	if _can_order() and _hover != null and actor != null and _action == ActionInfo.NONE and _talkable(hovered):
		cells.append(_hover)
		colors.append(COLOR_CURSOR)
		var talk := TalkCommand.new(_selected_id, hovered.id)
		_preview_text = "Talk to %s" % hovered.name if talk.validate(state) else "Walk over to talk to %s" % hovered.name
	elif _can_order() and _hover != null and actor != null:
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
	_entity_renderer.fire_field = _fire_field
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
	_party_bar.item_dropped.connect(func(to_id: int, from_id: int, index: int) -> void:
		Net.submit(GiveCommand.new(from_id, to_id, index)))
	_party_bar.end_turn_pressed.connect(func() -> void:
		if _confirming_end_turn:
			_end_turn(true)
		else:
			_end_turn())

	_dialogue = DialoguePanel.new()
	canvas.add_child(_dialogue)
	_dialogue.chosen.connect(func(index: int) -> void:
		if state != null and not state.conversation.is_empty():
			Net.submit(ChooseCommand.new(state.conversation.talker, index)))
	_journal = JournalPanel.new()
	canvas.add_child(_journal)
	_save_menu = SaveMenu.new()
	_save_menu.z_index = 10  # above the other panels
	canvas.add_child(_save_menu)
	_save_menu.save_requested.connect(func(title: String) -> void:
		if _save(SaveStore.new_slot(), title):
			_save_menu.saved())
	_save_menu.load_requested.connect(func(slot: String) -> void:
		_save_menu.close()
		_load_slot(slot))
	_save_menu.quit_requested.connect(func() -> void: Net.leave())

	_inventory = InventoryPanel.new()
	canvas.add_child(_inventory)
	_inventory.give_requested.connect(func(from_id: int, to_id: int, index: int) -> void:
		Net.submit(GiveCommand.new(from_id, to_id, index)))
	_inventory.sort_requested.connect(func(entity_id: int, from_index: int, to_index: int) -> void:
		Net.submit(SortItemCommand.new(entity_id, from_index, to_index)))

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
	var party := CombatRules.fighters(shown, SimEntity.Faction.PLAYERS)
	var partner_ids := {}
	var out_of_moves := _is_players_turn()
	for e in party:
		if not Net.may_control(Net.local_slot, e):
			partner_ids[e.id] = true
		elif _has_moves(e):
			out_of_moves = false
	var end_turn := PartyBar.EndTurn.NORMAL
	if _is_players_turn() and Net.ready_slots.has(Net.local_slot):
		end_turn = PartyBar.EndTurn.WAITING
	elif _can_command() and out_of_moves:
		end_turn = PartyBar.EndTurn.SUGGESTED
	_party_bar.update_party(party, _selected_id, _turn_start_ap, _preview_cost, _can_command() and _is_players_turn(), partner_ids, end_turn)
	var actor := state.get_entity(_selected_id)
	var talker := state.get_entity(state.conversation.get("talker", -1)) if not state.conversation.is_empty() else null
	_dialogue.show_conversation(state, talker != null and Net.may_control(Net.local_slot, talker))
	_journal.show_journal(state)
	_inventory.show_for(actor, party, _selected_is_mine() and not state.combat.active, _selected_is_mine())
	var note := "" if actor == null or _selected_is_mine() else "%s is controlled by your partner" % actor.name
	_action_bar.show_actions(actor if actor != null and actor.is_alive() else null, _action, _can_order(), state.combat.active, note)
	var lines: Array[String] = []
	if state.combat.active:
		var turn := "Your turn" if _is_players_turn() else "Enemy turn..."
		if _is_players_turn() and Net.ready_slots.has(Net.local_slot):
			turn = "Waiting for your partner to end the turn..."
		elif _is_players_turn() and not Net.ready_slots.is_empty():
			turn = "Your turn — your partner is ready"
		lines.append("Round %d — %s" % [state.combat.round_number, turn])
	elif _exploring():
		var sneaking := actor != null and actor.sneaking
		lines.append("Exploring — sneaking (C to stop)" if sneaking else "Exploring")
	else:
		lines.append("Combat over — press R to restart")
	if Net.is_online():
		var partner := "partner connected" if Net.connected_slots.size() > 1 else "waiting for a partner to join"
		var ping := Net.ping_ms()
		var line := "Co-op: %s (%s)" % ["hosting" if Net.is_host() else "joined", partner]
		if ping >= 0:
			line += "   ping %d ms" % ping
		if Net.is_host() and Net.connected_slots.size() == 1:
			line += "   join at: %s" % ", ".join(NetSession.host_addresses())
		lines.append(line + "   F10: leave")
	if _preview_text != "" and _preview_text != "Walk":  # plain walking needs no caption
		lines.append(_preview_text)
	if _show_help:
		if actor != null:
			var items := ", ".join(actor.inventory) if not actor.inventory.is_empty() else "nothing"
			var whose := "" if _selected_is_mine() else "   (your partner's — you can't control them)"
			lines.append("%s the %s   weapon: %s   carrying: %s%s" % [actor.name, SimArchetypes.title(actor.archetype), actor.weapon if actor.weapon != "" else "none", items, whose])
		lines.append("Ground tint — red: enemies see you there, yellow: townsfolk watch")
		lines.append("RMB move   LMB use / select   1-9 actions   Esc cancel / menu   F1-F4 / Tab select   Enter end turn   Space (hold) fast-forward")
		lines.append("C sneak   I inventory   J journal   Alt (hold) names + health   F5 / F9 quicksave / load   R restart")
		lines.append("WASD pan   Q/E or middle-drag rotate   wheel zoom   P look: %s   ` perf   H hide" % _retro.style_name())
	else:
		lines.append("H: controls")
	if _show_perf or log_perf:
		lines.append(_perf_text())
	_hud.text = "\n".join(lines)
	_log_label.text = "\n".join(_log)
