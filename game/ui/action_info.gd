class_name ActionInfo
extends RefCounted
## Names, costs and tooltip text for the actions on a character's action bar.
## An action is ATTACK or a SimAbilities.Ability value.

const NONE := -2
const ATTACK := -1

## What the action does, with the actor's own numbers when there is one.
@warning_ignore("integer_division")
static func description(action: int, actor: SimEntity = null) -> String:
	var spell := actor.spell_power() if actor != null else 0
	var potency := SimAbilities.potency(actor, action) if actor != null and action >= 0 else 0
	match action:
		ATTACK:
			return "Hit an adjacent target with your weapon. Physical damage staggers; enough stagger in one round knocks them down."
		SimAbilities.Ability.FIREBOLT:
			return "Deals %d damage, heats the target two levels (thaws Frozen, sets Burning) and sets the cell on fire. Lights oil." % (SimAbilities.FIREBOLT_DAMAGE + spell + potency)
		SimAbilities.Ability.RAIN:
			return "Soaks an area with water. Puts out fire (making steam); can be frozen into ice."
		SimAbilities.Ability.TELEPORT:
			return "Pick something up to %d kg, then put it in any free cell you can see. Try high up, or in the fire." % (StatRules.teleport_limit(actor) if actor != null else StatRules.TELEPORT_BASE)
		SimAbilities.Ability.SHOVE:
			return "Pushes an adjacent target (up to %d kg) %d cells. Walls and bodies hurt; ledges drop." % [StatRules.shove_limit(actor) if actor != null else StatRules.SHOVE_BASE, SimAbilities.SHOVE_DISTANCE + potency / 2]
		SimAbilities.Ability.STEAL:
			return "Takes an enemy's weapon, or an item if it has none."
		SimAbilities.Ability.FROST:
			return "Chills an area one level (Burning to Hot, Normal to Cold; the Cold, e.g. soaked by Rain, freeze solid), freezes water into ice, puts out fire, %d damage." % (SimAbilities.FROST_DAMAGE + spell + potency)
		SimAbilities.Ability.OIL_FLASK:
			return "Throw an oil flask: splashes oil over an area. Burns well. Uses up a flask."
		SimAbilities.Ability.MEND:
			return "Heals %d HP. Works on yourself and others." % (SimAbilities.MEND_HEAL + (StatRules.heal_cast_bonus(actor) if actor != null else 0) + potency)
		SimAbilities.Ability.CLEAVE:
			return "Hits everything adjacent with your weapon, allies too."
		SimAbilities.Ability.BLINK:
			return "Jump to a free cell you can see."
		SimAbilities.Ability.SHOCKWAVE:
			return "Slam the ground: a %d-cell line toward the target, %d stagger to everyone on it (allies too). Walls stop it; it doesn't need sight." % [SimAbilities.SHOCKWAVE_LENGTH, SimAbilities.SHOCKWAVE_STAGGER + potency / 2]
		SimAbilities.Ability.LOW_BLOW:
			return "A dirty trip: %d stagger to someone next to you, enough to knock most down on its own." % SimAbilities.LOW_BLOW_STAGGER
		SimAbilities.Ability.PICKPOCKET:
			if actor != null and actor.thievery > 0:
				return "Outside combat: look through the pockets of someone next to you and take one item (Thievery %d: worth up to %s). Anyone who sees it reacts — sneak (C) and come from behind." % [
					actor.thievery, "anything" if actor.thievery >= StatRules.PICK_ANY_RANK else "%d gold" % (StatRules.PICK_VALUE_PER_RANK * actor.thievery)]
			return "Outside combat: lift the first item of someone next to you. Anyone who sees it reacts — sneak (C) and come from behind."
		SimAbilities.Ability.REVIVE:
			return "After combat: bring an adjacent fallen ally back with %d%% of their HP." % SimAbilities.REVIVE_HP_PERCENT
		SimAbilities.Ability.HELP_UP:
			return "Help an adjacent knocked-down ally to their feet. On their turn, they can act right away."
		SimAbilities.Ability.KINDLE:
			return "Warms someone a level (yourself too). Hot characters get an extra AP at the start of their turn; burning ones keep burning. On a barrel: oil catches fire, water boils into steam."
		SimAbilities.Ability.OVERGROWTH:
			return "Vines spring up over bare ground: walking through them slows. They burn fast and frost kills them."
		SimAbilities.Ability.DRAIN:
			return "Deals %d death damage and heals you by what it took." % (SimAbilities.DRAIN_DAMAGE + spell + potency)
		SimAbilities.Ability.BLIGHT:
			return "Rots an area: water turns to poison (it hurts to stand in), vines wither, and a body bursts into a heavy cloud of poison gas that explodes in fire."
		SimAbilities.Ability.DISTRACT:
			return "The target turns its back to you for %d turns (less with a strong Mind). Steal from it, or stab it in the back." % SimAbilities.DISTRACT_TURNS
		SimAbilities.Ability.BACKSTAB:
			return "A weapon hit on someone next to you: double damage if you're behind them."
		SimAbilities.Ability.LOADED_SHOT:
			return "Shoot your first special arrow (fire, water, oil, frost) with your bow or sling: a hit plus what the arrow carries. Uses the arrow up."
		SimAbilities.Ability.PINNING_SHOT:
			return "A bow or sling hit that pins the target: it can't move on its next turn."
	return ""


