class_name EventSounds
extends Node3D
## Turns sim events into sounds (CLAUDE.md rule 6: the sim never knows). Uses
## the same timing as VfxPlayer: after a thrown spell or an arrow the impact
## sounds wait PROJECTILE_SECONDS, so they land with the effect. Weapon sounds
## follow the weapon's properties (what it scales with, its weight, ranged),
## voices follow who it is (voice_of()), never names.

## Seconds between footsteps along a combat move (two cells per step).
const STEP_EVERY_CELLS := 2

const A := SimAbilities.Ability
## Ability -> cue played at the caster as it casts ("" = none).
const CAST_CUES := {
	A.FIREBOLT: "fire_cast", A.COMBUST: "fire_cast", A.KINDLE: "ignite",
	A.FROST: "frost_cast", A.GLACIER: "frost_nova",
	A.TELEPORT: "dodge", A.BLINK: "dodge", A.SHOVE: "shove", A.LOW_BLOW: "punch",
	A.CLEAVE: "heavy_swing", A.SHOCKWAVE: "slam", A.BRACE: "brace",
	A.STEAL: "pickup_valuable", A.PICKPOCKET: "pickup_valuable",
	A.MEND: "heal", A.WELLSPRING: "heal", A.REVIVE: "revive", A.OVERGROWTH: "magic",
	A.DRAIN: "toxic", A.DREAD: "toxic", A.DISTRACT: "magic",
	A.BLIGHT: "gas", A.SHROUD: "gas", A.SNARE: "search",
}
## Ability -> cue played where it lands (after a projectile's flight).
const LAND_CUES := {
	A.OIL_FLASK: "glass", A.SMOKE_BOMB: "glass", A.RAIN: "gas",
	A.FROST: "freeze", A.GLACIER: "freeze",
}

var sfx: SfxPlayer


func _ready() -> void:
	sfx = SfxPlayer.new()
	add_child(sfx)


## Which voice set an entity speaks with: "party", "folk" (townsfolk),
## "sneak" (light fighters with finesse weapons) or "brute".
static func voice_of(e: SimEntity) -> String:
	match e.faction:
		SimEntity.Faction.PLAYERS:
			return "party"
		SimEntity.Faction.NEUTRAL, SimEntity.Faction.NONE:
			return "folk"
	return "sneak" if SimItems.info(e.weapon).get("scales", "str") == "dex" else "brute"


## The swing and hit cues of an attacker's weapon: [swing, hit].
static func weapon_cues(e: SimEntity) -> Array[String]:
	if e == null or e.weapon == "":
		return ["blade_swing", "punch"]
	var info := SimItems.info(e.weapon)
	if info.has("ranged"):
		return ["", "arrow_hit"]
	match info.get("scales", "str"):
		"dex":
			return ["blade_swing", "blade_hit"]
		"mind":
			return ["staff_swing", "staff_hit"]
	if SimItems.weight_of(e.weapon) >= 1500:
		return ["heavy_swing", "heavy_hit"]
	return ["blade_swing", "blade_hit"]  # (a ternary of two literals is untyped: keep these plain returns)


