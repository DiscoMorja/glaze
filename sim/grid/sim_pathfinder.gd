class_name SimPathfinder
extends RefCounted
## Deterministic A* over standable cells. Units walk in 8 directions and can
## step up or down one level orthogonally. The search prefers to avoid hazards,
## but AP is charged on movement_cost(), which ignores hazard penalties.

const COST_STRAIGHT := 10
const COST_DIAGONAL := 14
const COST_STEP := 4
const HAZARD_FIRE := 30
const HAZARD_ICE := 10

const DIRS_8 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1),
]

## A goal whose walkable surroundings run out within this many cells (a tower
## top, a roof, a walled-off spot) is a pocket: find_path checks it first, so
## unreachable pockets are rejected without searching the whole level.
const POCKET_LIMIT := 128
const STRUCTURE_POCKET_LIMIT := 1500

const _INDEX_BITS := 24
const _INDEX_MASK := (1 << 24) - 1


## Highest rise (or drop) between neighbouring floors a unit can walk, in cm:
## one-level steps on structures (stairs, platforms: 100) pass. Between two
## terrain floors the limit is lower, so steep (rocky) slopes are cliffs.
const MAX_CLIMB_CM := 110
const MAX_SLOPE_CM := 70

## A cell a unit can stand in: open, on solid ground, not taken by another living entity.
static func is_standable(state: SimState, c: Vector3i, mover_id: int = -1) -> bool:
	return _standable(state.grid, occupancy(state), c, mover_id)


static func neighbors(state: SimState, c: Vector3i, mover_id: int = -1) -> Array[Vector3i]:
	return _neighbors(state.grid, occupancy(state), c, mover_id)


## Cell -> id of the living entity standing there. Searches build it once
## instead of scanning every entity for every cell they look at.
static func occupancy(state: SimState) -> Dictionary:
	var result := {}
	for e in state.entities:
		if e.is_alive() and not result.has(e.cell):
			result[e.cell] = e.id
	return result


static func _standable(grid: SimGrid, occupied: Dictionary, c: Vector3i, mover_id: int) -> bool:
	if not grid.in_bounds(c) or grid.is_solid(c) or not grid.is_supported(c):
		return false
	var occupant: int = occupied.get(c, -1)
	return occupant == -1 or occupant == mover_id


## Whether the floors of two neighbouring cells are close enough in height to
## walk between (the same both ways, which the pocket check relies on).
static func _climbable(grid: SimGrid, a: Vector3i, b: Vector3i) -> bool:
	var limit := MAX_SLOPE_CM if grid.is_terrain_floor(a) and grid.is_terrain_floor(b) else MAX_CLIMB_CM
	return absi(grid.floor_cm(a) - grid.floor_cm(b)) <= limit


static func _neighbors(grid: SimGrid, occupied: Dictionary, c: Vector3i, mover_id: int) -> Array[Vector3i]:
	# The hot loop of every search: direct array reads instead of the grid's
	# helper calls (same rules as _standable / _climbable).
	var result: Array[Vector3i] = []
	var solid := grid.solid
	var sx := grid.size.x
	var sy := grid.size.y
	var sz := grid.size.z
	var layer := sx * sz
	var floors := grid.terrain_floor
	var heights := grid.terrain_height_cm
	var has_terrain := not floors.is_empty()
	var cx := c.x
	var cy := c.y
	var cz := c.z
	var c_column := cx + cz * sx
	var c_terrain := has_terrain and floors[c_column] == cy
	var c_cm: int = heights[c_column] if c_terrain else cy * 100
	var up_blocked := cy + 1 >= sy or solid[c_column + (cy + 1) * layer] != 0
	for d: Vector3i in DIRS_8:
		var nx := cx + d.x
		var nz := cz + d.z
		var diagonal := d.x != 0 and d.z != 0
		if diagonal and (_solid(solid, sx, sy, sz, nx, cy, cz) or _solid(solid, sx, sy, sz, cx, cy, nz)):
			continue  # no cutting corners
		if nx < 0 or nz < 0 or nx >= sx or nz >= sz:
			continue
		var column := nx + nz * sx
		var ny := cy
		var here := column + ny * layer
		var n_solid := solid[here] != 0
		if not n_solid and (ny == 0 or solid[here - layer] != 0):
			pass  # standable floor at the same level
		elif diagonal:
			continue
		elif n_solid:
			ny = cy + 1  # step up onto it
			if up_blocked or ny >= sy or solid[column + ny * layer] != 0:
				continue
		else:
			ny = cy - 1  # step down off an edge
			if ny < 0 or solid[column + ny * layer] != 0 or (ny > 0 and solid[column + (ny - 1) * layer] == 0):
				continue
		var n := Vector3i(nx, ny, nz)
		var occupant: int = occupied.get(n, -1)
		if occupant != -1 and occupant != mover_id:
			continue
		var n_terrain := has_terrain and floors[column] == ny
		var n_cm: int = heights[column] if n_terrain else ny * 100
		var limit := MAX_SLOPE_CM if c_terrain and n_terrain else MAX_CLIMB_CM
		if absi(c_cm - n_cm) <= limit:
			result.append(n)
	return result