## The selected character's action bar: Attack first, then its abilities.
static func actions_for(e: SimEntity) -> Array[int]:
	var result: Array[int] = [ATTACK]
	result.append_array(SimAbilities.available(e))
	return result


static func name_of(action: int) -> String:
	return "Attack" if action == ATTACK else SimAbilities.NAMES[action]


static func cost(action: int) -> int:
	return CombatRules.ATTACK_AP if action == ATTACK else SimAbilities.AP_COST[action]


## Turns until the action can be used again after use (0 = no cooldown).
static func cooldown_of(action: int) -> int:
	return 0 if action == ATTACK else SimAbilities.COOLDOWN[action]


## Turns the actor still has to wait before using the action.
static func remaining(action: int, actor: SimEntity) -> int:
	return 0 if action == ATTACK or actor == null else actor.cooldown(action)


## Reach in cells; with an actor, attacks and shots reach as far as its weapon.
static func range_of(action: int, actor: SimEntity = null) -> int:
	if actor != null and (action == ATTACK or SimAbilities.SHOTS.has(action)):
		return AttackCommand.reach(actor) if action == ATTACK else mini(AttackCommand.reach(actor), SimAbilities.RANGE[action])
	return 1 if action == ATTACK else SimAbilities.RANGE[action]


static func tooltip(action: int, actor: SimEntity) -> String:
	var reach := range_of(action, actor)
	var range_text := "adjacent" if reach == 1 else "range %d" % reach
	var lines: Array[String] = ["%s — %d AP, %s" % [name_of(action), cost(action), range_text]]
	if action == ATTACK and actor != null:
		lines.append("%d damage with %s." % [actor.attack_damage(), actor.weapon if actor.weapon != "" else "bare hands"])
	else:
		lines.append(description(action, actor))
	if action >= 0:
		var school: int = SimAbilities.SCHOOL[action]
		if school >= 0:
			lines.append("%s %d skill." % [StatRules.SCHOOLS[school].capitalize(), SimAbilities.RANK[action]])
		var lack := SimAbilities.lacks(actor, action) if actor != null else ""
		if lack != "":
			lines.append("Can't use: %s." % lack)
	if reach > 1:
		lines.append("Needs line of sight.")
	var cooldown := cooldown_of(action)
	if cooldown > 1:
		lines.append("Cooldown: usable every %d turns." % cooldown)
	elif cooldown == 1:
		lines.append("Cooldown: once per turn.")
	var wait := remaining(action, actor)
	if wait > 0:
		lines.append("Ready in %d turn%s." % [wait, "" if wait == 1 else "s"])
	return "\n".join(lines)
