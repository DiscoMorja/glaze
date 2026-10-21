class_name SimEntity
extends RefCounted
## Anything that occupies a cell: characters, barrels, crates. Verbs act on its
## properties (mass, hp, contents, inventory), never on what kind of thing it is
## (CLAUDE.md rule 9).

## NEUTRAL: townsfolk who don't fight unless a crime turns them (CrimeRules).
enum Faction { NONE, PLAYERS, ENEMIES, NEUTRAL }

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
## What is worn in every slot but the main hand (that's `weapon`): slot ->
## item name (EquipRules). The gear_* stats and armour are worked out from it
## (EquipRules.recalculate()); armour takes that much off each physical hit
## (EntityOps.damage(), at most half of it).
var worn := {}
var armor := 0
var gear_damage := 0
var gear_power := 0
var gear_hp := 0
## Gold pieces carried (TradeCommand).
var gold := 0
## Townsfolk who buy and sell (TradeCommand).
var trader := false
## Progression (ProgressionRules): experience, level and unspent points:
## attribute points, combat (school) points and civil points.
var xp := 0
var level := 1
var points := 0
var combat_points := 0
var civil_points := 0
## Attributes, school ranks (by StatRules.School) and civil skills (StatRules).
var strength := 0
var vitality := 0
var dexterity := 0
var mind := 0
var ward := 0
var schools := PackedInt32Array()
var thievery := 0
var charisma := 0
var historian := 0
var inventory: Array[String] = []
## SimAbilities.Ability values this entity can use.
var abilities: Array[int] = []
## Turns left until each ability (by SimAbilities.Ability value) is ready again.
var cooldowns := PackedInt32Array()
## Cells still to walk in real time (exploration), one per tick.
var travel: Array[Vector3i] = []
## Turns left of being slowed (walking through oil): moving costs double AP in
## combat and walking takes twice as long in real time.
var slowed := 0
## Turns left pinned (Pinning Shot): it can't move in combat, this turn and the next.
var pinned := 0
## Turns left distracted (Distract): it keeps looking where it was turned.
var distracted := 0
## Turns left in dread (Dread): on its turn it only runs from dread_from.
var dread := 0
var dread_from := Vector3i.ZERO
## Turns left braced (Brace): extra armour, and it can't be shoved.
var braced := 0
## A corpse that Blight already burst into gas.
var blighted := false
## Body temperature level: -2 Frozen, -1 Cold, 0 Normal, 1 Hot, 2 Burning
## (EntityOps.change_temperature()). At an extreme, temp_turns counts the
## turns it lasts before easing to Cold or Hot.
var temperature := 0
var temp_turns := 0
## Stagger built up since this entity's last turn start; reaching
## stagger_max knocks it down.
var stagger := 0
var stagger_max := 3
## Knocked down: the turn ended and the next one is skipped, unless an ally
## helps it up. It stays down through the skipped turn (knocked_skipping) and
## gets up at that turn's end.
var knocked_down := false
var knocked_skipping := false
## How far (cells) this entity notices opponents outside combat; 0 = never.
var sight := 0
## Facing (SimPerception.FACINGS index): its vision cone points this way.
## Idle NPCs look around home_facing.
var facing := 4
var home_facing := 4
## Sneaking (party, outside combat): half walking speed, harder to see.
var sneaking := false
## A neutral NPC that saw a petty crime: the next one turns its group hostile.
var suspicious := false
## Items in the inventory that were stolen, tagged "pack:item" (CrimeRules).
var stolen: Array[String] = []
## Name of the group this entity belongs to (the level's pack name, e.g.
## "Bandits", "Village"), for facts like alive.Bandits.
var group := ""
## The dialogue knot talking to it starts at ("" = nothing to say).
var dialogue := ""
## Containers: the item that unlocks it ("" = no key), and how hard it is
## to pick (0 = can't be picked). See LootCommand.
var lock := ""
var lock_level := 0
## What it looks like ("chest", or "" for the default capsule/cylinder);
## presentation only, rules never read it.
var model := ""
## Player slot that controls this entity in co-op (0 = host, 1 = guest), or -1
## for entities no player controls.
var owner := -1
## Entities sharing a pack (> 0) join fights together; 0 = on its own.
var pack := 0
## Taking part in the current fight. Outside combat it marks an entity that
## was hurt (or hurt someone) and joins the fight that this starts.
var in_combat := false


