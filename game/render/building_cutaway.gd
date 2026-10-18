class_name BuildingCutaway
extends RefCounted
## Takes the roof off buildings this player's characters are inside and cuts
## the walls down to stubs, so the camera sees in, and tells cursor picking to
## look past what was cut. A building is a CSG structure with an "Inside"
## subtraction and a "Roof" child; hiding the roof drops it from the CSG shape,
## and a subtraction box added here cuts the walls. Presentation only: the sim
## grid keeps walls and roof (it was baked at load).

## Wall left standing above the floor while cut away, in metres (cells).
const STUB := 1

## One entry per building: [roof node, interior box, cut height (first cell
## row cut away), footprint box, wall cut node].
var _buildings: Array = []
## Indices into _buildings that are cut away.
var _cut: Array[int] = []


func setup(level: Node) -> void:
	_buildings.clear()
	_cut.clear()
	if level == null:
		return
	for node in level.find_children("Roof", "CSGShape3D", true, false):
		var roof := node as CSGShape3D
		var building := roof.get_parent() as CSGShape3D
		var inside := building.get_node_or_null("Inside") as CSGShape3D if building != null else null
		if inside == null:
			continue
		var interior := inside.global_transform * inside.get_aabb()
		var footprint := (building.global_transform * building.get_aabb()).merge(roof.global_transform * roof.get_aabb())
		var floor_y := roundi(interior.position.y)
		var cut := CSGBox3D.new()
		cut.name = "Cutaway"
		cut.operation = CSGShape3D.OPERATION_SUBTRACTION
		cut.visible = false
		var low := float(floor_y + STUB)
		cut.size = Vector3(footprint.size.x + 1.0, footprint.end.y - low + 1.0, footprint.size.z + 1.0)
		building.add_child(cut)
		cut.global_position = Vector3(footprint.get_center().x, low + cut.size.y / 2.0, footprint.get_center().z)
		_buildings.append([roof, interior, floor_y + STUB, footprint, cut])


## Updates which buildings are cut away for characters standing in `cells`. Returns
## whether that changed.
func update(cells: Array[Vector3i]) -> bool:
	var cut: Array[int] = []
	for i in _buildings.size():
		for c in cells:
			if _inside(i, c):
				cut.append(i)
				break
	if cut == _cut:
		return false
	for i in _buildings.size():
		var roof: CSGShape3D = _buildings[i][0]
		var walls: CSGShape3D = _buildings[i][4]
		if is_instance_valid(roof):
			roof.visible = not cut.has(i)
			walls.visible = cut.has(i)
	_cut = cut
	return true


## Whether a solid cell is in the part of a building that is cut away (roof
## and walls above the stubs): picking looks past it.
func see_through(c: Vector3i) -> bool:
	for i in _cut:
		var footprint: AABB = _buildings[i][3]
		if c.y >= int(_buildings[i][2]) and _column_in(footprint, c):
			return true
	return false


func any_cut() -> bool:
	return not _cut.is_empty()


func _inside(i: int, c: Vector3i) -> bool:
	var interior: AABB = _buildings[i][1]
	return _column_in(interior, c) and c.y >= roundi(interior.position.y) and c.y < roundi(interior.end.y)


static func _column_in(box: AABB, c: Vector3i) -> bool:
	var x := c.x + 0.5
	var z := c.z + 0.5
	return x >= box.position.x and x <= box.end.x and z >= box.position.z and z <= box.end.z
