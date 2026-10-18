extends GutTest
## Saves must survive the game changing: old snapshots keep loading (missing
## fields take defaults, older versions migrate), newer or broken ones are
## refused instead of crashing, and save files round-trip.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const TEST_DIR := "user://test_saves"

var _real_dir := ""


func before_each() -> void:
	_real_dir = SaveStore.dir
	SaveStore.dir = TEST_DIR
	_clear_test_dir()


func after_each() -> void:
	_clear_test_dir()
	SaveStore.dir = _real_dir


func _clear_test_dir() -> void:
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for name in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute(TEST_DIR + "/" + name)


## Packs snapshot data the way to_snapshot() does.
func _pack(data: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes(data)
	return var_to_bytes([raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD)])


func _unpack(bytes: PackedByteArray) -> Dictionary:
	var packed: Array = bytes_to_var(bytes)
	return bytes_to_var((packed[1] as PackedByteArray).decompress(packed[0], FileAccess.COMPRESSION_ZSTD))


## Writes a save with a hand-edited header (e.g. to fake its time).
func _rewrite(slot: String, header: Dictionary, state: SimState) -> void:
	header.erase("slot")
	var file := FileAccess.open("%s/%s.save" % [TEST_DIR, slot], FileAccess.WRITE)
	file.store_buffer(SaveStore.MAGIC.to_utf8_buffer())
	file.store_var(header)
	file.store_var(state.to_snapshot())
	file.close()


func test_every_fixture_still_loads() -> void:
	# One fixture per snapshot version (tools/make_snapshot_fixture.gd). If
	# this fails, a change broke old saves: add defaults or a migration step.
	var names := DirAccess.get_files_at("res://tests/fixtures")
	var count := 0
	for name in names:
		if name.begins_with("snapshot_v") and name.ends_with(".bin"):
			count += 1
			var state := SimState.from_snapshot(FileAccess.get_file_as_bytes("res://tests/fixtures/" + name))
			assert_not_null(state, name)
			if state == null:
				continue
			var hero := Fixtures.hero(state)
			assert_eq(hero.hp, 20, name)
			assert_eq(hero.cell, Vector3i(2, 1, 2), name)
			assert_eq(hero.owner, 1, name)
			assert_true(hero.inventory.has("Silver ring"), name)
			assert_eq(state.facts.get("bandits_known", 0), 1, name)
			assert_true(state.quests.bandits.known, name)
			assert_gt(state.grid.fire_cells.size(), 0, name)
			assert_true(state.combat.active, name)
			# And it keeps running.
			state.step_ticks(2)
	assert_gt(count, 0, "there is at least the version-1 fixture")


func test_fields_missing_from_old_snapshots_take_defaults() -> void:
	var state := Fixtures.duel_state()
	var data := _unpack(state.to_snapshot())
	for d: Dictionary in data.entities:
		d.erase("knocked_down")
		d.erase("dialogue")
		d.erase("stolen")
	data.erase("facts")
	data.erase("conversation")
	var copy := SimState.from_snapshot(_pack(data))
	assert_not_null(copy)
	assert_false(Fixtures.hero(copy).knocked_down)
	assert_eq(Fixtures.hero(copy).dialogue, "")
	assert_eq(copy.facts, {})
	assert_eq(copy.conversation, {})


func test_snapshots_from_a_newer_version_are_refused() -> void:
	var data := _unpack(Fixtures.duel_state().to_snapshot())
	data.version = SimState.SNAPSHOT_VERSION + 1
	assert_null(SimState.from_snapshot(_pack(data)))


func test_garbage_is_refused() -> void:
	assert_null(SimState.from_snapshot(PackedByteArray([1, 2, 3, 4])))
	assert_engine_error_count(1, "the engine reports the bad bytes")
	assert_null(SimState.from_snapshot(var_to_bytes("hello")))


func test_save_files_round_trip() -> void:
	var state := Fixtures.duel_state()
	state.facts["x"] = 3
	assert_eq(SaveStore.write("slot_a", "My save", state, "res://levels/arena/arena.tscn", 125), OK)
	var data := SaveStore.read("slot_a")
	assert_false(data.is_empty())
	assert_eq(data.state.checksum(), state.checksum())
	assert_eq(data.header.title, "My save")
	assert_eq(data.header.level, "res://levels/arena/arena.tscn")
	assert_eq(data.header.playtime, 125)
	assert_eq(data.header.slot, "slot_a")
	assert_false(FileAccess.file_exists(TEST_DIR + "/slot_a.save.tmp"), "the temporary file is gone")


func test_list_is_newest_first_and_skips_broken_files() -> void:
	var state := Fixtures.duel_state()
	SaveStore.write("one", "One", state, "", 0)
	SaveStore.write("two", "Two", state, "", 0)
	# Same second: make "one" older by hand.
	var old := SaveStore.read("one")
	old.header.saved -= 100
	_rewrite("one", old.header, state)
	var broken := FileAccess.open(TEST_DIR + "/broken.save", FileAccess.WRITE)
	broken.store_string("not a save")
	broken.close()
	var titles := SaveStore.list().map(func(h: Dictionary) -> String: return h.title)
	assert_eq(titles, ["Two", "One"])
	assert_true(SaveStore.read("broken").is_empty())
	assert_true(SaveStore.read("missing").is_empty())


func test_autosaves_rotate_through_their_slots() -> void:
	var state := Fixtures.duel_state()
	var used := []
	for i in SaveStore.AUTO_SLOTS:
		var slot := SaveStore.next_auto_slot()
		used.append(slot)
		SaveStore.write(slot, "Autosave", state, "", 0)
	assert_eq(used, ["auto_0", "auto_1", "auto_2"])
	# All full: the oldest is next.
	var newer := SaveStore.read("auto_0")
	newer.header.saved += 100
	_rewrite("auto_0", newer.header, state)
	assert_ne(SaveStore.next_auto_slot(), "auto_0")
