class_name SpendPointCommand
extends SimCommand
## A party member spends a level-up point on an attribute, a school rank or a
## civil skill (StatRules keys; ProgressionRules.spend()).
## Any time, free.

const TYPE := "spend_point"

var entity_id: int
var stat: String


func _init(p_entity_id: int = -1, p_stat: String = "") -> void:
	entity_id = p_entity_id
	stat = p_stat


func get_type() -> String:
	return TYPE


func actor_id() -> int:
	return entity_id


func validate(state: SimState) -> bool:
	var e := state.get_entity(entity_id)
	return e != null and e.faction == SimEntity.Faction.PLAYERS and ProgressionRules.can_spend(e, stat)


func execute(state: SimState) -> void:
	ProgressionRules.spend(state.get_entity(entity_id), stat)


func to_dict() -> Dictionary:
	return {"type": TYPE, "entity_id": entity_id, "stat": stat}


static func from_dict(data: Dictionary) -> SpendPointCommand:
	return SpendPointCommand.new(data.entity_id, data.stat)
