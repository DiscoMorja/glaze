class_name SimArchetypes
extends RefCounted
## Character roles: stats, weapon and verbs. Tune roles here; build characters
## with make(). Player roles keep their weapons (Steal can't take them).
##
## Progression is classless (GDD §5.9): the party roles are starting presets.
## A role's "hp" is its base before Vitality (+3 per point); "attributes",
## "schools" and "civil" are its starting StatRules stats (the party spends
## the creation points: 5 attributes, 2 school ranks, 1 civil); "kit" items
## are added to what it carries.
##
## Party roles are built to combo: the Tidecaller makes water and ice, the
## Pyromancer makes oil and fire, the Vanguard pushes enemies into the mess, the
## Trickster moves people (and their stuff) where they shouldn't be.

const A := SimAbilities.Ability
## Cells an enemy notices the party from, outside combat (roles can override).
const ENEMY_SIGHT := 6
## Townsfolk watch a little less far.
const NEUTRAL_SIGHT := 5
## Stagger that knocks a role down (roles can override with "stagger"). Most
## sources add 1, so it takes three hits in one round: two characters working
## together, or one with help from the environment.
const DEFAULT_STAGGER := 3

const ROLES := {
	# --- Party ---
	"vanguard": {
		"title": "Vanguard", "hp": 20, "weapon": "Greatsword", "damage": 5, "mass": 90, "stagger": 4,
		"abilities": [A.SHOVE, A.CLEAVE, A.SHOCKWAVE],
		"attributes": {"strength": 3, "vitality": 2}, "schools": {"warrior": 2}, "civil": {"charisma": 1},
		"blurb": "Front line. Shoves enemies into hazards and off ledges; Cleave hits everything around it; Shockwave staggers a whole line.",
	},
	"pyromancer": {
		"title": "Pyromancer", "hp": 16, "weapon": "Staff", "damage": 2, "mass": 65,
		"abilities": [A.FIREBOLT, A.KINDLE],
		"attributes": {"mind": 3, "ward": 1, "dexterity": 1}, "schools": {"fire": 2}, "civil": {"historian": 1},
		"kit": ["Oil flask", "Oil flask", "Oil flask"],
		"blurb": "Area damage. Throws oil flasks, then lights them.",
	},
	"trickster": {
		"title": "Trickster", "hp": 18, "weapon": "Daggers", "damage": 3, "mass": 60,
		"abilities": [A.STEAL, A.BLINK, A.TELEPORT, A.LOW_BLOW, A.DISTRACT],
		"attributes": {"dexterity": 3, "mind": 2}, "schools": {"rogue": 1, "psychic": 1}, "civil": {"thievery": 1},
		"kit": ["Lockpick"],
		"blurb": "Control. Steals weapons, blinks around, teleports enemies into fire or the air, and trips people up with a Low Blow.",
	},
	"tidecaller": {
		"title": "Tidecaller", "hp": 18, "weapon": "Staff", "damage": 2, "mass": 65,
		"abilities": [A.RAIN, A.FROST, A.MEND, A.OVERGROWTH],
		"attributes": {"mind": 2, "ward": 3}, "schools": {"ice": 1, "life": 1}, "civil": {"historian": 1},
		"blurb": "Support. Heals, douses fires, and turns water into ice that trips people up.",
	},
	# --- Enemies ---
	"brute": {
		"title": "Brute", "hp": 20, "weapon": "Greataxe", "damage": 6, "mass": 110, "stagger": 5,
		"abilities": [A.SHOVE, A.CLEAVE],
		"attributes": {"strength": 3, "vitality": 2},
	},
	"firecaller": {
		"title": "Firecaller", "hp": 12, "weapon": "Staff", "damage": 2, "mass": 60,
		"abilities": [A.FIREBOLT, A.TELEPORT],
		"attributes": {"mind": 3, "ward": 2},
	},
	"skirmisher": {
		"title": "Skirmisher", "hp": 12, "weapon": "Knife", "damage": 3, "mass": 60,
		"abilities": [A.STEAL, A.BLINK],
		"attributes": {"dexterity": 3, "mind": 2}, "civil": {"thievery": 1},
	},
	"shaman": {
		"title": "Shaman", "hp": 14, "weapon": "Totem", "damage": 2, "mass": 65,
		"abilities": [A.MEND, A.RAIN, A.FROST],
		"attributes": {"mind": 2, "ward": 3},
	},
	"archer": {
		"title": "Archer", "hp": 12, "weapon": "Shortbow", "damage": 3, "mass": 65,
		"abilities": [A.PINNING_SHOT, A.LOADED_SHOT],
		"attributes": {"dexterity": 3, "strength": 1}, "kit": ["Fire arrows", "Fire arrows"],
	},
	"pikeman": {
		"title": "Pikeman", "hp": 8, "weapon": "Spear", "damage": 4, "mass": 75, "stagger": 4,
		"abilities": [A.SHOVE],
		"attributes": {"strength": 3, "vitality": 2},
	},
	# --- Townsfolk (Faction.NEUTRAL until a crime turns them) ---
	"villager": {
		"title": "Villager", "hp": 10, "weapon": "", "damage": 1, "mass": 65,
		"abilities": [],
	},
	"merchant": {
		"title": "Merchant", "hp": 12, "weapon": "", "damage": 1, "mass": 75,
		"abilities": [],
	},
	"guard": {
		"title": "Guard", "hp": 12, "weapon": "Spear", "damage": 4, "mass": 85, "stagger": 4, "sight": 7,
		"abilities": [A.SHOVE],
		"attributes": {"strength": 3, "vitality": 2},
	},
	"thug": {
		"title": "Thug", "hp": 9, "weapon": "Club", "damage": 3, "mass": 80,
		"abilities": [],
		"attributes": {"strength": 2, "vitality": 1},
	},
}


## Builds a character of the given role. Player characters can't be disarmed.
static func make(role: String, p_name: String, faction: SimEntity.Faction, cell: Vector3i, inventory: Array[String] = []) -> SimEntity:
	assert(ROLES.has(role), "Unknown role: %s" % role)
	var data: Dictionary = ROLES[role]
	var abilities: Array[int] = []
	abilities.assign(data.abilities)
	abilities.append(A.HELP_UP)  # everyone can help a fallen ally up
	if faction == SimEntity.Faction.PLAYERS:
		abilities.append(A.REVIVE)  # and the party revives its fallen after a fight
		abilities.append(A.PICKPOCKET)  # and picks pockets outside one
	var carried: Array[String] = inventory.duplicate()
	for item: String in data.get("kit", []):
		carried.append(item)
	var e := SimEntity.character(p_name, faction, cell, data.hp, data.weapon, data.damage, carried, abilities)
	e.archetype = role
	StatRules.apply_preset(e, data)
	e.mass = data.mass
	e.stagger_max = data.get("stagger", DEFAULT_STAGGER)
	e.can_be_disarmed = faction != SimEntity.Faction.PLAYERS
	if faction == SimEntity.Faction.ENEMIES:
		e.sight = data.get("sight", ENEMY_SIGHT)
	elif faction == SimEntity.Faction.NEUTRAL:
		e.sight = data.get("sight", NEUTRAL_SIGHT)
	return e


static func title(role: String) -> String:
	return ROLES[role].title if ROLES.has(role) else ""
