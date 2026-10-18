class_name TalkCommand
extends SimCommand
## Outside combat: a party member starts talking to an NPC next to them (2
## cells) that has something to say and isn't hostile. One conversation at a
## time; the partner watches it.

const TYPE := "talk"
const REACH := 2

var talker_id: int
var npc_id: int


func _init(p_talker_id: int = -1, p_npc_id: int = -1) -> void:
	talker_id = p_talker_id
	npc_id = p_npc_id


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return talker_id


func validate(state: SimState) -> bool:
	var talker := state.get_entity(talker_id)
	var npc := state.get_entity(npc_id)
	if state.combat.active or not state.conversation.is_empty() or talker == null or npc == null:
		return false
	if talker.faction != SimEntity.Faction.PLAYERS or not talker.is_alive() or not npc.is_alive():
		return false
	if npc.dialogue == "" or not SimDialogue.knots.has(npc.dialogue) or npc.faction == SimEntity.Faction.ENEMIES:
		return false
	return maxi(absi(npc.cell.x - talker.cell.x), absi(npc.cell.z - talker.cell.z)) <= REACH


func execute(state: SimState) -> void:
	var npc := state.get_entity(npc_id)
	SimDialogue.start(state, state.get_entity(talker_id), npc, npc.dialogue)


func to_dict() -> Dictionary:
	return {"type": TYPE, "talker_id": talker_id, "npc_id": npc_id}


static func from_dict(data: Dictionary) -> TalkCommand:
	return TalkCommand.new(data.talker_id, data.npc_id)
