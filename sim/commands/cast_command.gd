class_name CastCommand
extends SimCommand
## Uses one of the SimAbilities verbs. `destination` is only used by abilities
## with a second target (Teleport); `item` by Pickpocket (which pocket item a
## thief chooses; -1 = the first).

const TYPE := "cast"

var caster_id: int
var ability: int
var target: Vector3i
var destination: Vector3i
var item: int


func _init(p_caster_id: int = -1, p_ability: int = 0, p_target: Vector3i = Vector3i.ZERO, p_destination: Vector3i = Vector3i.ZERO, p_item: int = -1) -> void:
	caster_id = p_caster_id
	ability = p_ability
	target = p_target
	destination = p_destination
	item = p_item


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	var caster := state.get_entity(caster_id)
	return caster != null and SimAbilities.validate(state, caster, ability, target, destination, item)


func execute(state: SimState) -> void:
	SimAbilities.execute(state, state.get_entity(caster_id), ability, target, destination, item)


func actor_id() -> int:
	return caster_id


func to_dict() -> Dictionary:
	return {"type": TYPE, "caster_id": caster_id, "ability": ability, "target": target, "destination": destination, "item": item}


static func from_dict(data: Dictionary) -> CastCommand:
	return CastCommand.new(data.caster_id, data.ability, data.target, data.destination, data.get("item", -1))