func _init() -> void:
	cooldowns.resize(SimAbilities.NAMES.size())
	cooldowns.fill(0)
	schools.resize(StatRules.SCHOOLS.size())
	schools.fill(0)


func cooldown(ability: int) -> int:
	return cooldowns[ability]


## Counts every cooldown down by one turn.
func tick_cooldowns() -> void:
	for i in cooldowns.size():
		if cooldowns[i] > 0:
			cooldowns[i] -= 1


## Counts timed statuses down by one turn.
func tick_statuses() -> void:
	if slowed > 0:
		slowed -= 1
	if pinned > 0:
		pinned -= 1
	if distracted > 0:
		distracted -= 1
	if dread > 0:
		dread -= 1
	if braced > 0:
		braced -= 1


func is_burning() -> bool:
	return temperature >= EntityOps.TEMP_MAX


func is_frozen() -> bool:
	return temperature <= EntityOps.TEMP_MIN


## Moving costs double: slowed by oil, Cold, or carrying too much.
func is_slowed() -> bool:
	return slowed > 0 or temperature == EntityOps.TEMP_MIN + 1 or StatRules.is_overloaded(self)


func is_alive() -> bool:
	return hp > 0


func takes_turns() -> bool:
	return max_ap > 0


## A weapon hit's damage (from the front): weapon, gear, and the attribute
## the weapon scales with. StatRules.hit_damage() adds hits from behind.
func attack_damage() -> int:
	return (weapon_damage if weapon != "" else unarmed_damage) + gear_damage + gear_power + StatRules.weapon_bonus(self)


## Bonus damage for spells: Mind and gear.
func spell_power() -> int:
	return gear_power + StatRules.spell_bonus(self)


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "archetype": archetype, "cell": cell, "faction": faction,
		"hp": hp, "max_hp": max_hp, "ap": ap, "max_ap": max_ap, "mass": mass,
		"contents_surface": contents_surface, "contents_amount": contents_amount,
		"weapon": weapon, "can_be_disarmed": can_be_disarmed, "weapon_damage": weapon_damage, "unarmed_damage": unarmed_damage,
		"worn": worn.duplicate(), "armor": armor, "gear_damage": gear_damage, "gear_power": gear_power, "gear_hp": gear_hp,
		"gold": gold, "trader": trader,
		"xp": xp, "level": level, "points": points, "combat_points": combat_points, "civil_points": civil_points,
		"strength": strength, "vitality": vitality, "dexterity": dexterity, "mind": mind, "ward": ward,
		"schools": schools.duplicate(), "thievery": thievery, "charisma": charisma, "historian": historian,
		"inventory": inventory.duplicate(),
		"abilities": abilities.duplicate(),
		"cooldowns": cooldowns.duplicate(),
		"travel": travel.duplicate(),
		"sight": sight,
		"facing": facing,
		"home_facing": home_facing,
		"sneaking": sneaking,
		"suspicious": suspicious,
		"stolen": stolen.duplicate(),
		"group": group,
		"dialogue": dialogue,
		"lock": lock,
		"lock_level": lock_level,
		"model": model,
		"slowed": slowed,
		"pinned": pinned,
		"distracted": distracted,
		"dread": dread,
		"dread_from": dread_from,
		"braced": braced,
		"blighted": blighted,
		"temperature": temperature,
		"temp_turns": temp_turns,
		"stagger": stagger,
		"stagger_max": stagger_max,
		"knocked_down": knocked_down,
		"knocked_skipping": knocked_skipping,
		"pack": pack,
		"owner": owner,
		"in_combat": in_combat,
	}


