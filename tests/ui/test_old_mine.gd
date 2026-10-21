extends GutTest
## The Old Mine dungeon (levels/old_mine): it bakes with its way back up and
## its arrival point, and its two secrets stay secret: the sealed chamber
## behind fallen timbers, and the satchel on a ledge only Teleport or Blink
## reaches.

const MINE := "res://levels/old_mine/old_mine.tscn"

var _state: SimState


func before_all() -> void:
	var level := (load(MINE) as PackedScene).instantiate() as GameLevel
	add_child(level)
	_state = await level.bake(3)
	level.queue_free()


func _named(display_name: String) -> Array[SimEntity]:
	var found: Array[SimEntity] = []
	for e in _state.entities:
		if e.name == display_name:
			found.append(e)
	return found


func _walk(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	return SimPathfinder.find_path(_state, from, to, -1, true, false)


func test_it_knows_its_level_and_ways_in_and_out() -> void:
	assert_eq(_state.level, MINE)
	assert_true(_state.entries.has("start"))
	assert_eq(_state.exits.size(), 1)
	var exit: Dictionary = _state.exits.values()[0]
	assert_eq(exit.level, "res://levels/vertical_slice/vertical_slice.tscn")
	assert_eq(exit.entry, "mine")


func test_the_hall_and_its_thugs_are_reachable() -> void:
	var start: Vector3i = _state.entries.start
	var foreman := _named("Foreman")
	assert_eq(foreman.size(), 1)
	assert_false(_walk(start, foreman[0].cell).is_empty())


func test_the_sealed_chamber_opens_only_past_the_timbers() -> void:
	var start: Vector3i = _state.entries.start
	var cache: SimEntity = _named("Forgotten cache")[0]
	var leak := _walk(start, cache.cell)
	assert_true(leak.is_empty(), "sealed while the timbers stand: %s" % [leak])
	for timber in _named("Fallen timbers"):
		timber.hp = 0  # broken, burnt or teleported away
	assert_false(_walk(start, cache.cell).is_empty(), "open once they're gone")
	for timber in _named("Fallen timbers"):
		timber.hp = timber.max_hp


func test_the_ledge_satchel_is_up_out_of_walking_reach() -> void:
	var satchel: SimEntity = _named("Dusty satchel")[0]
	assert_eq(satchel.cell.y, 5, "three metres up the wall")
	assert_true(_walk(_state.entries.start, satchel.cell).is_empty())
	var below := Vector3i(satchel.cell.x, 2, satchel.cell.z + 6)  # far enough back to see over the lip
	var ledge := satchel.cell + Vector3i(1, 0, 0)
	assert_true(SimPathfinder.is_standable(_state, ledge), "room to land next to it")
	assert_true(SimLos.has_line_of_sight(_state.grid, below, ledge), "Blink can see the ledge from the hall")
