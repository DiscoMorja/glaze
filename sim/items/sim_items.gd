class_name SimItems
extends RefCounted
## The item catalog: every item a character can carry, by name (inventories
## hold these names, one slot each). Value is in gold pieces, weight in grams
## (integers, CLAUDE.md rule 4). Unknown names still work, as worthless 1 kg
## oddments, so a typo in a level doesn't break anything.
##
## "kind" groups items for the inventory's look. Verbs read the other
## properties, never the name (CLAUDE.md rule 9):
##   "heal": n           using it restores n HP (UseItemCommand)
##   "temperature": d    using it moves body temperature by d levels
##   "slot": where it is worn (EquipRules: head, neck, body, hands, waist,
##           legs, feet, ring, main_hand, off_hand); "two_handed" weapons
##           fill both hands
##   "damage": n (weapons; worn elsewhere, extra damage), "armor": n,
##   "power": n (weapon and spell damage), "max_hp": n   (EquipRules)
##   "scales": "str" | "dex" | "mind"   the attribute a weapon hits with
##           (StatRules; default str)
##   "money": true       traders take it at full value (TradeCommand)
##   "rest": true        the party can rest with it (RestCommand)
##   "casts": "Ability"  carrying it grants that ability; each use spends one
##                       (SimAbilities.FROM_ITEM)
##   "lockpick": true    picks locks with Thievery (LootCommand)
##   "ranged": n         a weapon that hits at range n with sight (AttackCommand)
##   "ammo": true        what Loaded Shot fires (used up), with "ignite",
##                       "splash": "water" | "oil", "chill": n
##   "teaches": "Ability" reading it (UseItemCommand, outside combat) teaches
##                       that skill if your school rank allows; used up

const DEFAULT := {"value": 0, "weight": 1000, "kind": "misc", "blurb": ""}