static func _solid(solid: PackedByteArray, sx: int, sy: int, sz: int, x: int, y: int, z: int) -> bool:
	return x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz or solid[x + z * sx + y * sx * sz] != 0


## Cost of one step between neighbouring cells, without hazard penalties.
static func step_cost(a: Vector3i, b: Vector3i) -> int:
	var cost := COST_DIAGONAL if a.x != b.x and a.z != b.z else COST_STRAIGHT
	if a.y != b.y:
		cost += COST_STEP
	return cost


## Total movement cost of walking path (which excludes from).
static func movement_cost(from: Vector3i, path: Array[Vector3i]) -> int:
	var cost := 0
	var prev := from
	for c in path:
		cost += step_cost(prev, c)
		prev = c
	return cost


## Longest start of path whose movement cost fits in budget.
static func affordable_prefix(from: Vector3i, path: Array[Vector3i], budget: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var cost := 0
	var prev := from
	for c in path:
		cost += step_cost(prev, c)
		if cost > budget:
			break
		result.append(c)
		prev = c
	return result


## Path from `from` to `to`, excluding `from`. With stop_adjacent the path ends
## next to `to` instead of on it. With avoid_hazards the search pays extra to
## route around fire and ice. With max_cells > 0 the search gives up after
## settling that many cells, so a far or unreachable goal costs a bounded
## amount. Returns [] when there is no path or no move is needed.
## SimPathSearch runs the same search a bit at a time.
static func find_path(state: SimState, from: Vector3i, to: Vector3i, mover_id: int = -1, stop_adjacent: bool = false, avoid_hazards: bool = true, max_cells: int = 0) -> Array[Vector3i]:
	var search := SimPathSearch.new(state, from, to, mover_id, stop_adjacent, avoid_hazards, max_cells)
	search.step()
	return search.path


## Every cell reachable from `from` within a movement budget (no hazard
## penalties), mapped to its cheapest movement cost. Excludes `from`.
static func reachable(state: SimState, from: Vector3i, budget: int, mover_id: int = -1) -> Dictionary:
	var grid := state.grid
	var occupied := occupancy(state)
	var start := grid.index(from)
	var g := {start: 0}
	var closed := {}
	var result := {}
	var heap := PackedInt64Array()
	_push(heap, 0, start)
	while not heap.is_empty():
		var idx := _pop(heap) & _INDEX_MASK
		if closed.has(idx):
			continue
		closed[idx] = true
		var c := grid.coord(idx)
		var base_cost: int = g[idx]
		if idx != start:
			result[c] = base_cost
		for n in _neighbors(grid, occupied, c, mover_id):
			var ni := grid.index(n)
			var cost := base_cost + step_cost(c, n)
			if cost <= budget and not closed.has(ni) and (not g.has(ni) or cost < g[ni]):
				g[ni] = cost
				_push(heap, cost, ni)
	return result


## Whether the cells walkable from `goal` run out within POCKET_LIMIT without
## reaching `start` (walking is symmetric, so then start can't reach goal).
## A goal on a structure (a roof, a pier, a balcony) gets a bigger budget and
## counts as connected as soon as the walk reaches open ground, so a large
## roof is turned down cheaply instead of by a whole failed search.
static func _in_pocket_without(grid: SimGrid, occupied: Dictionary, goal: Vector3i, start: Vector3i, mover_id: int) -> bool:
	var on_structure := not grid.terrain_floor.is_empty() and not grid.is_terrain_floor(goal)
	var limit := STRUCTURE_POCKET_LIMIT if on_structure else POCKET_LIMIT
	var seen := {goal: true}
	var queue: Array[Vector3i] = [goal]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for n in _neighbors(grid, occupied, c, mover_id):
			if n == start or (on_structure and grid.is_terrain_floor(n)):
				return false
			if seen.has(n):
				continue
			seen[n] = true
			if seen.size() > limit:
				return false
			queue.append(n)
	return true


## Walking cost from the nearest of `sources` to every cell within max_cost
## (Dijkstra outward; walking is symmetric, so it is also the cost from each
## cell to them). Sources are usually occupied (opponents), so they seed the
## search instead of being stood on.
static func distance_field(state: SimState, sources: Array[Vector3i], max_cost: int, mover_id: int = -1) -> Dictionary:
	var grid := state.grid
	var occupied := occupancy(state)
	var g := {}
	var closed := {}
	var heap := PackedInt64Array()
	for s in sources:
		var si := grid.index(s)
		if not g.has(si):
			g[si] = 0
			_push(heap, 0, si)
	var result := {}
	while not heap.is_empty():
		var idx := _pop(heap) & _INDEX_MASK
		if closed.has(idx):
			continue
		closed[idx] = true
		var c := grid.coord(idx)
		var base_cost: int = g[idx]
		result[c] = base_cost
		for n in _neighbors(grid, occupied, c, mover_id):
			var ni := grid.index(n)
			var cost := base_cost + step_cost(c, n)
			if cost <= max_cost and not closed.has(ni) and (not g.has(ni) or cost < g[ni]):
				g[ni] = cost
				_push(heap, cost, ni)
	return result


static func _is_goal(c: Vector3i, to: Vector3i, stop_adjacent: bool) -> bool:
	if not stop_adjacent:
		return c == to
	return c != to and absi(c.x - to.x) <= 1 and absi(c.z - to.z) <= 1 and absi(c.y - to.y) <= 1


static func _hazard_cost(grid: SimGrid, i: int) -> int:
	var cost := 0
	if grid.fire[i] > 0:
		cost += HAZARD_FIRE
	if grid.surface_type[i] == SimMaterials.Surface.ICE:
		cost += HAZARD_ICE
	return cost


## Octile distance plus vertical steps; never overestimates.
static func distance(a: Vector3i, b: Vector3i) -> int:
	var dx := absi(a.x - b.x)
	var dz := absi(a.z - b.z)
	return COST_STRAIGHT * maxi(dx, dz) + (COST_DIAGONAL - COST_STRAIGHT) * mini(dx, dz) + COST_STEP * absi(a.y - b.y)


static func _reconstruct(grid: SimGrid, came_from: Dictionary, goal: int, start: int) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	var idx := goal
	while idx != start:
		path.push_front(grid.coord(idx))
		idx = came_from[idx]
	return path


# Binary min-heap of (priority << 24 | cell index); ties break on index, so the
# search order is deterministic.

static func _push(heap: PackedInt64Array, priority: int, idx: int) -> void:
	heap.append((priority << _INDEX_BITS) | idx)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[parent] <= heap[i]:
			break
		var tmp := heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


static func _pop(heap: PackedInt64Array) -> int:
	var top := heap[0]
	var last := heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	var size := heap.size()
	if size == 0:
		return top
	heap[0] = last
	var i := 0
	while true:
		var left := 2 * i + 1
		var right := left + 1
		var smallest := i
		if left < size and heap[left] < heap[smallest]:
			smallest = left
		if right < size and heap[right] < heap[smallest]:
			smallest = right
		if smallest == i:
			break
		var tmp := heap[smallest]
		heap[smallest] = heap[i]
		heap[i] = tmp
		i = smallest
	return top