static func from_dict(data: Dictionary) -> SimEntity:
	var e := SimEntity.new()
	e.id = data.get("id", e.id)
	e.name = data.get("name", e.name)
	e.archetype = data.get("archetype", e.archetype)
	e.cell = data.get("cell", e.cell)
	e.faction = data.get("faction", e.faction)
	e.hp = data.get("hp", e.hp)
	e.max_hp = data.get("max_hp", e.max_hp)
	e.ap = data.get("ap", e.ap)
	e.max_ap = data.get("max_ap", e.max_ap)
	e.mass = data.get("mass", e.mass)
	e.contents_surface = data.get("contents_surface", e.contents_surface)
	e.contents_amount = data.get("contents_amount", e.contents_amount)
	e.weapon = data.get("weapon", e.weapon)
	e.can_be_disarmed = data.get("can_be_disarmed", e.can_be_disarmed)
	e.weapon_damage = data.get("weapon_damage", e.weapon_damage)
	e.unarmed_damage = data.get("unarmed_damage", e.unarmed_damage)
	e.worn = data.get("worn", {}).duplicate()
	if data.get("armor_item", "") != "":
		e.worn["body"] = data.armor_item  # one armour slot, before the paperdoll
	e.armor = data.get("armor", e.armor)
	e.gear_damage = data.get("gear_damage", e.gear_damage)
	e.gear_power = data.get("gear_power", e.gear_power)
	e.gear_hp = data.get("gear_hp", e.gear_hp)
	e.gold = data.get("gold", e.gold)
	e.trader = data.get("trader", e.trader)
	e.xp = data.get("xp", e.xp)
	e.level = data.get("level", e.level)
	e.points = data.get("points", e.points)
	e.combat_points = data.get("combat_points", e.combat_points)
	e.civil_points = data.get("civil_points", e.civil_points)
	e.strength = data.get("strength", e.strength)
	e.vitality = data.get("vitality", e.vitality)
	e.dexterity = data.get("dexterity", e.dexterity)
	e.mind = data.get("mind", e.mind)
	e.ward = data.get("ward", e.ward)
	e.schools = PackedInt32Array(data.get("schools", e.schools))
	e.schools.resize(StatRules.SCHOOLS.size())
	e.thievery = data.get("thievery", e.thievery)
	e.charisma = data.get("charisma", e.charisma)
	e.historian = data.get("historian", e.historian)
	e.inventory.assign(data.get("inventory", []))
	e.abilities.assign(data.get("abilities", []))
	e.cooldowns = PackedInt32Array(data.get("cooldowns", e.cooldowns))
	e.cooldowns.resize(SimAbilities.NAMES.size())  # older saves know fewer abilities
	e.travel.assign(data.get("travel", []))
	e.sight = data.get("sight", e.sight)
	e.facing = data.get("facing", e.facing)
	e.home_facing = data.get("home_facing", e.home_facing)
	e.sneaking = data.get("sneaking", e.sneaking)
	e.suspicious = data.get("suspicious", e.suspicious)
	e.stolen.assign(data.get("stolen", []))
	e.group = data.get("group", e.group)
	e.dialogue = data.get("dialogue", e.dialogue)
	e.lock = data.get("lock", e.lock)
	e.lock_level = data.get("lock_level", e.lock_level)
	e.model = data.get("model", e.model)
	e.slowed = data.get("slowed", e.slowed)
	e.pinned = data.get("pinned", e.pinned)
	e.distracted = data.get("distracted", e.distracted)
	e.dread = data.get("dread", e.dread)
	e.dread_from = data.get("dread_from", e.dread_from)
	e.braced = data.get("braced", e.braced)
	e.blighted = data.get("blighted", e.blighted)
	e.temperature = data.get("temperature", e.temperature)
	e.temp_turns = data.get("temp_turns", e.temp_turns)
	e.stagger = data.get("stagger", e.stagger)
	e.stagger_max = data.get("stagger_max", e.stagger_max)
	e.knocked_down = data.get("knocked_down", e.knocked_down)
	e.knocked_skipping = data.get("knocked_skipping", e.knocked_skipping)
	e.pack = data.get("pack", e.pack)
	e.owner = data.get("owner", e.owner)
	e.in_combat = data.get("in_combat", e.in_combat)
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
	e.schools = StatRules.schools_for(e.abilities)  # knows enough to use its verbs
	return e


## A breakable container that spills its contents when destroyed.
## A sturdy chest (or crate, box...) holding items, maybe locked.
static func container(p_name: String, p_cell: Vector3i, p_items: Array[String], p_lock: String = "", p_hp: int = 8) -> SimEntity:
	var e := SimEntity.new()
	e.name = p_name
	e.cell = p_cell
	e.hp = p_hp
	e.max_hp = p_hp
	e.mass = 80
	e.inventory.assign(p_items)
	e.lock = p_lock
	e.model = "chest"
	return e


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
