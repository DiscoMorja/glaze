class_name SaveStore
extends RefCounted
## Save files: user://saves/<slot>.save. Each file is a small header (what
## the load lists show, readable without unpacking the world) followed by
## SimState.to_snapshot(), so everything the sim knows is saved and nothing
## else needs to be. Only the host saves; a co-op guest gets the loaded world
## like a join.
##
## Slots: "quick" (F5 / F9), "auto_0".."auto_2" (rotating autosaves), and
## "save_<time>" for saves made in the menu.

## Where saves live (tests point it elsewhere).
static var dir := "user://saves"
const EXTENSION := "save"
const QUICK := "quick"
const AUTO_SLOTS := 3
const MAGIC := "glaze-save"
## Header layout version (the snapshot inside has its own, SimState.SNAPSHOT_VERSION).
const FORMAT := 1

## A save picked in the main menu, loaded once the game scene is ready:
## {"header": Dictionary, "state": SimState}, or empty.
static var pending := {}


## Writes a save. Atomic: written to a temporary file first, so a crash
## mid-save never leaves a broken file in place of a good one.
static func write(slot: String, title: String, state: SimState, level_path: String, playtime: int) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	var header := {
		"format": FORMAT, "sim_version": SimState.SNAPSHOT_VERSION,
		"title": title, "level": level_path, "saved": int(Time.get_unix_time_from_system()),
		"playtime": playtime, "in_combat": state.combat.active, "party": party_summary(state),
	}
	var temp := _path(slot) + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(MAGIC.to_utf8_buffer())
	file.store_var(header)
	file.store_var(state.to_snapshot())
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	return DirAccess.rename_absolute(temp, _path(slot))


## The header of a save (with "slot" added), or empty if it is missing or unreadable.
static func read_header(slot: String) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)):
		return {}
	var file := _open(slot)
	if file == null:
		return {}
	var header: Variant = file.get_var()
	if not header is Dictionary:
		return {}
	header["slot"] = slot
	return header


## {"header", "state"}, or empty if the save is missing, broken, or from a
## newer version of the game.
static func read(slot: String) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)):
		return {}
	var file := _open(slot)
	if file == null:
		return {}
	var header: Variant = file.get_var()
	var bytes: Variant = file.get_var()
	if not header is Dictionary or not bytes is PackedByteArray:
		return {}
	if header.get("format", 0) > FORMAT:
		return {}
	var state := SimState.from_snapshot(bytes)
	if state == null:
		return {}
	header["slot"] = slot
	return {"header": header, "state": state}


## Every readable save's header, newest first.
static func list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return result
	for name in DirAccess.get_files_at(dir):
		if name.get_extension() == EXTENSION:
			var header := read_header(name.get_basename())
			if not header.is_empty():
				result.append(header)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.saved > b.saved)
	return result


static func remove(slot: String) -> void:
	DirAccess.remove_absolute(_path(slot))


## The autosave slot to write next: an empty one, else the oldest.
static func next_auto_slot() -> String:
	var best := "auto_0"
	var best_time := INF
	for i in AUTO_SLOTS:
		var slot := "auto_%d" % i
		var header := read_header(slot)
		if header.is_empty():
			return slot
		if header.saved < best_time:
			best_time = header.saved
			best = slot
	return best


## A fresh slot name for a save made in the menu.
static func new_slot() -> String:
	return "save_%d" % int(Time.get_unix_time_from_system() * 1000.0)


## "Ari 26/26, Bram 16/16, ..." for the load lists.
static func party_summary(state: SimState) -> String:
	var parts: Array[String] = []
	for e in state.entities:
		if e.faction == SimEntity.Faction.PLAYERS and e.takes_turns():
			parts.append("%s %d/%d" % [e.name, e.hp, e.max_hp])
	return ", ".join(parts)


## One line describing a save for a list: title, when, how long played.
static func describe(header: Dictionary) -> String:
	var when := Time.get_datetime_string_from_unix_time(header.get("saved", 0) + _utc_offset_seconds(), true)
	var minutes: int = header.get("playtime", 0) / 60
	return "%s   %s   %dh %02dm%s" % [header.get("title", "?"), when, minutes / 60, minutes % 60,
			"   (in combat)" if header.get("in_combat", false) else ""]


static func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## The save file positioned after its magic bytes, or null if it isn't one.
static func _open(slot: String) -> FileAccess:
	var magic := MAGIC.to_utf8_buffer()
	var file := FileAccess.open(_path(slot), FileAccess.READ)
	if file == null or file.get_length() <= magic.size() or file.get_buffer(magic.size()) != magic:
		return null
	return file


static func _path(slot: String) -> String:
	return "%s/%s.%s" % [dir, slot, EXTENSION]
