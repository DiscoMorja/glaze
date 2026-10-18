class_name SimPathSearch
extends RefCounted
## SimPathfinder.find_path as an object that can run a few cells at a time, so
## a long search can be spread over several frames. Run to the end in one go
## it is find_path; split into any number of step() calls it settles the same
## cells in the same order and finds the same path.

enum Status { RUNNING, FOUND, FAILED }

var status := Status.RUNNING
## The path (excluding the start) once status is FOUND.
var path: Array[Vector3i] = []

var _grid: SimGrid
var _occupied: Dictionary
var _from: Vector3i
var _to: Vector3i
var _mover_id: int
var _stop_adjacent: bool
var _avoid_hazards: bool
var _max_cells: int
var _start := 0
var _g := {}
var _came_from := {}
var _closed := {}
var _heap := PackedInt64Array()
var _pocket_checked := false


func _init(state: SimState, from: Vector3i, to: Vector3i, mover_id: int = -1, stop_adjacent: bool = false, avoid_hazards: bool = true, max_cells: int = 0) -> void:
	_grid = state.grid
	_from = from
	_to = to
	_mover_id = mover_id
	_stop_adjacent = stop_adjacent
	_avoid_hazards = avoid_hazards
	_max_cells = max_cells
	if not _grid.in_bounds(from) or not _grid.in_bounds(to):
		status = Status.FAILED
		return
	_occupied = SimPathfinder.occupancy(state)
	if not stop_adjacent and not SimPathfinder._standable(_grid, _occupied, to, mover_id):
		status = Status.FAILED
		return
	_pocket_checked = stop_adjacent
	_start = _grid.index(from)
	_g[_start] = 0
	SimPathfinder._push(_heap, SimPathfinder.distance(from, to), _start)


func done() -> bool:
	return status != Status.RUNNING


## Settles up to `cells` more cells (all of them with cells <= 0). The pocket
## check (bounded) runs as the first step. Returns done().
func step(cells: int = 0) -> bool:
	if status != Status.RUNNING:
		return true
	if not _pocket_checked:
		_pocket_checked = true
		if SimPathfinder._in_pocket_without(_grid, _occupied, _to, _from, _mover_id):
			status = Status.FAILED
			return true
		if cells > 0:
			return false  # the pocket check was this step's work
	var settled := 0
	while not _heap.is_empty():
		if cells > 0 and settled >= cells:
			return false
		var idx := SimPathfinder._pop(_heap) & SimPathfinder._INDEX_MASK
		if _closed.has(idx):
			continue
		_closed[idx] = true
		settled += 1
		if _max_cells > 0 and _closed.size() > _max_cells:
			status = Status.FAILED
			return true
		var c := _grid.coord(idx)
		if SimPathfinder._is_goal(c, _to, _stop_adjacent):
			path = SimPathfinder._reconstruct(_grid, _came_from, idx, _start)
			status = Status.FOUND
			return true
		var base_cost: int = _g[idx]
		for n in SimPathfinder._neighbors(_grid, _occupied, c, _mover_id):
			var ni := _grid.index(n)
			if _closed.has(ni):
				continue
			var cost := base_cost + SimPathfinder.step_cost(c, n)
			if _avoid_hazards:
				cost += SimPathfinder._hazard_cost(_grid, ni)
			if not _g.has(ni) or cost < _g[ni]:
				_g[ni] = cost
				_came_from[ni] = idx
				SimPathfinder._push(_heap, cost + SimPathfinder.distance(n, _to), ni)
	status = Status.FAILED
	return true
