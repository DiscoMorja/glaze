class_name Content
extends RefCounted
## Loads the written content (dialogue and quests, plain text under
## game/data/) into the sim's registries. The sim only sees the text; reading
## files is the game layer's job. Both co-op peers load the same files.

const DIALOGUE_DIR := "res://game/data/dialogue"
const QUEST_DIR := "res://game/data/quests"

static var _loaded := false


## Loads everything once (call again with reload = true after editing files).
static func load_all(reload: bool = false) -> void:
	if _loaded and not reload:
		return
	_loaded = true
	SimDialogue.clear()
	QuestRules.clear()
	for path in _files(DIALOGUE_DIR, "dlg"):
		SimDialogue.register(FileAccess.get_file_as_string(path), path)
	for path in _files(QUEST_DIR, "quest"):
		QuestRules.register(FileAccess.get_file_as_string(path), path)
	for error in SimDialogue.errors + QuestRules.errors:
		push_warning("Content: " + error)


static func _files(dir: String, extension: String) -> Array[String]:
	var result: Array[String] = []
	var names := DirAccess.get_files_at(dir)
	names.sort()
	for name in names:
		if name.get_extension() == extension:
			result.append(dir + "/" + name)
	return result
