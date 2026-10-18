class_name SimItems
extends RefCounted
## The item catalog: every item a character can carry, by name (inventories
## hold these names, one slot each). Value is in gold pieces, weight in grams
## (integers, CLAUDE.md rule 4). Unknown names still work, as worthless 1 kg
## oddments, so a typo in a level doesn't break anything.
##
## "kind" groups items for the inventory's look (and later, for verbs that
## care: food, keys, valuables...).

const DEFAULT := {"value": 0, "weight": 1000, "kind": "misc", "blurb": ""}

const ITEMS := {
	"Gold": {"value": 25, "weight": 250, "kind": "valuable", "blurb": "A pouch of gold pieces."},
	"Coins": {"value": 8, "weight": 150, "kind": "valuable", "blurb": "A handful of copper and silver."},
	"Silver ring": {"value": 40, "weight": 20, "kind": "valuable", "blurb": "Plain, but real silver."},
	"Map": {"value": 15, "weight": 50, "kind": "document", "blurb": "The roads around the village, with a cross near the bandit camp."},
	"Bread": {"value": 1, "weight": 400, "kind": "food", "blurb": "Yesterday's loaf."},
	"Key": {"value": 2, "weight": 30, "kind": "key", "blurb": "A guard's key. To what?"},
	"Camp key": {"value": 5, "weight": 40, "kind": "key", "blurb": "Opens the bandit chief's chest."},
}


static func info(item: String) -> Dictionary:
	return ITEMS.get(item, DEFAULT)


static func value_of(item: String) -> int:
	return info(item).value


static func weight_of(item: String) -> int:
	return info(item).weight


static func kind_of(item: String) -> String:
	return info(item).kind


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
