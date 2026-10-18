class_name NetSession
extends Node
## The co-op session (autoload "Net"). Playing alone is a session too: the
## host with no guest, through exactly the same path (GDD 8.5).
##
## The sim is deterministic, so peers stay in sync by running the same
## commands in the same order (no state deltas):
##   - Players submit() commands. The host checks that the sender controls the
##     acting entity and that the command is valid on its authoritative state,
##     applies it there, and broadcasts it as the next op of one ordered stream.
##   - Real-time ticks (exploration) are ops too; only the host ticks.
##   - Every peer, the host included, plays the stream in order on its own copy
##     of the sim (op_received), animating as it goes.
##   - A joining guest gets a full snapshot first; ops carry checksums now and
##     then, and a guest that drifts asks for a fresh snapshot.
## The party's turn is shared: it ends when every player has pressed End Turn.

signal op_received(op: Dictionary)
## Guest: a full state to start from (or catch up with), and the level it is in.
signal snapshot_received(state: SimState, level_path: String)
## Players joined or left, or someone pressed End Turn.
signal players_changed

enum Mode { NONE, SOLO, HOST, GUEST }

const DEFAULT_PORT := 24560
const HOST_SLOT := 0
const GUEST_SLOT := 1
## Slots for commands the host issues itself: enemy AI, and the turn ending.
const AI_SLOT := -2
const SYSTEM_SLOT := -3
## Ticks between checksums in real time (combat commands always carry one).
const CHECKSUM_EVERY_TICKS := 16

var mode := Mode.NONE
## This machine's player slot.
var local_slot := HOST_SLOT
var level_path := ""
## Player slots in the session (replicated to the guest).
var connected_slots: Array[int] = [HOST_SLOT]
## Slot -> true for players who pressed End Turn this turn (replicated).
var ready_slots := {}
## Host only: the authoritative state. Ops are applied to it as soon as they
## are accepted; the copy the game animates follows through op_received.
var authority: SimState
var last_error := ""

var _seq := 0
var _synced_seq := -1
var _guest_peer := -1
## Guest: a snapshot, and ops, that arrived before the game scene was ready
## to take them (see claim_backlog()).
var _pending_snapshot: SimState
var _pending_level := ""
var _backlog: Array[Dictionary] = []


## Ops broadcast so far (host), e.g. to tell whether a submit was accepted.
func op_count() -> int:
	return _seq


## Guest: the last op already contained in the snapshot it started from.
func synced_seq() -> int:
	return _synced_seq


func is_host() -> bool:
	return mode == Mode.SOLO or mode == Mode.HOST


func is_online() -> bool:
	return mode == Mode.HOST or mode == Mode.GUEST


# --- Starting -----------------------------------------------------------------

func start_solo(p_level_path: String) -> void:
	_reset(Mode.SOLO, p_level_path)


func host(p_level_path: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 1)
	if error != OK:
		last_error = "Couldn't host on port %d (error %d)" % [port, error]
		return error
	_reset(Mode.HOST, p_level_path)
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		last_error = "Couldn't connect to %s:%d (error %d)" % [address, port, error]
		return error
	_reset(Mode.GUEST, "")
	local_slot = GUEST_SLOT
	multiplayer.multiplayer_peer = peer
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


func _reset(p_mode: Mode, p_level_path: String) -> void:
	mode = p_mode
	level_path = p_level_path
	local_slot = HOST_SLOT
	connected_slots = [HOST_SLOT]
	ready_slots.clear()
	authority = null
	_seq = 0
	_synced_seq = -1
	_guest_peer = -1
	_pending_snapshot = null
	_backlog.clear()


## Host: the state everyone plays from (after baking or restarting the level).
## A connected guest is sent a fresh snapshot.
func set_authority(state: SimState) -> void:
	authority = state.duplicate_state()
	ready_slots.clear()
	if mode == Mode.HOST and _guest_peer != -1:
		_send_snapshot(_guest_peer)


## Guest: asks the host for a fresh snapshot (joining, or after a desync).
func request_snapshot() -> void:
	var peer := multiplayer.multiplayer_peer
	if mode == Mode.GUEST and peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_snapshot_request.rpc_id(1)


## Guest: hands a newly loaded game scene whatever arrived before it was ready
## (a snapshot, then ops), through the usual signals.
func claim_backlog() -> void:
	if _pending_snapshot != null:
		var pending := _pending_snapshot
		_pending_snapshot = null
		snapshot_received.emit(pending, _pending_level)
	var ops := _backlog.duplicate()
	_backlog.clear()
	for op: Dictionary in ops:
		op_received.emit(op)


# --- Players ------------------------------------------------------------------

## Whether `slot` may act with `e`: its own characters, and while playing
## alone (or with the other player gone) the whole party.
func may_control(slot: int, e: SimEntity) -> bool:
	if e == null:
		return false
	if e.faction == SimEntity.Faction.ENEMIES:
		return slot == AI_SLOT
	if e.faction != SimEntity.Faction.PLAYERS:
		return false
	return e.owner == slot or (slot == HOST_SLOT and not connected_slots.has(e.owner))


func _on_peer_connected(id: int) -> void:
	if _guest_peer != -1:
		multiplayer.multiplayer_peer.disconnect_peer(id)  # two players only
		return
	_guest_peer = id
	connected_slots = [HOST_SLOT, GUEST_SLOT]
	_send_snapshot(id)
	_broadcast_players()


func _on_peer_disconnected(id: int) -> void:
	if id != _guest_peer:
		return
	_guest_peer = -1
	connected_slots = [HOST_SLOT]
	ready_slots.erase(GUEST_SLOT)
	_broadcast_players()
	_try_end_players_turn()