func play(state: SimState, events: Array[SimEvent]) -> void:
	var delay := 0.0
	var once := {}  # cues played once per batch (fire spreading, steam)
	var hurt := {}  # one pained voice per entity per batch
	var last_cast := -1
	for e in events:
		var who := state.get_entity(e.entity_id)
		var other := state.get_entity(e.other_id) if e.other_id >= 0 else null
		match e.type:
			SimEvent.Type.CAST:
				last_cast = e.amount
				if who != null:
					sfx.play(CAST_CUES.get(e.amount, ""), _body(who.cell), delay)
				if VfxPlayer.ABILITY_PROJECTILES.has(e.amount) and who != null:
					delay += VfxPlayer.PROJECTILE_SECONDS
				if LAND_CUES.has(e.amount):
					sfx.play(LAND_CUES[e.amount], _body(e.cell), delay)
			SimEvent.Type.ATTACKED:
				if other != null:
					var cues := weapon_cues(other)
					if cues[0] != "":
						sfx.play(cues[0], _body(other.cell), delay)
					if randi() % 3 == 0:
						sfx.play(voice_of(other) + "_attack", _body(other.cell), delay, -4.0)
					var ranged := SimItems.has_property(other.weapon, "ranged") and not SimAbilities.is_adjacent(other.cell, e.cell)
					if ranged and not SimAbilities.SHOTS.has(last_cast):
						delay += VfxPlayer.PROJECTILE_SECONDS  # the arrow flies first
			SimEvent.Type.DAMAGED:
				if who == null:
					continue
				if e.element == EntityOps.Element.PHYSICAL and other != null:
					var hit := "backstab" if last_cast == A.BACKSTAB else weapon_cues(other)[1]
					sfx.play(hit, _body(e.cell), delay)
				elif e.element == EntityOps.Element.FROST:
					sfx.play("freeze", _body(e.cell), delay)
				if who.is_alive() and who.takes_turns() and not hurt.has(who.id):
					hurt[who.id] = true
					sfx.play(voice_of(who) + "_hurt", _body(e.cell), delay + 0.05, -2.0)
			SimEvent.Type.DIED:
				if who != null and who.takes_turns():
					sfx.play(voice_of(who) + "_death", _body(e.cell), delay)
				elif who != null:
					sfx.play("glass" if who.contents_amount > 0 or who.contents_surface != SimMaterials.Surface.NONE else "punch", _body(e.cell), delay)
			SimEvent.Type.COMBAT_STARTED:
				for f in state.entities:
					if f.in_combat and f.is_alive() and f.faction == SimEntity.Faction.ENEMIES:
						sfx.play(voice_of(f) + "_aggro", _body(f.cell), delay)
						break
			SimEvent.Type.IGNITED:
				_once(once, "ignite", e.cell, delay, -6.0)
			SimEvent.Type.EXTINGUISHED:
				_once(once, "gas", e.cell, delay, -8.0)
			SimEvent.Type.FROZE, SimEvent.Type.FROZEN:
				_once(once, "freeze", e.cell, delay)
			SimEvent.Type.EXPLODED, SimEvent.Type.SNARED:
				sfx.play("slam", _body(e.cell), delay)
			SimEvent.Type.COMBUSTED:
				if not e.cells.is_empty():
					sfx.play("slam", _body(e.cell), delay)
			SimEvent.Type.SLIPPED:
				sfx.play("slip", _body(e.cell), delay)
			SimEvent.Type.FELL:
				if e.amount > 1:
					sfx.play("land", _body(e.cell), delay)
			SimEvent.Type.KNOCKED_DOWN:
				sfx.play("fall_down", _body(e.cell), delay)
			SimEvent.Type.COLLIDED:
				sfx.play("punch", _body(e.cell), delay)
			SimEvent.Type.BRACED:
				if other != null:
					sfx.play("block", _body(e.cell), delay)  # a shove that didn't move it
			SimEvent.Type.SPILLED:
				sfx.play("glass", _body(e.cell), delay)
			SimEvent.Type.REVIVED, SimEvent.Type.STOOD_UP:
				if e.type == SimEvent.Type.REVIVED:
					sfx.play("revive", _body(e.cell), delay)
			SimEvent.Type.ITEM_USED:
				if SimItems.amount(e.text, "heal") > 0 or SimItems.amount(e.text, "temperature") != 0:
					sfx.play("drink", _body(e.cell), delay)
			SimEvent.Type.LOOTED, SimEvent.Type.GIVEN, SimEvent.Type.STOLEN, SimEvent.Type.PICKPOCKETED:
				sfx.play(_pickup_cue(e.text), _body(e.cell), delay)
			SimEvent.Type.UNLOCKED:
				sfx.play("chest_open", _body(e.cell), delay)
			SimEvent.Type.EQUIPPED:
				sfx.play_ui(_equip_cue(e.text))
			SimEvent.Type.TRADED:
				sfx.play_ui("coins")
			SimEvent.Type.RESTED:
				sfx.play_ui("ignite")
			SimEvent.Type.LEVELED_UP:
				_once_ui(once, "level_up")
			SimEvent.Type.LEARNED:
				sfx.play_ui("learned")
			SimEvent.Type.QUEST_STARTED, SimEvent.Type.QUEST_ENDED:
				_once_ui(once, "quest")
			SimEvent.Type.MOVED:
				_steps(state, who, e.cells, delay)


## Footsteps along a walk: every cell in real time (one per tick), every
## STEP_EVERY_CELLS cells along a combat move, timed with the walk.
func _steps(state: SimState, who: SimEntity, cells: Array[Vector3i], delay: float) -> void:
	if who == null or not who.is_alive() or not who.takes_turns() or not FogOfWar.shows(state, who):
		return
	var cue := "step_heavy" if who.mass >= 85 else "step"
	if cells.size() <= 1:
		sfx.play(cue, _feet(who.cell), delay, -8.0)
		return
	for i in range(0, cells.size(), STEP_EVERY_CELLS):
		sfx.play(cue, _feet(cells[i]), delay + i * SimEntityRenderer.MOVE_SECONDS_PER_CELL, -8.0)


func _once(once: Dictionary, cue: String, c: Vector3i, delay: float, volume_db: float = 0.0) -> void:
	if not once.has(cue):
		once[cue] = true
		sfx.play(cue, _body(c), delay, volume_db)


func _once_ui(once: Dictionary, cue: String) -> void:
	if not once.has(cue):
		once[cue] = true
		sfx.play_ui(cue)


static func _pickup_cue(item: String) -> String:
	match SimItems.kind_of(item):
		"weapon":
			return "pickup_weapon"
		"armor":
			return "pickup_armor"
		"valuable", "trinket":
			return "pickup_valuable"
	return "pickup_item"


static func _equip_cue(item: String) -> String:
	match SimItems.kind_of(item):
		"weapon":
			return "equip_weapon"
		"trinket":
			return "equip_jewel"
	return "equip_armor"


static func _body(c: Vector3i) -> Vector3:
	return WorldSpace.cell_to_world(c) + Vector3(0, 0.8, 0)


static func _feet(c: Vector3i) -> Vector3:
	return WorldSpace.cell_to_world(c)
