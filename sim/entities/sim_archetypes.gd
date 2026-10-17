class_name SimArchetypes
extends RefCounted
## Character roles: stats, weapon and verbs. Tune roles here; build characters
## with make(). Player roles keep their weapons (Steal can't take them).
##
## Party roles are built to combo: the Tidecaller makes water and ice, the
## Pyromancer makes oil and fire, the Vanguard pushes enemies into the mess, the
## Trickster moves people (and their stuff) where they shouldn't be.

const A := SimAbilities.Ability
## Cells an enemy notices the party from, outside combat (roles can override).
const ENEMY_SIGHT := 6

const ROLES := {
	# --- Party ---
	"vanguard": {
		"title": "Vanguard", "hp": 26, "weapon": "Greatsword", "damage": 5, "mass": 90,
		"abilities": [A.SHOVE, A.CLEAVE],
		"blurb": "Front line. Shoves enemies into hazards and off ledges; Cleave hits everything around it.",
	},
	"pyromancer": {
		"title": "Pyromancer", "hp": 16, "weapon": "Staff", "damage": 2, "mass": 65,
		"abilities": [A.FIREBOLT, A.OIL_FLASK],
		"blurb": "Area damage. Lays oil, then lights it.",
	},
	"trickster": {
		"title": "Trickster", "hp": 18, "weapon": "Daggers", "damage": 3, "mass": 60,
		"abilities": [A.STEAL, A.BLINK, A.TELEPORT],
		"blurb": "Control. Steals weapons, blinks around, teleports enemies into fire or the air.",
	},
	"tidecaller": {
		"title": "Tidecaller", "hp": 18, "weapon": "Staff", "damage": 2, "mass": 65,
		"abilities": [A.RAIN, A.FROST, A.MEND],
		"blurb": "Support. Heals, douses fires, and turns water into ice that trips people up.",
	},
	# --- Enemies ---
	"brute": {
		"title": "Brute", "hp": 26, "weapon": "Greataxe", "damage": 6, "mass": 110,
		"abilities": [A.SHOVE, A.CLEAVE],
	},
	"firecaller": {
		"title": "Firecaller", "hp": 12, "weapon": "Staff", "damage": 2, "mass": 60,
		"abilities": [A.FIREBOLT, A.TELEPORT],
	},
	"skirmisher": {
		"title": "Skirmisher", "hp": 12, "weapon": "Knife", "damage": 3, "mass": 60,
		"abilities": [A.STEAL, A.BLINK],
	},
	"shaman": {
		"title": "Shaman", "hp": 14, "weapon": "Totem", "damage": 2, "mass": 65,
		"abilities": [A.MEND, A.RAIN, A.FROST],
	},
	"pikeman": {
		"title": "Pikeman", "hp": 14, "weapon": "Spear", "damage": 4, "mass": 75,
		"abilities": [A.SHOVE],
	},
	"thug": {
		"title": "Thug", "hp": 12, "weapon": "Club", "damage": 3, "mass": 80,
		"abilities": [],
	},
}


## Builds a character of the given role. Player characters can't be disarmed.
static func make(role: String, p_name: String, faction: SimEntity.Faction, cell: Vector3i, inventory: Array[String] = []) -> SimEntity:
	assert(ROLES.has(role), "Unknown role: %s" % role)
	var data: Dictionary = ROLES[role]
	var abilities: Array[int] = []
	abilities.assign(data.abilities)
	var e := SimEntity.character(p_name, faction, cell, data.hp, data.weapon, data.damage, inventory, abilities)
	e.archetype = role
	e.mass = data.mass
	e.can_be_disarmed = faction != SimEntity.Faction.PLAYERS
	if faction == SimEntity.Faction.ENEMIES:
		e.sight = data.get("sight", ENEMY_SIGHT)
	return e


static func title(role: String) -> String:
	return ROLES[role].title if ROLES.has(role) else ""
