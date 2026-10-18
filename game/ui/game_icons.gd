class_name GameIcons
extends RefCounted
## Icon textures for actions and items (game/ui/icons/*.svg, hand-made, edit
## them freely). Files are named after the action or item: "Oil Flask" ->
## ability_oil_flask.svg, "Healing potion" -> item_healing_potion.svg. Missing
## icons return null; callers draw a text fallback.

const DIR := "res://game/ui/icons"
const PORTRAIT := DIR + "/portrait.svg"
## Portrait backdrop per role (until there is portrait art).
const ROLE_COLORS := {
	"vanguard": Color(0.55, 0.22, 0.2),
	"pyromancer": Color(0.62, 0.36, 0.12),
	"trickster": Color(0.38, 0.24, 0.55),
	"tidecaller": Color(0.16, 0.42, 0.5),
}

static var _cache := {}


static func for_action(action: int) -> Texture2D:
	return _load("ability_" + _file_name(ActionInfo.name_of(action)))


static func for_item(item: String) -> Texture2D:
	return _load("item_" + _file_name(item))


static func portrait() -> Texture2D:
	return _load("portrait")


static func role_color(role: String) -> Color:
	return ROLE_COLORS.get(role, Color(0.3, 0.32, 0.36))


## "Oil Flask" -> "oil_flask".
static func _file_name(display: String) -> String:
	return display.to_lower().replace(" ", "_").replace("'", "")


static func _load(file: String) -> Texture2D:
	if not _cache.has(file):
		var path := "%s/%s.svg" % [DIR, file]
		_cache[file] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _cache[file]
