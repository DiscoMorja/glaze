class_name HotbarLayout
extends RefCounted
## What sits in each action-bar slot, per character: PAGES pages of SLOTS
## slots, each empty, an action ("a:<ActionInfo action>") or an item
## ("i:<item name>", used from the character's bag). A player's own UI
## preference, so it lives in the player's user folder, not in the sim or the
## save (keyed by character name).
##
## New actions and new kinds of usable items get a slot the first time a
## character has them (default_spot()): the first page holds Attack and the
## character's school skills from the left and healing potions from the
## right; everything else (Help up, Revive, Pickpocket, other items) starts
## on the second page, so a new character's bar stays short. After that the
## player arranges them (moving one away or clearing it sticks).

const PAGES := 3
const SLOTS := 10
const EMPTY := ""
## Layouts saved before this version are dropped once, so everyone gets the
## current default arrangement.
const VERSION := 2

## Where layouts are kept (tests point it elsewhere).
static var path := "user://hotbars.cfg"
## Character name -> {"pages": Array (PAGES x SLOTS strings), "seen": Array of entries}.
static var _layouts := {}
static var _loaded := false


static func action_entry(action: int) -> String:
	return "a:%d" % action


static func item_entry(item: String) -> String:
	return "i:" + item


static func is_action(entry: String) -> bool:
	return entry.begins_with("a:")


static func is_item(entry: String) -> bool:
	return entry.begins_with("i:")


static func action_of(entry: String) -> int:
	return int(entry.substr(2))


static func item_of(entry: String) -> String:
	return entry.substr(2)


## Items that make sense on the bar: usable ones, and ones to rest with.
static func bar_item(item: String) -> bool:
	return SimItems.is_usable(item) or SimItems.has_property(item, "rest")


## The character's page, after placing anything new it has.
static func page(e: SimEntity, index: int) -> Array:
	return _layout_for(e).pages[index]


static func set_slot(e: SimEntity, page_index: int, slot: int, entry: String) -> void:
	var layout := _layout_for(e)
	if entry != EMPTY:
		# One slot per action or item: placing it again moves it here.
		for p: Array in layout.pages:
			for i in p.size():
				if p[i] == entry:
					p[i] = EMPTY
	layout.pages[page_index][slot] = entry
	if entry != EMPTY and not layout.seen.has(entry):
		layout.seen.append(entry)
	save()


static func swap(e: SimEntity, page_a: int, slot_a: int, page_b: int, slot_b: int) -> void:
	var pages: Array = _layout_for(e).pages
	var a: String = pages[page_a][slot_a]
	pages[page_a][slot_a] = pages[page_b][slot_b]
	pages[page_b][slot_b] = a
	save()


static func _layout_for(e: SimEntity) -> Dictionary:
	_load()
	if not _layouts.has(e.name):
		var pages: Array = []
		for _p in PAGES:
			var slots: Array = []
			slots.resize(SLOTS)
			slots.fill(EMPTY)
			pages.append(slots)
		_layouts[e.name] = {"pages": pages, "seen": [], "v": VERSION}
	var layout: Dictionary = _layouts[e.name]
	var changed := false
	var wanted: Array[String] = []
	for action in ActionInfo.actions_for(e):
		wanted.append(action_entry(action))
	for item in e.inventory:
		if bar_item(item) and not wanted.has(item_entry(item)):
			wanted.append(item_entry(item))
	for entry in wanted:
		if layout.seen.has(entry):
			continue
		layout.seen.append(entry)
		changed = true
		var spot := default_spot(entry)
		var free := _free_on(layout.pages, spot.x, spot.y < 0)
		if free.x < 0:
			free = _first_free(layout.pages)
		if free.x >= 0:
			layout.pages[free.x][free.y] = entry
	if changed:
		save()
	return layout


## Where a new entry goes by default: (page, side), side 1 from the left, -1
## from the right. Fighting actions (Attack, school skills, thrown items) and
## healing potions on the first page; the rest on the second.
static func default_spot(entry: String) -> Vector2i:
	if is_action(entry):
		var action := action_of(entry)
		var fighting: bool = action == ActionInfo.ATTACK or SimAbilities.SCHOOL[action] >= 0 or SimAbilities.FROM_ITEM.has(action)
		return Vector2i(0, 1) if fighting else Vector2i(1, 1)
	var item := item_of(entry)
	var potion := SimItems.kind_of(item) == "potion" and SimItems.amount(item, "heal") > 0 and SimItems.amount(item, "temperature") == 0
	return Vector2i(0, -1) if potion else Vector2i(1, 1)


## The first free slot on a page, from the left or (from_right) the right.
static func _free_on(pages: Array, page_index: int, from_right: bool) -> Vector2i:
	for k in SLOTS:
		var i := SLOTS - 1 - k if from_right else k
		if pages[page_index][i] == EMPTY:
			return Vector2i(page_index, i)
	return Vector2i(-1, -1)


static func _first_free(pages: Array) -> Vector2i:
	for p in pages.size():
		for i in SLOTS:
			if pages[p][i] == EMPTY:
				return Vector2i(p, i)
	return Vector2i(-1, -1)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for name in file.get_section_keys("bars") if file.has_section("bars") else PackedStringArray():
		var data: Variant = file.get_value("bars", name)
		if data is Dictionary and data.get("pages") is Array and data.pages.size() == PAGES and data.get("v", 1) >= VERSION:
			_layouts[name] = data


static func save() -> void:
	var file := ConfigFile.new()
	for name: String in _layouts:
		file.set_value("bars", name, _layouts[name])
	file.save(path)


## Forget everything (tests).
static func reset(p_path: String) -> void:
	path = p_path
	_layouts.clear()
	_loaded = false
