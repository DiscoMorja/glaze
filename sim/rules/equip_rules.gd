class_name EquipRules
extends RefCounted
## What characters wear: eleven slots, filled with items whose "slot"
## property fits (SimItems). The main hand is the entity's `weapon` (so Steal
## and the AI keep working as before); the rest live in `worn`. Gear adds up
## into a few stats (recalculate()): armour, extra damage, power, max HP.
##
## Item "slot" values: head, neck, body, hands, waist, legs, feet, ring (either
## ring slot), main_hand, off_hand. A "two_handed" main-hand weapon leaves no
## room for an off-hand item: wearing one takes the other off.

const SLOTS: Array[String] = ["head", "neck", "body", "hands", "waist", "legs", "feet", "ring1", "ring2", "main_hand", "off_hand"]
const SLOT_NAMES := {
	"head": "Head", "neck": "Neck", "body": "Body", "hands": "Hands", "waist": "Waist",
	"legs": "Legs", "feet": "Feet", "ring1": "Ring", "ring2": "Ring",
	"main_hand": "Main hand", "off_hand": "Off hand",
}
const MAIN := "main_hand"
const OFF := "off_hand"


## Whether `item` can go in `slot`.
static func fits(slot: String, item: String) -> bool:
	var kind := SimItems.slot_of(item)
	if kind == "":
		return false
	if kind == "ring":
		return slot == "ring1" or slot == "ring2"
	return kind == slot


## Where wearing `item` puts it by default: its slot, or for rings the first
## free ring slot. "" if it can't be worn.
static func default_slot(e: SimEntity, item: String) -> String:
	var kind := SimItems.slot_of(item)
	if kind == "ring":
		return "ring2" if worn(e, "ring1") != "" and worn(e, "ring2") == "" else "ring1"
	return kind if SLOTS.has(kind) else ""


static func worn(e: SimEntity, slot: String) -> String:
	return e.weapon if slot == MAIN else e.worn.get(slot, "")


## Everything worn, main hand included.
static func all_worn(e: SimEntity) -> Array[String]:
	var result: Array[String] = []
	for slot in SLOTS:
		var item := worn(e, slot)
		if item != "":
			result.append(item)
	return result


## Wears `item` in `slot` ("" takes it off). Returns what came off (old item,
## and an off-hand or two-handed weapon in the way), for the bag.
static func put(e: SimEntity, slot: String, item: String) -> Array[String]:
	var removed: Array[String] = []
	var old := worn(e, slot)
	if old != "":
		removed.append(old)
	if item != "" and slot == MAIN and SimItems.has_property(item, "two_handed") and worn(e, OFF) != "":
		removed.append(worn(e, OFF))
		_wear_in(e, OFF, "")
	if item != "" and slot == OFF and SimItems.has_property(e.weapon, "two_handed"):
		removed.append(e.weapon)
		_wear_in(e, MAIN, "")
	_wear_in(e, slot, item)
	recalculate(e)
	return removed


## Takes everything off (a fallen enemy drops it all). Returns it.
static func strip(e: SimEntity) -> Array[String]:
	var items := all_worn(e)
	e.weapon = ""
	e.weapon_damage = 0
	e.worn.clear()
	recalculate(e)
	return items


static func _wear_in(e: SimEntity, slot: String, item: String) -> void:
	if slot == MAIN:
		e.weapon = item
		e.weapon_damage = SimItems.amount(item, "damage")
	elif item == "":
		e.worn.erase(slot)
	else:
		e.worn[slot] = item


## Gear stats from what is worn: armour, extra damage (off hand, gloves...),
## power and max HP. A change in max HP moves current HP with it (never
## below 1 for the living).
static func recalculate(e: SimEntity) -> void:
	var armor := 0
	var damage := 0
	var power := 0
	var hp := 0
	for slot in SLOTS:
		var item := worn(e, slot)
		if item == "":
			continue
		armor += SimItems.amount(item, "armor")
		power += SimItems.amount(item, "power")
		hp += SimItems.amount(item, "max_hp")
		if slot != MAIN:
			damage += SimItems.amount(item, "damage")
	e.armor = armor + StatRules.armor_bonus(e)
	e.gear_damage = damage
	e.gear_power = power
	var delta := hp - e.gear_hp
	e.gear_hp = hp
	if delta != 0:
		e.max_hp += delta
		if e.is_alive():
			e.hp = clampi(e.hp + maxi(delta, 0), 1, e.max_hp)
		else:
			e.hp = mini(e.hp, e.max_hp)
