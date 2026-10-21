class_name SoundBank
extends RefCounted
## Sound cues by meaning ("blade_hit", "fire_cast"...), each a few file
## variants in game/audio/ played at random so repeats don't sound canned.
## Files are named without extension: the .wav is used, else the .mp3. Missing
## files are skipped (a cue with none plays nothing), so the game works with
## or without the audio folder. Tune cues here; EventSounds says when they
## play, MusicDirector picks the music.

const DIR := "res://game/audio/"
const MUSIC_DIR := "res://game/audio/music/"

## Audio buses (made at start if the project has no layout for them) and
## their volume in dB.
const BUSES := {"Music": -9.0, "SFX": -3.0}

const CUES := {
	# Weapons: swing, then the hit, by what the weapon scales with (StatRules).
	"heavy_swing": ["hammer_swing-01", "hammer_swing-02", "hammer_swing-03", "hammer_swing-04", "hammer_swing-05", "hammer_swing-06"],
	"heavy_hit": ["hammer_impact_metal-01", "hammer_impact_metal-02", "hammer_impact_metal-03", "hammer_impact_metal-04", "hammer_impact_metal-05", "hammer_impact_metal-06"],
	"blade_swing": ["swing-01", "swing-02", "swing-03", "swing-04", "swing-05", "swing-06"],
	"blade_hit": ["sword_stab-01", "sword_stab-02", "sword_stab-03", "sword_stab-04"],
	"backstab": ["WEAPKnif_DAGGER-Finisher_B00M_MMDS", "sword_weakspot-01", "sword_weakspot-02", "sword_weakspot-03"],
	"staff_swing": ["staff_swing-01", "staff_swing-02", "staff_swing-03", "staff_swing-04", "staff_swing-05", "staff_swing-06"],
	"staff_hit": ["staff_hit-01", "staff_hit-02", "staff_hit-03", "staff_hit-04", "staff_hit-05", "staff_hit-06"],
	"arrow_hit": ["bolt_hit-01", "bolt_hit-02", "bolt_hit-03", "bolt_hit-04", "bolt_hit-05", "bolt_hit-06"],
	"punch": ["hammer_hit-01", "hammer_hit-02", "hammer_hit-03", "hammer_hit-04"],
	"block": ["sword_block_-01", "sword_block_-02", "sword_block_-03", "block-01", "block-02"],
	"brace": ["julia_defence"],
	# Bodies and the world.
	"slam": ["impact_hammer_large-01", "impact_hammer_large-02", "impact_hammer_large-03", "impact_hammer_large-04", "impact_hammer_large-05"],
	"shove": ["push_-01", "push_-02", "push_-03", "push_-04", "push_-05", "push_-06"],
	"dodge": ["dodge_-01", "dodge_-02", "dodge_-03", "player_dodge-01", "player_dodge-02"],
	"land": ["jump_land-01", "jump_land-02", "jump_land-03", "land_01"],
	"slip": ["ice_slip-01", "ice_slip-02", "ice_slip-03"],
	"fall_down": ["ice_slip_land (1)", "ice_slip_land (2)", "ice_slip_land (3)"],
	"glass": ["glass_break-01", "glass_break-02", "glass_break-03", "glass_break-04", "glass_break-05"],
	"step": ["foosteps2-01", "foosteps2-02", "foosteps2-03", "foosteps2-04", "foosteps2-05", "foosteps2-06", "foosteps2-07", "foosteps2-08"],
	"step_heavy": ["footsteps-boots-101657", "footsteps-boots-101657-2", "footsteps-boots-101657-3", "footsteps-boots-101657-4", "footsteps-boots-101657-5", "footsteps-boots-101657-6"],
	# Magic and materials.
	"fire_cast": ["bonfire_lit"],
	"ignite": ["bonfire_lit"],
	"fire_loop": ["fire_loop"],
	"frost_cast": ["frostbolt_cast"],
	"frost_nova": ["frost_nova"],
	"freeze": ["freeze"],
	"gas": ["gas"],
	"toxic": ["elin_toxic_tank"],
	"heal": ["revive_finished"],
	"revive": ["revive_finished"],
	"drink": ["drink_health_potion", "drink_health_potion_2", "bottle_open"],
	"magic": ["loot_spawn"],
	# Items, loot, progression.
	"chest_open": ["open_chest"],
	"chest_close": ["close_chest"],
	"search": ["searching-01", "searching-02", "searching-03", "searching-04", "searching-05"],
	"search_done": ["search_done-01", "search_done-02", "search_done-03", "search_done-04"],
	"pickup_valuable": ["item_pickup_valuable"],
	"pickup_weapon": ["item_pickup_weapon"],
	"pickup_armor": ["item_pickup_armor"],
	"pickup_item": ["item_pickup_consumable"],
	"equip_weapon": ["item_place_weapon"],
	"equip_armor": ["item_place_armor"],
	"equip_jewel": ["item_place_jewel"],
	"coins": ["item_place_valuable"],
	"level_up": ["loot_drop_legendary"],
	"learned": ["loot_land_legendary"],
	"quest": ["loot_spawn"],
	# Voices, by voice set (EventSounds.voice_of()).
	"party_hurt": ["player_hit-01", "player_hit-02", "player_hit-03", "player_hit-04", "player_hit-05", "player_hit-06"],
	"party_death": ["player_generic_hit"],
	"party_attack": ["smartsound_HUMAN_VOCAL_Male_Attack_Aggressive_Scream_01", "smartsound_HUMAN_VOCAL_Male_Attack_Aggressive_Scream_02", "smartsound_HUMAN_VOCAL_Male_Attack_Aggressive_Scream_03"],
	"brute_aggro": ["orc_aggro-01", "orc_aggro-02", "orc_aggro-03"],
	"brute_attack": ["orc_attack-01", "orc_attack-02", "orc_attack-03", "orc_attack-04"],
	"brute_hurt": ["orc_hit-01", "orc_hit-02", "orc_hit-03", "orc_hit-04", "brut_hurt-01", "brut_hurt-02", "brut_hurt-03"],
	"brute_death": ["orc_death-01", "orc_death-02", "orc_death-03", "orc_death-04"],
	"sneak_aggro": ["goblin_aggro-01", "goblin_aggro-02", "goblin_aggro-03", "goblin_aggro-04"],
	"sneak_attack": ["goblin_attack-01", "goblin_attack-02", "goblin_attack-03", "goblin_attack-04", "goblin_attack-05", "goblin_attack-06"],
	"sneak_hurt": ["goblin_hit-01", "goblin_hit-02", "goblin_hit-03", "goblin_hit-04", "goblin_hit-05"],
	"sneak_death": ["goblin_death-01", "goblin_death-02", "goblin_death-03", "goblin_death-04", "goblin_death-05"],
	"folk_hurt": ["bruthurt-01", "bruthurt-02", "bruthurt-03"],
	"folk_death": ["zombie_death (1)", "zombie_death (2)"],
}

