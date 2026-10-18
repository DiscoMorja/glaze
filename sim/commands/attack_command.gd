class_name AttackCommand
extends SimCommand
## Weapon attack on an entity (characters and props alike): adjacent, or in
## range and sight with a weapon that has "ranged" (bows, slings), which hits
## harder from above (StatRules.hit_damage()).

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
			and (SimAbilities.is_adjacent(attacker.cell, target.cell) or in_reach(state, attacker, target.cell)))


## Cells the attacker's weapon reaches: its "ranged" range, 1 for melee.
static func reach(attacker: SimEntity) -> int:
	return maxi(1, SimItems.amount(attacker.weapon, "ranged"))


## A ranged weapon in hand, the cell within its range and in sight.
static func in_reach(state: SimState, attacker: SimEntity, c: Vector3i) -> bool:
	var range_cells := SimItems.amount(attacker.weapon, "ranged")
	return (range_cells > 0 and c != attacker.cell and SimAbilities.in_range(attacker.cell, c, range_cells)
			and SimLos.has_line_of_sight(state.grid, attacker.cell, c))


func execute(state: SimState) -> void:
	var attacker := state.get_entity(attacker_id)
	var target := state.get_entity(target_id)
	CombatRules.spend(state, attacker, CombatRules.ATTACK_AP)
	state.emit_event(SimEvent.Type.ATTACKED, target.cell, target.id, attacker.id)
	EntityOps.damage(state, target, StatRules.hit_damage(attacker, target), attacker.id)


func actor_id() -> int:
	return attacker_id


func to_dict() -> Dictionary:
	return {"type": TYPE, "attacker_id": attacker_id, "target_id": target_id}


static func from_dict(data: Dictionary) -> AttackCommand:
	return AttackCommand.new(data.attacker_id, data.target_id)
