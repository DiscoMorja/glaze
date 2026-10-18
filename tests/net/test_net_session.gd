extends GutTest
## Session rules (no network needed): who may act with whom, the shared End
## Turn, and the op stream every peer plays.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES

var _net: NetSession
var _ops: Array[Dictionary] = []


## A duel with a second party member owned by the guest (id 3), hosted alone.
func before_each() -> void:
	_net = NetSession.new()
	add_child_autofree(_net)
	_ops.clear()
	_net.op_received.connect(func(op: Dictionary) -> void: _ops.append(op))
	var state := Fixtures.duel_state()
	Fixtures.hero(state).owner = NetSession.HOST_SLOT
	var guest_unit := state.add_entity(SimEntity.character("Guest", PLAYERS, Vector3i(2, Y, 6), 20, "Sword", 4))
	guest_unit.owner = NetSession.GUEST_SLOT
	guest_unit.ap = 4  # joined mid-fight
	_net.start_solo("")
	_net.set_authority(state)


func _cmds() -> Array[Dictionary]:
	return _ops.filter(func(op: Dictionary) -> bool: return op.k == "cmd")


func test_an_accepted_command_is_applied_and_broadcast() -> void:
	_net._guest_peer = 2  # checksums are only made for a guest to compare
	_net.submit(MoveCommand.new(1, Vector3i(3, Y, 2)))
	assert_eq(_cmds().size(), 1)
	assert_eq(_net.authority.get_entity(1).cell, Vector3i(3, Y, 2))
	assert_true(_cmds()[0].has("sum"), "commands carry a checksum")
	assert_false(_cmds()[0].full, "a cheap one, without the grid")


func test_invalid_commands_are_dropped() -> void:
	_net.submit(MoveCommand.new(1, Vector3i(2, Y, 2)))  # already there
	assert_eq(_ops.size(), 0)


func test_alone_the_host_controls_the_whole_party() -> void:
	_net.submit(MoveCommand.new(3, Vector3i(3, Y, 6)))
	assert_eq(_cmds().size(), 1)


func test_with_a_guest_each_player_controls_only_their_own() -> void:
	_net.connected_slots = [NetSession.HOST_SLOT, NetSession.GUEST_SLOT]
	_net.submit(MoveCommand.new(3, Vector3i(3, Y, 6)))
	assert_eq(_cmds().size(), 0, "the host can't move the guest's character")
	_net._accept(NetSession.GUEST_SLOT, MoveCommand.new(3, Vector3i(3, Y, 6)).to_dict())
	assert_eq(_cmds().size(), 1, "the guest can")
	_net._accept(NetSession.GUEST_SLOT, MoveCommand.new(1, Vector3i(3, Y, 2)).to_dict())
	assert_eq(_cmds().size(), 1, "and can't move the host's")


func test_players_cannot_end_the_turn_or_move_enemies_directly() -> void:
	_net.submit(EndTurnCommand.new(PLAYERS))
	_net.submit(MoveCommand.new(2, Vector3i(8, Y, 9)))
	assert_eq(_cmds().size(), 0)
	_net.set_ready(true)  # alone: the enemies' turn
	_net.submit(MoveCommand.new(2, Vector3i(8, Y, 9)))
	assert_eq(_cmds().size(), 1, "the turn ended, but a player still can't move enemies")
	_net.submit_ai(MoveCommand.new(2, Vector3i(8, Y, 9)))
	assert_eq(_cmds().size(), 2, "the AI moves enemies")


func test_the_turn_ends_when_every_player_is_ready() -> void:
	_net.connected_slots = [NetSession.HOST_SLOT, NetSession.GUEST_SLOT]
	_net.set_ready(true)
	assert_eq(_cmds().size(), 0, "one player ready isn't enough")
	_net._set_ready(NetSession.GUEST_SLOT, true)
	assert_eq(_cmds().size(), 1)
	assert_eq(_net.authority.combat.side, ENEMIES)
	assert_true(_net.ready_slots.is_empty(), "ready resets for the next turn")


func test_alone_end_turn_is_immediate() -> void:
	_net.set_ready(true)
	assert_eq(_net.authority.combat.side, ENEMIES)


func test_ops_are_numbered_in_order() -> void:
	_net.submit(MoveCommand.new(1, Vector3i(3, Y, 2)))
	_net.submit(MoveCommand.new(3, Vector3i(3, Y, 6)))
	assert_eq(_ops[0].seq + 1, _ops[1].seq)


func test_alone_no_checksums_are_made() -> void:
	_net.submit(MoveCommand.new(1, Vector3i(3, Y, 2)))
	assert_false(_cmds()[0].has("sum"), "nobody to compare with: skip the cost")


func test_a_guest_replaying_the_stream_matches_the_host() -> void:
	_net._guest_peer = 2
	var guest := SimState.from_snapshot(_net.authority.to_snapshot())
	_net.submit(MoveCommand.new(1, Vector3i(4, Y, 3)))
	_net.set_ready(true)
	for op in _cmds():
		assert_true(guest.apply_command(SimCommandRegistry.from_dict(op.c)))
		assert_eq(guest.checksum(op.full), op.sum)
