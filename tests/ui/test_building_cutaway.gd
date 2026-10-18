extends GutTest
## Roofs and walls come off a building while one of this player's characters
## is inside, and picking looks past what was cut.

var _level: Node3D
var _building: CSGBox3D
var _roof: CSGBox3D
var _cutaway: BuildingCutaway


## A 6 x 4 x 6 m house on the ground at (10, 0, 10): walls 0.3 m, open
## ceiling, a roof slab on top.
func before_each() -> void:
	_level = Node3D.new()
	add_child_autofree(_level)
	_building = CSGBox3D.new()
	_building.size = Vector3(6, 4, 6)
	_building.position = Vector3(13, 2, 13)
	_level.add_child(_building)
	var inside := CSGBox3D.new()
	inside.name = "Inside"
	inside.operation = CSGShape3D.OPERATION_SUBTRACTION
	inside.size = Vector3(5.4, 4.05, 5.4)
	inside.position = Vector3(0, 0.025, 0)
	_building.add_child(inside)
	_roof = CSGBox3D.new()
	_roof.name = "Roof"
	_roof.size = Vector3(6.6, 0.5, 6.6)
	_roof.position = Vector3(0, 2.25, 0)
	_building.add_child(_roof)
	await wait_physics_frames(2)  # CSG shapes build on a later frame
	_cutaway = BuildingCutaway.new()
	_cutaway.setup(_level)


func test_inside_takes_the_roof_and_walls_off() -> void:
	assert_true(_cutaway.update([Vector3i(13, 0, 13)] as Array[Vector3i]))
	assert_false(_roof.visible)
	assert_true((_building.get_node("Cutaway") as CSGShape3D).visible, "walls cut to stubs")
	assert_true(_cutaway.see_through(Vector3i(10, 3, 13)), "a wall above the stub")
	assert_false(_cutaway.see_through(Vector3i(10, 0, 13)), "the stub itself")
	assert_false(_cutaway.see_through(Vector3i(30, 3, 13)), "elsewhere")


func test_leaving_puts_it_back() -> void:
	_cutaway.update([Vector3i(13, 0, 13)] as Array[Vector3i])
	assert_true(_cutaway.update([Vector3i(20, 0, 13)] as Array[Vector3i]))
	assert_true(_roof.visible)
	assert_false((_building.get_node("Cutaway") as CSGShape3D).visible)
	assert_false(_cutaway.see_through(Vector3i(10, 3, 13)))
	assert_false(_cutaway.update([Vector3i(20, 0, 13)] as Array[Vector3i]), "no change, no work")


func test_standing_on_the_roof_is_not_inside() -> void:
	assert_false(_cutaway.update([Vector3i(13, 5, 13)] as Array[Vector3i]))
	assert_true(_roof.visible)
