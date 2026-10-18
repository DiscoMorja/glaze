class_name CharacterLooks
extends RefCounted
## Which model a character uses and which weapon model an item shows, from
## the placeholder packs in assetlibs/ (git-ignored: everything falls back to
## capsules when they are missing). Presentation only; the sim never reads it.
##
## A look names a rig (a model file with its animations) and the meshes of
## it to show. Levels pick looks with LevelSpawn.look; without one,
## default_for() picks by side and role.

const MODULAR_MALE := "res://assetlibs/Characters/modular_rpg_characters/human_male_rigged.glb"
const MODULAR_FEMALE := "res://assetlibs/Characters/modular_rpg_characters/human_female_rigged.glb"
const VILLAGERS := "res://assetlibs/Characters/Villager NPCs/Villager_NPCs_glb.glb"
const KNIGHT := "res://assetlibs/Characters/Knight/Knight.glb"
const WEAPONS := "res://assetlibs/Weapons/FBX/"
const MODULAR_TEXTURES := "res://assetlibs/Characters/modular_rpg_characters/textures/"
const VILLAGER_TEXTURES := "res://assetlibs/Characters/Villager NPCs/Textures/"

## Rigs: model file, the bones weapons go on (and which of their axes a
## held weapon points along), and animation names for each
## state. Modular rigs pick idle/attack animations by weapon style
## (see style_of()); "%s" is the style.
const RIGS := {
	"modular_male": {
		"scene": MODULAR_MALE, "hand_r": "wep_pos_R", "hand_l": "wep_pos_L", "weapon_axis": Vector3.DOWN, "staff_axis": Vector3.LEFT,
		"anims": {
			"idle": "human_male_idle", "run": "human_male_run", "death": "human_male_death",
			"combat_idle": "human_male_idle_combat_%s", "attack": "human_male_cast_%s",
			"cast": "human_male_cast_unarmed_magic", "cast_staff": "human_male_cast_two_handed_staff",
			"drink": "human_male_drink_potion",
		},
	},
	"modular_female": {
		"scene": MODULAR_FEMALE, "hand_r": "wep_pos_R", "hand_l": "wep_pos_L", "weapon_axis": Vector3.DOWN, "staff_axis": Vector3.LEFT,
		"anims": {
			"idle": "human_female_idle", "run": "human_female_run", "death": "human_female_death",
			"combat_idle": "human_female_idle_combat_%s", "attack": "human_female_cast_%s",
			"cast": "human_female_cast_unarmed_magic", "cast_staff": "human_female_cast_two_handed_staff",
			"drink": "human_female_drink_potion",
		},
	},
	"villager": {
		"scene": VILLAGERS, "hand_r": "", "hand_l": "",
		"anims": {"idle": "Idle_1", "run": "Walk_1", "talk": "Talk_1"},
	},
	"knight": {
		"scene": KNIGHT, "hand_r": "Item_In_Hand_R", "hand_l": "Item_In_Hand_L", "weapon_axis": Vector3.BACK,
		"anims": {
			"idle": "Idle_1", "run": "Run", "walk": "Walk", "combat_idle": "Combat_Idle",
			"attack": "Attack_1", "hit": "Hit_front", "death": "Death_1",
		},
	},
}

## Looks: a rig and the meshes to show (all others are hidden).
const LOOKS := {
	# Party
	"ari": {"rig": "modular_male", "meshes": ["human_male_light_armor_3", "human_male_light_boots", "human_male_light_gloves", "human_male_head_2", "human_male_hair_3"]},
	"bram": {"rig": "modular_male", "meshes": ["human_male_light_armor", "human_male_light_boots_2", "human_male_hands_default", "human_male_head_4", "human_male_hair_5"]},
	"cel": {"rig": "modular_female", "meshes": ["human_female_light_armor_4", "human_female_light_boots", "human_female_light_gloves_3", "human_female_head_2", "human_female_hair_2"]},
	"dov": {"rig": "modular_female", "meshes": ["human_female_light_armor_2", "human_female_light_boots_2", "human_female_hands_default", "human_female_head_3", "human_female_hair_1"]},
	# Fighters
	"brute": {"rig": "modular_male", "meshes": ["human_male_medium_armor", "human_male_medium_boots", "human_male_medium_gloves", "human_male_head_5", "human_male_hair_1"]},
	"bandit_m1": {"rig": "modular_male", "meshes": ["human_male_light_armor_2", "human_male_light_boots", "human_male_hands_default", "human_male_head_3", "human_male_hair_2"]},
	"bandit_m2": {"rig": "modular_male", "meshes": ["human_male_light_armor_4", "human_male_feet_default", "human_male_light_gloves_3", "human_male_head_6", "human_male_hair_4"]},
	"bandit_f1": {"rig": "modular_female", "meshes": ["human_female_light_armor_3", "human_female_light_boots", "human_female_hands_default", "human_female_head_1", "human_female_hair_3"]},
	"knight": {"rig": "knight", "meshes": ["Face_1", "Guntlets", "Helmet", "Male", "Shoulder_pads"]},
	# Townsfolk
	"villager_m1": {"rig": "villager", "meshes": ["Male_1"]},
	"villager_m2": {"rig": "villager", "meshes": ["Male_2"]},
	"villager_m3": {"rig": "villager", "meshes": ["Male_3"]},
	"villager_m4": {"rig": "villager", "meshes": ["Male_4"]},
	"villager_f1": {"rig": "villager", "meshes": ["Woman_1"]},
	"villager_f2": {"rig": "villager", "meshes": ["Woman_2"]},
	"villager_f3": {"rig": "villager", "meshes": ["Woman_3"]},
	"villager_f4": {"rig": "villager", "meshes": ["Woman_4"]},
}

