class_name ProgressionRules
extends RefCounted
## Experience and levels. XP is shared: every party member (fallen ones too)
## gets all of it, so nobody falls behind for being the healer. It comes from
## defeating fighters and from quest outcomes (QuestRules). Each level gives a
## little HP and a point to spend (SpendPointCommand).

## XP for defeating a fighter, per point of its max HP.
const XP_PER_HP := 4
## Max HP every level up gives, before points.
const HP_PER_LEVEL := 2
## What a point buys.
const STATS := {
	"vitality": "+4 max HP",
	"power": "+1 damage with weapons and spells",
	"resolve": "+1 stagger before being knocked down",
}
const VITALITY_HP := 4


## Total XP needed to reach `level` (level 2 at 100, 3 at 300, 4 at 600...).
static func xp_for_level(level: int) -> int:
	return 50 * level * (level - 1)


## Gives every party member `amount` XP, levelling them up as it adds up.
static func award(state: SimState, amount: int) -> void:
	if amount <= 0:
		return
	for e in state.entities:
		if e.faction != SimEntity.Faction.PLAYERS or not e.takes_turns():
			continue
		e.xp += amount
		var gained := state.emit_event(SimEvent.Type.XP_GAINED, e.cell, e.id, -1, amount)
		gained.text = str(e.xp)
		while e.xp >= xp_for_level(e.level + 1):
			e.level += 1
			e.points += 1
			e.max_hp += HP_PER_LEVEL
			if e.is_alive():
				e.hp += HP_PER_LEVEL
			state.emit_event(SimEvent.Type.LEVELED_UP, e.cell, e.id, -1, e.level)


## A fighter not on the party's side fell: the party learns from it.
static func on_death(state: SimState, e: SimEntity) -> void:
	if e.takes_turns() and e.faction == SimEntity.Faction.ENEMIES:
		award(state, e.max_hp * XP_PER_HP)


## Spends one point on `stat` (a STATS key).
static func spend(e: SimEntity, stat: String) -> void:
	e.points -= 1
	match stat:
		"vitality":
			e.max_hp += VITALITY_HP
			e.hp += VITALITY_HP if e.is_alive() else 0
		"power":
			e.power += 1
		"resolve":
			e.stagger_max += 1
