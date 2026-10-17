class_name WorldSpace
extends RefCounted
## Maps sim cells to world positions. Cell (x, y, z) sits at world
## (x + 0.5, floor, z + 0.5). In a baked level the floor of a terrain column is
## the real terrain height, so characters and effects sit on the ground rather
## than on 1 m steps; elsewhere (and in the arena) it is simply y.

static var _size := Vector2i.ZERO
static var _terrain_height := PackedFloat32Array()
static var _terrain_floor := PackedInt32Array()


## Uses a baked level's terrain columns: heights and the walk layer per column
## (index x + z * width; -1 where there is no terrain).
static func set_terrain(size: Vector2i, heights: PackedFloat32Array, floors: PackedInt32Array) -> void:
	_size = size
	_terrain_height = heights
	_terrain_floor = floors


static func clear() -> void:
	_size = Vector2i.ZERO
	_terrain_height = PackedFloat32Array()
	_terrain_floor = PackedInt32Array()


static func has_terrain() -> bool:
	return _size != Vector2i.ZERO


## Terrain height at a column, or -INF where there is none.
static func terrain_height(x: int, z: int) -> float:
	if not has_terrain() or x < 0 or z < 0 or x >= _size.x or z >= _size.y:
		return -INF
	return _terrain_height[x + z * _size.x]


## Walk layer of a terrain column, or -1.
static func terrain_floor(x: int, z: int) -> int:
	if not has_terrain() or x < 0 or z < 0 or x >= _size.x or z >= _size.y:
		return -1
	return _terrain_floor[x + z * _size.x]


## World height of the floor a cell stands on.
static func floor_y(c: Vector3i) -> float:
	if terrain_floor(c.x, c.z) == c.y:
		return terrain_height(c.x, c.z)
	return float(c.y)


static func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c.x + 0.5, floor_y(c), c.z + 0.5)