## Music by mood: tracks played in turn, crossfading (MusicDirector).
const MUSIC := {
	"menu": ["main_theme"],
	"hub": ["hub_1", "hub_2", "hub_3", "hub_4", "Moonlit Maproom"],
	"wilds": ["ambience_1", "ambience_2", "ambience_3", "ambience_4"],
	"dungeon": ["Dungeon Whispers", "Moonlit Archive Halls"],
	"combat": ["combat_1", "combat_2", "combat_3", "combat_4"],
	"big_fight": ["epic_fight_1", "Last Stand Overture"],
	"victory": ["victory_1"],
}

static var _paths := {}


## A random variant of a cue (null if it has none on disk).
static func stream(cue: String) -> AudioStream:
	var paths := paths_of(cue)
	if paths.is_empty():
		return null
	return load(paths[randi() % paths.size()]) as AudioStream


## The cue's variants that exist on disk.
static func paths_of(cue: String) -> Array[String]:
	if not _paths.has(cue):
		var found: Array[String] = []
		for name: String in CUES.get(cue, []):
			var path := resolve(DIR + name)
			if path != "":
				found.append(path)
		_paths[cue] = found
	return _paths[cue]


## The tracks of a mood that exist on disk.
static func music_of(mood: String) -> Array[String]:
	var found: Array[String] = []
	for name: String in MUSIC.get(mood, []):
		var path := resolve(MUSIC_DIR + name)
		if path != "":
			found.append(path)
	return found


## `base` with the first extension that exists ("" if none).
static func resolve(base: String) -> String:
	for ext in [".ogg", ".wav", ".mp3"]:
		if ResourceLoader.exists(base + ext):
			return base + ext
	return ""


## Makes the BUSES (once per run) unless the project's layout has them.
static func ensure_buses() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
			AudioServer.set_bus_volume_db(index, BUSES[bus])
