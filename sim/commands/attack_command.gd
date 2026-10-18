class_name AttackCommand
extends SimCommand
## Melee attack on an adjacent entity (characters and props alike).

const TYPE := "attack"

var attacker_id: int
var target_id: int


func _init(p_attacker_id: int = -1, p_target_id: int = -1) -> void:
	attacker_id = p_attacker_id
	target_id = p_target_id


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	var attacker := state.get_entity(attacker_id)
	var target := state.get_entity(target_id)
	return (CombatRules.can_act(state, attacker, CombatRules.ATTACK_AP)
			and target != null and target.is_alive() and target != attacker
			and SimAbilities.is_adjacent(attacker.cell, target.cell))


func execute(state: SimState) -> void:
	var attacker := state.get_entity(attacker_id)
	var target := state.get_entity(target_id)
	CombatRules.spend(state, attacker, CombatRules.ATTACK_AP)
	state.emit_event(SimEvent.Type.ATTACKED, target.cell, target.id, attacker.id)
	EntityOps.damage(state, target, attacker.attack_damage(), attacker.id)


func actor_id() -> int:
	return attacker_id


func to_dict() -> Dictionary:
	return {"type": TYPE, "attacker_id": attacker_id, "target_id": target_id}


static func from_dict(data: Dictionary) -> AttackCommand:
	return AttackCommand.new(data.attacker_id, data.target_id)
