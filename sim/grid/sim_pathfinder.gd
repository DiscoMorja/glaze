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

const _INDEX_BITS := 24
const _INDEX_MASK := (1 << 24) - 1


## A cell a unit can stand in: open, on solid ground, not taken by another living entity.
static func is_standable(state: SimState, c: Vector3i, mover_id: int = -1) -> bool:
	var grid := state.grid
	if not grid.in_bounds(c) or grid.is_solid(c) or not grid.is_supported(c):
		return false
	var occupant := state.entity_at(c)
	return occupant == null or occupant.id == mover_id


static func neighbors(state: SimState, c: Vector3i, mover_id: int = -1) -> Array[Vector3i]:
	var grid := state.grid
	var result: Array[Vector3i] = []
	for d: Vector3i in DIRS_8:
		var diagonal := d.x != 0 and d.z != 0
		if diagonal and (grid.is_solid(c + Vector3i(d.x, 0, 0)) or grid.is_solid(c + Vector3i(0, 0, d.z))):
			continue  # no cutting corners
		var n := c + d
		if is_standable(state, n, mover_id):
			result.append(n)
		elif diagonal:
			continue
		elif grid.is_solid(n):
			var up := n + Vector3i.UP
			if not grid.is_solid(c + Vector3i.UP) and is_standable(state, up, mover_id):
				result.append(up)
		elif not grid.is_supported(n):
			var down := n + Vector3i.DOWN
			if is_standable(state, down, mover_id):
				result.append(down)
	return result


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
## next to `to` instead of on it. Returns [] when there is no path or no move is needed.
static func find_path(state: SimState, from: Vector3i, to: Vector3i, mover_id: int = -1, stop_adjacent: bool = false) -> Array[Vector3i]:
	var grid := state.grid
	var none: Array[Vector3i] = []
	if not grid.in_bounds(from) or not grid.in_bounds(to):
		return none
	if not stop_adjacent and not is_standable(state, to, mover_id):
		return none

	var start := grid.index(from)
	var g := {start: 0}
	var came_from := {}
	var closed := {}
	var heap := PackedInt64Array()
	_push(heap, distance(from, to), start)

	while not heap.is_empty():
		var idx := _pop(heap) & _INDEX_MASK
		if closed.has(idx):
			continue
		closed[idx] = true
		var c := grid.coord(idx)
		if _is_goal(c, to, stop_adjacent):
			return _reconstruct(grid, came_from, idx, start)
		var base_cost: int = g[idx]
		for n in neighbors(state, c, mover_id):
			var ni := grid.index(n)
			if closed.has(ni):
				continue
			var cost := base_cost + step_cost(c, n) + _hazard_cost(grid, ni)
			if not g.has(ni) or cost < g[ni]:
				g[ni] = cost
				came_from[ni] = idx
				_push(heap, cost + distance(n, to), ni)
	return none


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
