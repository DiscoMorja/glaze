class_name ActionInfo
extends RefCounted
## Names, costs and tooltip text for the actions on a character's action bar.
## An action is ATTACK or a SimAbilities.Ability value.

const NONE := -2
const ATTACK := -1

static func description(action: int) -> String:
	match action:
		ATTACK:
			return "Hit an adjacent target with your weapon."
		SimAbilities.Ability.FIREBOLT:
			return "Deals %d damage and sets the target cell on fire. Lights oil." % SimAbilities.FIREBOLT_DAMAGE
		SimAbilities.Ability.RAIN:
			return "Soaks an area with water. Puts out fire (making steam); can be frozen into ice."
		SimAbilities.Ability.TELEPORT:
			return "Pick something up to %d kg, then put it in any free cell you can see. Try high up, or in the fire." % SimAbilities.TELEPORT_MAX_MASS
		SimAbilities.Ability.SHOVE:
			return "Pushes an adjacent target %d cells. Walls and bodies hurt; ledges drop." % SimAbilities.SHOVE_DISTANCE
		SimAbilities.Ability.STEAL:
			return "Takes an enemy's weapon, or an item if it has none."
		SimAbilities.Ability.FROST:
			return "Chills an area: freezes water into slippery ice, puts out fire, %d damage." % SimAbilities.FROST_DAMAGE
		SimAbilities.Ability.OIL_FLASK:
			return "Splashes oil over an area. Burns well."
		SimAbilities.Ability.MEND:
			return "Heals %d HP. Works on yourself and others." % SimAbilities.MEND_HEAL
		SimAbilities.Ability.CLEAVE:
			return "Hits everything adjacent with your weapon, allies too."
		SimAbilities.Ability.BLINK:
			return "Jump to a free cell you can see."
	return ""


## The selected character's action bar: Attack first, then its abilities.
static func actions_for(e: SimEntity) -> Array[int]:
	var result: Array[int] = [ATTACK]
	result.append_array(e.abilities)
	return result


static func name_of(action: int) -> String:
	return "Attack" if action == ATTACK else SimAbilities.NAMES[action]


static func cost(action: int) -> int:
	return CombatRules.ATTACK_AP if action == ATTACK else SimAbilities.AP_COST[action]


static func range_of(action: int) -> int:
	return 1 if action == ATTACK else SimAbilities.RANGE[action]


static func tooltip(action: int, actor: SimEntity) -> String:
	var reach := range_of(action)
	var range_text := "adjacent" if reach == 1 else "range %d" % reach
	var lines: Array[String] = ["%s — %d AP, %s" % [name_of(action), cost(action), range_text]]
	if action == ATTACK and actor != null:
		lines.append("%d damage with %s." % [actor.attack_damage(), actor.weapon if actor.weapon != "" else "bare hands"])
	else:
		lines.append(description(action))
	if reach > 1:
		lines.append("Needs line of sight.")
	return "\n".join(lines)