const ITEMS := {
	"Gold": {"value": 25, "weight": 250, "kind": "valuable", "money": true, "blurb": "A pouch of gold pieces."},
	"Coins": {"value": 8, "weight": 150, "kind": "valuable", "money": true, "blurb": "A handful of copper and silver."},
	"Map": {"value": 15, "weight": 50, "kind": "document", "blurb": "The roads around the village, with a cross near the bandit camp."},
	"Key": {"value": 2, "weight": 30, "kind": "key", "blurb": "A guard's key. To what?"},
	"Camp key": {"value": 5, "weight": 40, "kind": "key", "blurb": "Opens the bandit chief's chest."},
	# Consumables
	"Bread": {"value": 1, "weight": 400, "kind": "food", "heal": 3, "blurb": "Yesterday's loaf."},
	"Healing potion": {"value": 20, "weight": 300, "kind": "potion", "heal": 10, "blurb": "Red and bitter."},
	"Cooling salve": {"value": 12, "weight": 150, "kind": "potion", "temperature": -1, "heal": 2,
			"blurb": "Cools the skin; puts out burning."},
	"Warming draught": {"value": 12, "weight": 250, "kind": "potion", "temperature": 1,
			"blurb": "Thaws the frozen and the cold."},
	"Oil flask": {"value": 6, "weight": 500, "kind": "potion", "casts": "Oil Flask",
			"blurb": "Lamp oil in a clay flask. Throw it, then light it."},
	"Lockpick": {"value": 15, "weight": 100, "kind": "key", "lockpick": true,
			"blurb": "Bent wire and patience. Opens locks with enough Thievery."},
	# Ammunition for Loaded Shot
	"Fire arrows": {"value": 4, "weight": 100, "kind": "ammo", "ammo": true, "ignite": true, "blurb": "Pitch-soaked heads. Sets the target alight."},
	"Water arrows": {"value": 3, "weight": 150, "kind": "ammo", "ammo": true, "splash": "water", "blurb": "A clay bulb of water bursts where it lands."},
	"Oil arrows": {"value": 4, "weight": 150, "kind": "ammo", "ammo": true, "splash": "oil", "blurb": "A clay bulb of lamp oil bursts where it lands."},
	"Frost arrows": {"value": 5, "weight": 100, "kind": "ammo", "ammo": true, "chill": 1, "blurb": "Rimed heads that steal the warmth from a wound."},
	# Skill tomes (one per learnable skill)
	"Kindle tome": {"value": 30, "weight": 600, "kind": "book", "teaches": "Kindle", "blurb": "Fire 1. Warm a friend into haste, or a barrel into flames."},
	"Overgrowth tome": {"value": 30, "weight": 600, "kind": "book", "teaches": "Overgrowth", "blurb": "Life 1. Raise a tangle of vines that snares and burns."},
	"Drain tome": {"value": 30, "weight": 600, "kind": "book", "teaches": "Drain", "blurb": "Death 1. Take a little of someone's life for your own."},
	"Blight tome": {"value": 50, "weight": 600, "kind": "book", "teaches": "Blight", "blurb": "Death 2. Turn water to poison and the dead to a foul, flammable cloud."},
	"Distract tome": {"value": 30, "weight": 600, "kind": "book", "teaches": "Distract", "blurb": "Psychic 1. Make someone look the other way."},
	"Backstab tome": {"value": 50, "weight": 600, "kind": "book", "teaches": "Backstab", "blurb": "Rogue 2. Twice the hurt from behind."},
	"Loaded Shot tome": {"value": 30, "weight": 600, "kind": "book", "teaches": "Loaded Shot", "blurb": "Ranger 1. Fire special arrows."},
	"Pinning Shot tome": {"value": 30, "weight": 600, "kind": "book", "teaches": "Pinning Shot", "blurb": "Ranger 1. Nail someone's foot to the ground."},
	"Bedroll": {"value": 10, "weight": 2000, "kind": "misc", "rest": true,
			"blurb": "Rest with it when no enemies are near: the whole party heals."},
	# Main hand (two-handed ones leave no room for the off hand)
	"Greatsword": {"value": 30, "weight": 3500, "kind": "weapon", "slot": "main_hand", "two_handed": true, "damage": 5, "scales": "str", "blurb": "Two-handed."},
	"Greataxe": {"value": 30, "weight": 4000, "kind": "weapon", "slot": "main_hand", "two_handed": true, "damage": 6, "scales": "str", "blurb": "Two-handed. Heavy."},
	"Daggers": {"value": 18, "weight": 800, "kind": "weapon", "slot": "main_hand", "damage": 3, "scales": "dex", "blurb": "Quick and quiet."},
	"Knife": {"value": 6, "weight": 300, "kind": "weapon", "slot": "main_hand", "damage": 3, "scales": "dex", "blurb": "Sharp enough."},
	"Staff": {"value": 10, "weight": 1800, "kind": "weapon", "slot": "main_hand", "two_handed": true, "damage": 2, "scales": "mind", "blurb": "Two-handed. A walking stick, mostly."},
	"Totem": {"value": 12, "weight": 1500, "kind": "weapon", "slot": "main_hand", "damage": 2, "scales": "mind", "blurb": "Carved and painted."},
	"Spear": {"value": 15, "weight": 2200, "kind": "weapon", "slot": "main_hand", "two_handed": true, "damage": 4, "scales": "str", "blurb": "Two-handed. Long reach, simple."},
	"Club": {"value": 3, "weight": 1500, "kind": "weapon", "slot": "main_hand", "damage": 3, "scales": "str", "blurb": "A heavy branch."},
	"Shortbow": {"value": 25, "weight": 1000, "kind": "weapon", "slot": "main_hand", "two_handed": true, "damage": 3, "ranged": 7, "scales": "dex", "blurb": "Two-handed. Shoots up to 7 cells; better from high ground."},
	"Sling": {"value": 8, "weight": 200, "kind": "weapon", "slot": "main_hand", "damage": 2, "ranged": 5, "scales": "dex", "blurb": "A strip of leather and a stone. Shoots up to 5 cells."},
	"Fine sword": {"value": 60, "weight": 1500, "kind": "weapon", "slot": "main_hand", "damage": 6, "scales": "str", "blurb": "Well balanced; leaves a hand free."},
	# Off hand
	"Wooden shield": {"value": 14, "weight": 3000, "kind": "armor", "slot": "off_hand", "armor": 1, "blurb": "Round, oak, dented."},
	"Parrying dagger": {"value": 16, "weight": 400, "kind": "weapon", "slot": "off_hand", "damage": 1, "scales": "dex", "blurb": "For the other hand."},
	# Armour and trinkets
	"Leather cap": {"value": 8, "weight": 400, "kind": "armor", "slot": "head", "max_hp": 2, "blurb": "Better than nothing."},
	"Iron helm": {"value": 30, "weight": 2000, "kind": "armor", "slot": "head", "armor": 1, "max_hp": 2, "blurb": "Heavy and loud."},
	"Leather armour": {"value": 25, "weight": 5000, "kind": "armor", "slot": "body", "armor": 1, "blurb": "Boiled leather."},
	"Chain shirt": {"value": 70, "weight": 9000, "kind": "armor", "slot": "body", "armor": 2, "blurb": "Rings of iron."},
	"Brawler's gloves": {"value": 18, "weight": 300, "kind": "armor", "slot": "hands", "damage": 1, "blurb": "Studded knuckles."},
	"Leather leggings": {"value": 12, "weight": 1200, "kind": "armor", "slot": "legs", "max_hp": 3, "blurb": "Patched at the knees."},
	"Leather boots": {"value": 10, "weight": 900, "kind": "armor", "slot": "feet", "max_hp": 2, "blurb": "Good for long roads."},
	"Belt": {"value": 6, "weight": 300, "kind": "armor", "slot": "waist", "max_hp": 2, "blurb": "Keeps everything where it should be."},
	"Bone amulet": {"value": 22, "weight": 60, "kind": "trinket", "slot": "neck", "power": 1, "blurb": "Something old hums in it."},
	"Amber pendant": {"value": 35, "weight": 40, "kind": "trinket", "slot": "neck", "max_hp": 4, "blurb": "Warm to the touch."},
	"Silver ring": {"value": 40, "weight": 20, "kind": "trinket", "slot": "ring", "power": 1, "blurb": "Plain, but real silver."},
	"Copper ring": {"value": 10, "weight": 15, "kind": "trinket", "slot": "ring", "max_hp": 2, "blurb": "Turns your finger green."},
}


