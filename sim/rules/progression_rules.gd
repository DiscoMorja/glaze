class_name ProgressionRules
extends RefCounted
## Experience and levels. XP is shared: every party member (fallen ones too)
## gets all of it, so nobody falls behind for being the healer. It comes from
## defeating fighters and from quest outcomes (QuestRules). Each level gives a
## little HP, an attribute point and a combat (school) point; every other
## level a civil point too (GDD §5.9). Points are spent with SpendPointCommand
## on any StatRules stat. Talents (creation, 5, 10) come later.

## XP for defeating a fighter, per point of its max HP.
const XP_PER_HP := 4
## Max HP every level up gives, before points.
const HP_PER_LEVEL := 2


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
			level_up(e)
			state.emit_event(SimEvent.Type.LEVELED_UP, e.cell, e.id, -1, e.level)


static func level_up(e: SimEntity) -> void:
	e.level += 1
	e.points += 1
	e.combat_points += 1
	if e.level % 2 == 0:
		e.civil_points += 1
	e.max_hp += HP_PER_LEVEL
	if e.is_alive():
		e.hp += HP_PER_LEVEL


## A fighter not on the party's side fell: the party learns from it.
static func on_death(state: SimState, e: SimEntity) -> void:
	if e.takes_turns() and e.faction == SimEntity.Faction.ENEMIES:
		award(state, e.max_hp * XP_PER_HP)


## Unspent points that can buy `stat`, a StatRules key (-1 if it isn't one).
static func pool(e: SimEntity, stat: String) -> int:
	if StatRules.ATTRIBUTES.has(stat):
		return e.points
	if StatRules.SCHOOLS.has(stat):
		return e.combat_points
	if StatRules.CIVIL.has(stat):
		return e.civil_points
	return -1


## Whether a point can go into `stat` now: one to spend, and below the cap
## (attributes have none; schools and civil skills stop at StatRules.MAX_RANK).
static func can_spend(e: SimEntity, stat: String) -> bool:
	if pool(e, stat) <= 0:
		return false
	return StatRules.is_attribute(stat) or StatRules.value(e, stat) < StatRules.MAX_RANK


## Spends one point on `stat`.
static func spend(e: SimEntity, stat: String) -> void:
	if StatRules.ATTRIBUTES.has(stat):
		e.points -= 1
	elif StatRules.SCHOOLS.has(stat):
		e.combat_points -= 1
	else:
		e.civil_points -= 1
	StatRules.set_value(e, stat, StatRules.value(e, stat) + 1)
