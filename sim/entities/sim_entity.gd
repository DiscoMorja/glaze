class_name SimEntity
extends RefCounted
## Anything that occupies a cell: characters, barrels, crates. Verbs act on its
## properties (mass, hp, contents, inventory), never on what kind of thing it is
## (CLAUDE.md rule 9).

enum Faction { NONE, PLAYERS, ENEMIES }

var id: int = 0
var name: String = ""
## Role this entity was built from (SimArchetypes id), for display.
var archetype: String = ""
var cell: Vector3i
var faction: Faction = Faction.NONE
var hp: int = 1
var max_hp: int = 1
var ap: int = 0
## AP gained per turn. 0 means the entity never takes turns (props).
var max_ap: int = 0
## Kilograms. Limits what can be teleported or shoved.
var mass: int = 70
## Surface spilled around the entity when it is destroyed.
var contents_surface: int = SimMaterials.Surface.NONE
var contents_amount: int = 0
var weapon: String = ""
## Whether Steal can take the weapon. Player characters keep theirs.
var can_be_disarmed := true
var weapon_damage: int = 0
var unarmed_damage: int = 1
var inventory: Array[String] = []
## SimAbilities.Ability values this entity can use.
var abilities: Array[int] = []
## Turns left until each ability (by SimAbilities.Ability value) is ready again.
var cooldowns := PackedInt32Array()
## Cells still to walk in real time (exploration), one per tick.
var travel: Array[Vector3i] = []
## How far (cells) this entity notices opponents outside combat; 0 = never.
var sight := 0


func _init() -> void:
	cooldowns.resize(SimAbilities.NAMES.size())
	cooldowns.fill(0)


func cooldown(ability: int) -> int:
	return cooldowns[ability]


## Counts every cooldown down by one turn.
func tick_cooldowns() -> void:
	for i in cooldowns.size():
		if cooldowns[i] > 0:
			cooldowns[i] -= 1


func is_alive() -> bool:
	return hp > 0


func takes_turns() -> bool:
	return max_ap > 0


func attack_damage() -> int:
	return weapon_damage if weapon != "" else unarmed_damage


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "archetype": archetype, "cell": cell, "faction": faction,
		"hp": hp, "max_hp": max_hp, "ap": ap, "max_ap": max_ap, "mass": mass,
		"contents_surface": contents_surface, "contents_amount": contents_amount,
		"weapon": weapon, "can_be_disarmed": can_be_disarmed, "weapon_damage": weapon_damage, "unarmed_damage": unarmed_damage,
		"inventory": inventory.duplicate(),
		"abilities": abilities.duplicate(),
		"cooldowns": cooldowns.duplicate(),
		"travel": travel.duplicate(),
		"sight": sight,
	}


static func from_dict(data: Dictionary) -> SimEntity:
	var e := SimEntity.new()
	e.id = data.id
	e.name = data.name
	e.archetype = data.archetype
	e.cell = data.cell
	e.faction = data.faction
	e.hp = data.hp
	e.max_hp = data.max_hp
	e.ap = data.ap
	e.max_ap = data.max_ap
	e.mass = data.mass
	e.contents_surface = data.contents_surface
	e.contents_amount = data.contents_amount
	e.weapon = data.weapon
	e.can_be_disarmed = data.can_be_disarmed
	e.weapon_damage = data.weapon_damage
	e.unarmed_damage = data.unarmed_damage
	e.inventory.assign(data.inventory)
	e.abilities.assign(data.abilities)
	e.cooldowns = PackedInt32Array(data.cooldowns)
	e.travel.assign(data.travel)
	e.sight = data.sight
	return e


func duplicate_entity() -> SimEntity:
	return SimEntity.from_dict(to_dict())


## A turn-taking character.
static func character(
		p_name: String, p_faction: Faction, p_cell: Vector3i, p_hp: int,
		p_weapon: String = "", p_weapon_damage: int = 0, p_inventory: Array[String] = [],
		p_abilities: Array[int] = []) -> SimEntity:
	var e := SimEntity.new()
	e.name = p_name
	e.faction = p_faction
	e.cell = p_cell
	e.hp = p_hp
	e.max_hp = p_hp
	e.max_ap = 4
	e.weapon = p_weapon
	e.weapon_damage = p_weapon_damage
	e.inventory.assign(p_inventory)
	e.abilities.assign(p_abilities)
	return e


## A breakable container that spills its contents when destroyed.
static func barrel(p_name: String, p_cell: Vector3i, p_surface: int, p_amount: int) -> SimEntity:
	var e := SimEntity.new()
	e.name = p_name
	e.cell = p_cell
	e.hp = 3
	e.max_hp = 3
	e.mass = 60
	e.contents_surface = p_surface
	e.contents_amount = p_amount
	return e
