class_name StatRules
extends RefCounted
## Attributes, combat schools and civil skills (GDD §5.9). Every bonus is a
## small integer breakpoint ("+1 per 2 points"), never a percentage, and no
## rule rolls dice. Resistances shave numbers but never block an effect.
##
## Attributes (start at 0, a point per level):
##   strength   +1 damage per 2 with Str weapons (and fists); carry limit;
##              how heavy a thing you can shove
##   vitality   +3 max HP per point; +1 armour and +1 stagger limit per 4
##   dexterity  +1 damage per 2 with Dex weapons; +1 move unit per AP per
##              point; hits from behind deal +1 per 2
##   mind       +1 spell damage per 2 (staffs hit with it too); how heavy a
##              thing your Teleport moves
##   ward       fire and frost damage taken -1 per 3 (at most half a hit);
##              heals you cast +1 per 2, heals you receive +1 per 3
## Schools (ranks 0-5) gate the skills of their school (SimAbilities.SCHOOL /
## RANK) and add potency: +1 per rank above the skill's own.
## Civil skills (ranks 0-5): thievery, charisma, historian; thresholds only.

enum School { FIRE, ICE, LIFE, DEATH, PSYCHIC, WARRIOR, ROGUE, RANGER }
## Spend keys of the schools, by School value.
const SCHOOLS: Array[String] = ["fire", "ice", "life", "death", "psychic", "warrior", "rogue", "ranger"]
const ATTRIBUTES: Array[String] = ["strength", "vitality", "dexterity", "mind", "ward"]
const CIVIL: Array[String] = ["thievery", "charisma", "historian"]
const MAX_RANK := 5

const HP_PER_VITALITY := 3
## Carrying more than this (grams) slows you like oil does.
const CARRY_BASE := 20000
const CARRY_PER_STRENGTH := 4000
## Heaviest thing (kg) you can shove, and that your Teleport moves.
const SHOVE_BASE := 80
const SHOVE_PER_STRENGTH := 10
const TELEPORT_BASE := 100
const TELEPORT_PER_MIND := 10
## Thievery: the most valuable item a pickpocket can choose, per rank; from
## this rank anything goes.
const PICK_VALUE_PER_RANK := 30
const PICK_ANY_RANK := 3
## Thievery: sneak at full speed from this rank; walk silently (not heard) from this one.
const SNEAK_FAST_RANK := 2
const SILENT_RANK := 3

const DESCRIPTIONS := {
	"strength": "+1 damage per 2 with strength weapons and fists. Carry 4 kg more and shove 10 kg heavier per point.",
	"vitality": "+3 max HP per point. +1 armour and +1 stagger limit per 4.",
	"dexterity": "+1 damage per 2 with dexterity weapons, and per 2 when hitting from behind. Walk a little further per AP.",
	"mind": "+1 spell damage per 2 (staffs hit with it too). Teleport 10 kg heavier per point.",
	"ward": "-1 fire and frost damage taken per 3. Heals you cast +1 per 2; heals you get +1 per 3.",
	"fire": "Fire school: burning, heat, speed. Firebolt.",
	"ice": "Ice school: water, cold, cleansing. Rain, Frost.",
	"life": "Life school: healing, growing. Mend.",
	"death": "Death school: decay, darkness, draining. (No skills yet.)",
	"psychic": "Psychic school: mind and telekinesis. Teleport, Blink.",
	"warrior": "Warrior school: shields, two-handers, warfare. Shove, Cleave, Shockwave.",
	"rogue": "Rogue school: dirty tricks. Steal, Low Blow.",
	"ranger": "Ranger school: ranged weapons, survival. (No skills yet.)",
	"thievery": "Rank 1+: choose what to pickpocket (worth up to 30 gold per rank; anything at 3). Pick locks up to your rank with a lockpick. Sneak at full speed at 2; walk silently at 3.",
	"charisma": "Better prices (5% per rank). Opens persuasion in conversations.",
	"historian": "Opens lore in conversations. (Books, scrolls and identifying come later.)",
}


static func is_attribute(stat: String) -> bool:
	return ATTRIBUTES.has(stat)


## A stat by spend key (attribute, school or civil skill); 0 if unknown.
static func value(e: SimEntity, stat: String) -> int:
	if ATTRIBUTES.has(stat) or CIVIL.has(stat):
		return e.get(stat)
	var school := SCHOOLS.find(stat)
	return e.schools[school] if school >= 0 else 0


static func rank(e: SimEntity, school: int) -> int:
	return e.schools[school] if school >= 0 and school < e.schools.size() else 0


## Sets a stat by spend key. Vitality moves max HP with it (and armour).
static func set_value(e: SimEntity, stat: String, amount: int) -> void:
	if stat == "vitality":
		var delta := (amount - e.vitality) * HP_PER_VITALITY
		e.vitality = amount
		e.max_hp += delta
		if e.is_alive():
			e.hp = clampi(e.hp + maxi(delta, 0), 1, e.max_hp)
		EquipRules.recalculate(e)
	elif ATTRIBUTES.has(stat) or CIVIL.has(stat):
		e.set(stat, amount)
	else:
		var school := SCHOOLS.find(stat)
		if school >= 0:
			e.schools[school] = amount


