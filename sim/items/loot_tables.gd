class_name LootTables
extends RefCounted
## Random loot: weighted tables of item names, rolled with the sim's own RNG
## (CLAUDE.md rule 5) when a level is baked (GameLevel: a container's or a
## spawn's `loot` table, `loot_rolls` times). Guests get the rolled items in
## the snapshot, so nobody rolls twice.
##
## Each table maps an entry to its weight (integers; higher = likelier).
## An entry is an item name (SimItems), "" for nothing, or "@table" to roll
## once on another table. Tables are read in their written order, so the
## same seed always gives the same loot.
##
## Pacing (GDD §5.8): a new skill about once an hour of play. Tomes are rare
## in random loot (a hidden cache now and then); the levels place the rest
## (a tome-roll in a cache near the start, the Hexer's book).

const NOTHING := ""

const TABLES := {
	# Skill tomes by school rank (SimAbilities.RANK).
	"tomes_rank1": {
		"Kindle tome": 2, "Overgrowth tome": 2, "Drain tome": 2, "Distract tome": 2,
		"Loaded Shot tome": 2, "Pinning Shot tome": 2, "Smoke Bomb tome": 2,
	},
	"tomes_rank2": {
		"Blight tome": 2, "Backstab tome": 2, "Combust tome": 2, "Glacier tome": 2,
		"Wellspring tome": 2, "Shroud tome": 2, "Dread tome": 2, "Brace tome": 2, "Snare tome": 2,
	},
	"tomes": {"@tomes_rank1": 3, "@tomes_rank2": 2},
	# A household's odds and ends (townsfolk crates, baskets, pots).
	"household": {
		NOTHING: 6, "Bread": 4, "Coins": 4, "Healing potion": 1, "Cooling salve": 1,
		"Warming draught": 1, "Oil flask": 1,
	},
	# Bandits' pockets and the camp's crates.
	"bandit": {
		NOTHING: 5, "Coins": 4, "Gold": 1, "Healing potion": 2, "Oil flask": 2,
		"Fire arrows": 1, "Lockpick": 1,
	},
	# Hidden chests out in the wilds: worth the search (a tome in about one
	# roll in 20).
	"cache": {
		"Gold": 6, "Healing potion": 6, "Warming draught": 2, "Cooling salve": 2,
		"Silver ring": 2, "Amber pendant": 2, "@tomes": 1,
	},
}


## Items from `rolls` rolls on `table` (unknown tables give nothing).
static func roll(rng: SimRng, table: String, rolls: int = 1) -> Array[String]:
	var items: Array[String] = []
	for _i in rolls:
		var item := _roll_once(rng, table, 0)
		if item != NOTHING:
			items.append(item)
	return items


static func has_table(table: String) -> bool:
	return TABLES.has(table)


## Every item a table can give, nested tables included (for tests and tools).
static func items_of(table: String) -> Array[String]:
	var result: Array[String] = []
	for entry: String in TABLES.get(table, {}):
		if entry.begins_with("@"):
			for item in items_of(entry.substr(1)):
				if not result.has(item):
					result.append(item)
		elif entry != NOTHING and not result.has(entry):
			result.append(entry)
	return result


static func _roll_once(rng: SimRng, table: String, depth: int) -> String:
	var entries: Dictionary = TABLES.get(table, {})
	var total := 0
	for entry: String in entries:
		total += int(entries[entry])
	if total <= 0 or depth > 4:
		return NOTHING
	var pick := rng.range_int(total)
	for entry: String in entries:
		pick -= int(entries[entry])
		if pick < 0:
			return _roll_once(rng, entry.substr(1), depth + 1) if entry.begins_with("@") else entry
	return NOTHING