func _on_server_disconnected() -> void:
	last_error = "The host left"
	mode = Mode.NONE
	multiplayer.multiplayer_peer = null
	players_changed.emit()


func _broadcast_players() -> void:
	if mode == Mode.HOST:
		_players.rpc(connected_slots, ready_slots)
	players_changed.emit()


@rpc("authority", "reliable")
func _players(slots: Array, ready: Dictionary) -> void:
	connected_slots.assign(slots)
	ready_slots = ready
	players_changed.emit()


# --- Commands -----------------------------------------------------------------

## Sends a command from this machine's player to the host.
func submit(command: SimCommand) -> void:
	if is_host():
		_accept(local_slot, command.to_dict())
	elif mode == Mode.GUEST:
		_command_request.rpc_id(1, command.to_dict())


## Host: an enemy action chosen by the AI.
func submit_ai(command: SimCommand) -> void:
	if is_host():
		_accept(AI_SLOT, command.to_dict())


## Host: one real-time tick (exploration).
func host_tick() -> void:
	if not is_host() or authority == null:
		return
	authority.step()
	authority.drain_events()
	var op := {"k": "tick"}
	if authority.tick % CHECKSUM_EVERY_TICKS == 0:
		op["sum"] = authority.checksum()
	_broadcast(op)


## This player is done with the party's turn (or takes it back).
func set_ready(ready: bool) -> void:
	if is_host():
		_set_ready(local_slot, ready)
	elif mode == Mode.GUEST:
		_ready_request.rpc_id(1, ready)


@rpc("any_peer", "reliable")
func _command_request(data: Dictionary) -> void:
	if is_host() and multiplayer.get_remote_sender_id() == _guest_peer:
		_accept(GUEST_SLOT, data)


@rpc("any_peer", "reliable")
func _ready_request(ready: bool) -> void:
	if is_host() and multiplayer.get_remote_sender_id() == _guest_peer:
		_set_ready(GUEST_SLOT, ready)


func _set_ready(slot: int, ready: bool) -> void:
	if ready:
		ready_slots[slot] = true
	else:
		ready_slots.erase(slot)
	_broadcast_players()
	_try_end_players_turn()


## Ends the party's turn once every player in the session is ready.
func _try_end_players_turn() -> void:
	if authority == null or not authority.combat.active or authority.combat.side != SimEntity.Faction.PLAYERS:
		return
	for slot in connected_slots:
		if not ready_slots.has(slot):
			return
	ready_slots.clear()
	_broadcast_players()
	_accept(SYSTEM_SLOT, EndTurnCommand.new(SimEntity.Faction.PLAYERS).to_dict())


func _accept(slot: int, data: Dictionary) -> void:
	if authority == null:
		return
	var command := SimCommandRegistry.from_dict(data)
	if command == null or not _allowed(slot, command) or not command.validate(authority):
		return
	authority.apply_command(command)
	authority.drain_events()
	if command is EndTurnCommand:
		ready_slots.clear()
	_broadcast({"k": "cmd", "c": data, "slot": slot, "sum": authority.checksum()})


func _allowed(slot: int, command: SimCommand) -> bool:
	if command is EndTurnCommand:
		var faction := (command as EndTurnCommand).faction
		return slot == SYSTEM_SLOT if faction == SimEntity.Faction.PLAYERS else slot == AI_SLOT
	var actor_id: int = command.actor_id()
	if actor_id == -1:
		return slot == SYSTEM_SLOT or slot == HOST_SLOT  # world commands: host only
	return may_control(slot, authority.get_entity(actor_id))


# --- The op stream ------------------------------------------------------------

func _broadcast(op: Dictionary) -> void:
	_seq += 1
	op["seq"] = _seq
	if mode == Mode.HOST:
		_deliver.rpc(op)
	else:
		_deliver(op)


@rpc("authority", "call_local", "reliable")
func _deliver(op: Dictionary) -> void:
	if mode == Mode.GUEST and op.seq <= _synced_seq:
		return  # already in the snapshot
	if op_received.get_connections().is_empty():
		_backlog.append(op)
		return
	op_received.emit(op)


## Guest: whether a state that has just played `op` agrees with the host.
## On a mismatch it asks for a fresh snapshot and returns false.
func verify(state: SimState, op: Dictionary) -> bool:
	if mode != Mode.GUEST or not op.has("sum") or state.checksum() == op.sum:
		return true
	push_warning("Desync at op %d; asking the host for a snapshot" % op.seq)
	request_snapshot()
	return false


@rpc("any_peer", "reliable")
func _snapshot_request() -> void:
	if is_host() and multiplayer.get_remote_sender_id() == _guest_peer:
		_send_snapshot(_guest_peer)


func _send_snapshot(peer: int) -> void:
	if authority == null:
		return
	_snapshot.rpc_id(peer, authority.to_snapshot(), level_path, _seq, GUEST_SLOT, connected_slots, ready_slots)


@rpc("authority", "reliable")
func _snapshot(bytes: PackedByteArray, p_level_path: String, seq: int, slot: int, slots: Array, ready: Dictionary) -> void:
	_synced_seq = seq
	local_slot = slot
	level_path = p_level_path
	connected_slots.assign(slots)
	ready_slots = ready
	var snapshot := SimState.from_snapshot(bytes)
	if snapshot_received.get_connections().is_empty():
		_pending_snapshot = snapshot
		_pending_level = p_level_path
		_backlog.clear()
	else:
		snapshot_received.emit(snapshot, p_level_path)
	players_changed.emit()
