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
##   "slot": "weapon"/"armor", "damage": n, "armor": n   (EquipCommand)
##   "money": true       traders take it at full value (TradeRules)
##   "rest": true        the party can rest with it (RestCommand)

const DEFAULT := {"value": 0, "weight": 1000, "kind": "misc", "blurb": ""}

const ITEMS := {
	"Gold": {"value": 25, "weight": 250, "kind": "valuable", "money": true, "blurb": "A pouch of gold pieces."},
	"Coins": {"value": 8, "weight": 150, "kind": "valuable", "money": true, "blurb": "A handful of copper and silver."},
	"Silver ring": {"value": 40, "weight": 20, "kind": "valuable", "blurb": "Plain, but real silver."},
	"Map": {"value": 15, "weight": 50, "kind": "document", "blurb": "The roads around the village, with a cross near the bandit camp."},
	"Key": {"value": 2, "weight": 30, "kind": "key", "blurb": "A guard's key. To what?"},
	"Camp key": {"value": 5, "weight": 40, "kind": "key", "blurb": "Opens the bandit chief's chest."},
	# Consumables
	"Bread": {"value": 1, "weight": 400, "kind": "food", "heal": 3, "blurb": "Yesterday's loaf. Heals 3."},
	"Healing potion": {"value": 20, "weight": 300, "kind": "potion", "heal": 10, "blurb": "Heals 10."},
	"Cooling salve": {"value": 12, "weight": 150, "kind": "potion", "temperature": -1, "heal": 2,
			"blurb": "Puts out burning (or warms nothing). Heals 2."},
	"Warming draught": {"value": 12, "weight": 250, "kind": "potion", "temperature": 1,
			"blurb": "Thaws the frozen and the cold."},
	"Bedroll": {"value": 10, "weight": 2000, "kind": "misc", "rest": true,
			"blurb": "Rest with it when no enemies are near: the whole party heals."},
	# Weapons (damage) and armour (armor: less physical damage per hit)
	"Greatsword": {"value": 30, "weight": 3500, "kind": "weapon", "slot": "weapon", "damage": 5, "blurb": "Two-handed. 5 damage."},
	"Greataxe": {"value": 30, "weight": 4000, "kind": "weapon", "slot": "weapon", "damage": 6, "blurb": "Heavy. 6 damage."},
	"Daggers": {"value": 18, "weight": 800, "kind": "weapon", "slot": "weapon", "damage": 3, "blurb": "A matched pair. 3 damage."},
	"Knife": {"value": 6, "weight": 300, "kind": "weapon", "slot": "weapon", "damage": 3, "blurb": "Sharp enough. 3 damage."},
	"Staff": {"value": 10, "weight": 1800, "kind": "weapon", "slot": "weapon", "damage": 2, "blurb": "A walking stick, mostly. 2 damage."},
	"Totem": {"value": 12, "weight": 1500, "kind": "weapon", "slot": "weapon", "damage": 2, "blurb": "Carved and painted. 2 damage."},
	"Spear": {"value": 15, "weight": 2200, "kind": "weapon", "slot": "weapon", "damage": 4, "blurb": "Long reach, simple. 4 damage."},
	"Club": {"value": 3, "weight": 1500, "kind": "weapon", "slot": "weapon", "damage": 3, "blurb": "A heavy branch. 3 damage."},
	"Fine sword": {"value": 60, "weight": 1500, "kind": "weapon", "slot": "weapon", "damage": 6, "blurb": "Well balanced. 6 damage."},
	"Leather armour": {"value": 25, "weight": 5000, "kind": "armor", "slot": "armor", "armor": 1, "blurb": "Takes 1 off every physical hit."},
	"Chain shirt": {"value": 70, "weight": 9000, "kind": "armor", "slot": "armor", "armor": 2, "blurb": "Takes 2 off every physical hit."},
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


## "weapon", "armor", or "" if it can't be worn.
static func slot_of(item: String) -> String:
	return info(item).get("slot", "")


## Using it does something (heals, warms, cools).
static func is_usable(item: String) -> bool:
	return amount(item, "heal") > 0 or amount(item, "temperature") != 0


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
