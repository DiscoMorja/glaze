class_name ChooseCommand
extends SimCommand
## The talking party member picks a choice in the conversation; index -1
## leaves it (at its end, or walking away).

const TYPE := "choose"

var talker_id: int
var index: int


func _init(p_talker_id: int = -1, p_index: int = -1) -> void:
	talker_id = p_talker_id
	index = p_index


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return talker_id


func validate(state: SimState) -> bool:
	var convo := state.conversation
	if convo.is_empty() or convo.talker != talker_id:
		return false
	return index == -1 or (index >= 0 and index < convo.choices.size())


func execute(state: SimState) -> void:
	if index == -1:
		SimDialogue.end(state)
	else:
		SimDialogue.choose(state, index)


func to_dict() -> Dictionary:
	return {"type": TYPE, "talker_id": talker_id, "index": index}


static func from_dict(data: Dictionary) -> ChooseCommand:
	return ChooseCommand.new(data.talker_id, data.index)