static func info(item: String) -> Dictionary:
	return ITEMS.get(item, DEFAULT)


static func value_of(item: String) -> int:
	return info(item).value


static func weight_of(item: String) -> int:
	return info(item).weight


static func kind_of(item: String) -> String:
	return info(item).kind


## A numeric property (0 if the item doesn't have it).
static func amount(item: String, property: String) -> int:
	return int(info(item).get(property, 0))


static func has_property(item: String, property: String) -> bool:
	return info(item).has(property)


## Its EquipRules slot kind, or "" if it can't be worn.
static func slot_of(item: String) -> String:
	return info(item).get("slot", "")


## Using it does something (heals, warms, cools, teaches).
static func is_usable(item: String) -> bool:
	return amount(item, "heal") > 0 or amount(item, "temperature") != 0 or has_property(item, "teaches")


## The ability a tome teaches (-1 = none).
static func teaches(item: String) -> int:
	return SimAbilities.NAMES.find(info(item).get("teaches", ""))


## Total value (gold) and weight (grams) of an inventory.
static func total_value(items: Array[String]) -> int:
	var total := 0
	for item in items:
		total += value_of(item)
	return total


static func total_weight(items: Array[String]) -> int:
	var total := 0
	for item in items:
		total += weight_of(item)
	return total


## "1.25 kg", "50 g".
static func weight_text(grams: int) -> String:
	if grams < 1000:
		return "%d g" % grams
	return ("%.2f" % (grams / 1000.0)).rstrip("0").rstrip(".") + " kg"
