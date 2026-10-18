extends GutTest
## Baking structures into the grid: thin walls must not leave holes, and a
## door cut through one must stay open.


## A level without terrain holding one 0.3 m wall along z at `x`, 3 m high,
## with a 2 m door cut through it around z = 6.
func _bake_wall(x: float) -> SimState:
	var level := GameLevel.new()
	level.grid_size = Vector3i(12, 5, 12)
	add_child_autofree(level)
	var wall := CSGBox3D.new()
	wall.use_collision = true
	wall.size = Vector3(0.3, 3, 10)
	wall.position = Vector3(x, 1.5, 6)
	level.add_child(wall)
	var door := CSGBox3D.new()
	door.operation = CSGShape3D.OPERATION_SUBTRACTION
	door.size = Vector3(1.4, 2.4, 2.0)
	door.position = Vector3(0, -0.4, 0)
	wall.add_child(door)
	return await level.bake()


func test_thin_walls_between_the_old_sample_lines_are_solid() -> void:
	# 0.3 m walls anywhere in a cell, including between 0.25 and 0.75.
	for x: float in [4.4, 4.5, 4.6, 4.25, 4.85]:
		var state := await _bake_wall(x)
		for z in [2, 3, 8, 9]:
			assert_true(state.grid.is_solid(Vector3i(4, 1, z)), "wall at x %.2f, z %d" % [x, z])


func test_the_door_stays_open() -> void:
	for x: float in [4.4, 4.5, 4.85]:
		var state := await _bake_wall(x)
		assert_false(state.grid.is_solid(Vector3i(4, 0, 6)), "door at x %.2f" % x)
		assert_false(SimPathfinder.find_path(state, Vector3i(1, 0, 6), Vector3i(9, 0, 6)).is_empty(), "walk through the door")
		var around := SimPathfinder.find_path(state, Vector3i(1, 0, 3), Vector3i(9, 0, 3))
		for c in around:
			assert_false(c.x == 4 and (c.z < 5 or c.z > 7), "only through the door, not the wall at %s" % c)