## Weapon items -> [model file under WEAPONS, length in metres, grip]. The
## model is scaled to that length along its longest side; grip is where the
## hand holds it, as a fraction of the length from the butt (0 = the very
## end of the handle). Items not listed show nothing.
const WEAPON_MODELS := {
	"Greatsword": ["Long_Sword/Long_Sword_03.fbx", 1.3, 0.1],
	"Fine sword": ["Sabre/Sabre_02.fbx", 0.95, 0.1],
	"Greataxe": ["Axe/Axe_04.fbx", 1.15, 0.25],
	"Daggers": ["Dagger/Dagger_01.fbx", 0.4, 0.15],
	"Knife": ["Dagger/Dagger_05.fbx", 0.35, 0.15],
	"Parrying dagger": ["Dagger/Dagger_03.fbx", 0.45, 0.15],
	"Staff": ["Staff/Staff_02.fbx", 1.7, 0.4],
	"Totem": ["Staff/Staff_06.fbx", 1.3, 0.35],
	"Spear": ["Spear/Spear_01.fbx", 2.0, 0.4],
	"Club": ["Club/Club_02.fbx", 0.8, 0.12],
	"Wooden shield": ["Round_Shield/Round_Shield_01.fbx", 0.55, 0.5],
}
## Held upright like a walking staff (the rig's "staff_axis"), not out in front.
const STAFF_LIKE := ["Staff", "Totem"]
## Items drawn in both hands (a matched pair).
const PAIRED := ["Daggers"]

const _ENEMY_LOOKS := ["bandit_m1", "bandit_m2", "bandit_f1"]
const _VILLAGER_LOOKS := ["villager_m1", "villager_f1", "villager_m2", "villager_f2", "villager_m3", "villager_f3", "villager_m4", "villager_f4"]

static var _scenes := {}
static var _textures := {}


## The texture for a mesh surface whose material lost it on import (the
## .blend packs keep their textures as loose files), or null.
static func texture_for(mesh_name: String, material_name: String) -> Texture2D:
	var path := ""
	if material_name.begins_with("mat_"):
		# mat_human_male_light_armor_3_skirt -> tex_human_male_light_armor_3.png
		path = MODULAR_TEXTURES + "tex_" + material_name.trim_prefix("mat_").trim_suffix("_skirt") + ".png"
	elif mesh_name.begins_with("Male_"):
		path = VILLAGER_TEXTURES + "male_" + mesh_name.trim_prefix("Male_") + ".png"
	elif mesh_name.begins_with("Woman_"):
		path = VILLAGER_TEXTURES + "female_" + mesh_name.trim_prefix("Woman_") + ".png"
	if path == "":
		return null
	# Some male pieces only ship the female texture (same layout).
	if not ResourceLoader.exists(path) and path.contains("tex_human_male_"):
		path = path.replace("tex_human_male_", "tex_human_female_")
	if not _textures.has(path):
		_textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[path]


## The look for an entity without one set: party members by name, guards and
## brutes by role, other fighters and townsfolk varied by id.
static func default_for(e: SimEntity) -> String:
	var by_name := e.name.to_lower()
	if e.faction == SimEntity.Faction.PLAYERS and LOOKS.has(by_name):
		return by_name
	if e.archetype == "guard":
		return "knight"
	if e.archetype == "brute":
		return "brute"
	if e.faction == SimEntity.Faction.NEUTRAL or e.archetype in ["villager", "merchant"]:
		return _VILLAGER_LOOKS[e.id % _VILLAGER_LOOKS.size()]
	if e.faction == SimEntity.Faction.PLAYERS:
		return ["ari", "bram", "cel", "dov"][e.id % 4]
	return _ENEMY_LOOKS[e.id % _ENEMY_LOOKS.size()]


## The look's rig data, or {} if the look or its model file is missing.
static func rig_of(look: String) -> Dictionary:
	if not LOOKS.has(look):
		return {}
	var rig: Dictionary = RIGS[LOOKS[look].rig]
	return rig if ResourceLoader.exists(rig.scene) else {}


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]


static func weapon_scene(item: String) -> PackedScene:
	return scene(WEAPONS + WEAPON_MODELS[item][0]) if WEAPON_MODELS.has(item) else null


static func weapon_length(item: String) -> float:
	return WEAPON_MODELS[item][1] if WEAPON_MODELS.has(item) else 1.0


static func weapon_grip(item: String) -> float:
	return WEAPON_MODELS[item][2] if WEAPON_MODELS.has(item) else 0.1


static func is_shield(item: String) -> bool:
	return SimItems.slot_of(item) == "off_hand" and SimItems.amount(item, "armor") > 0


## Animation style for the modular rigs from what is held:
## two_handed_melee, two_handed_staff, dual_wield_melee, main_hand_melee, unarmed.
static func style_of(main: String, off: String) -> String:
	if main == "":
		return "unarmed"
	if main == "Staff":
		return "two_handed_staff"
	if SimItems.has_property(main, "two_handed"):
		return "two_handed_melee"
	if PAIRED.has(main) or SimItems.slot_of(off) == "off_hand" and SimItems.amount(off, "damage") > 0:
		return "dual_wield_melee"
	return "main_hand_melee"