## The attribute the weapon in hand scales with ("str", "dex", "mind"); fists use strength.
static func weapon_attribute(e: SimEntity) -> int:
	var scales: String = SimItems.info(e.weapon).get("scales", "str") if e.weapon != "" else "str"
	match scales:
		"dex":
			return e.dexterity
		"mind":
			return e.mind
	return e.strength


@warning_ignore("integer_division")
static func weapon_bonus(e: SimEntity) -> int:
	return weapon_attribute(e) / 2


@warning_ignore("integer_division")
static func spell_bonus(e: SimEntity) -> int:
	return e.mind / 2


## A weapon hit by `attacker` on `target`: its attack damage, more from behind.
@warning_ignore("integer_division")
static func hit_damage(attacker: SimEntity, target: SimEntity) -> int:
	var amount := attacker.attack_damage()
	if attacker.dexterity >= 2 and is_behind(attacker, target):
		amount += attacker.dexterity / 2
	return amount


## Whether `attacker` stands outside the target's 120° front cone (a character
## that faces somewhere; props have no back).
static func is_behind(attacker: SimEntity, target: SimEntity) -> bool:
	if not target.takes_turns():
		return false
	return not SimPerception.in_cone(target.facing, attacker.cell.x - target.cell.x, attacker.cell.z - target.cell.z)


@warning_ignore("integer_division")
static func armor_bonus(e: SimEntity) -> int:
	return e.vitality / 4


## Stagger that knocks the entity down.
@warning_ignore("integer_division")
static func stagger_limit(e: SimEntity) -> int:
	return e.stagger_max + e.vitality / 4


## Fire or frost damage after Ward: -1 per 3, at most half the hit.
@warning_ignore("integer_division")
static func ward_reduced(e: SimEntity, amount: int) -> int:
	var cut := e.ward / 3
	return maxi(amount - cut, (amount + 1) / 2) if cut > 0 else amount


@warning_ignore("integer_division")
static func heal_cast_bonus(e: SimEntity) -> int:
	return e.ward / 2


@warning_ignore("integer_division")
static func heal_received_bonus(e: SimEntity) -> int:
	return e.ward / 3


static func shove_limit(e: SimEntity) -> int:
	return SHOVE_BASE + SHOVE_PER_STRENGTH * e.strength


static func teleport_limit(e: SimEntity) -> int:
	return TELEPORT_BASE + TELEPORT_PER_MIND * e.mind


## Movement cost units one AP buys (CombatRules.MOVE_COST_PER_AP = 2 cells, +1 per Dex).
static func move_per_ap(e: SimEntity) -> int:
	return CombatRules.MOVE_COST_PER_AP + e.dexterity


static func carry_limit(e: SimEntity) -> int:
	return CARRY_BASE + CARRY_PER_STRENGTH * e.strength


## Grams carried: the bag and everything worn.
static func carried(e: SimEntity) -> int:
	return SimItems.total_weight(e.inventory) + SimItems.total_weight(EquipRules.all_worn(e))


## Carrying more than the limit: walks like someone slowed. Only characters.
static func is_overloaded(e: SimEntity) -> bool:
	return e.takes_turns() and carried(e) > carry_limit(e)


## Whether a thief of this rank may choose `item` from someone's pockets.
static func can_pick(thief: SimEntity, item: String) -> bool:
	if thief.thievery >= PICK_ANY_RANK:
		return true
	return thief.thievery >= 1 and SimItems.value_of(item) <= PICK_VALUE_PER_RANK * thief.thievery


## The lowest school ranks that let a character use `abilities` (a character
## built with these verbs knows enough to use them).
static func schools_for(abilities: Array[int]) -> PackedInt32Array:
	var ranks := PackedInt32Array()
	ranks.resize(SCHOOLS.size())
	ranks.fill(0)
	for ability in abilities:
		var school: int = SimAbilities.SCHOOL[ability]
		if school >= 0:
			ranks[school] = maxi(ranks[school], SimAbilities.RANK[ability])
	return ranks


## Applies a role's starting stats ({"attributes": {...}, "schools": {...},
## "civil": {...}}). Vitality adds its HP on top of the role's base.
static func apply_preset(e: SimEntity, data: Dictionary) -> void:
	var attributes: Dictionary = data.get("attributes", {})
	for stat: String in attributes:
		set_value(e, stat, attributes[stat])
	var schools: Dictionary = data.get("schools", {})
	for stat: String in schools:
		set_value(e, stat, maxi(schools[stat], value(e, stat)))
	var civil: Dictionary = data.get("civil", {})
	for stat: String in civil:
		set_value(e, stat, civil[stat])
