class_name RouteSearches
extends RefCounted
## Walk routes for exploring, searched a few milliseconds per frame (as
## SimPathSearch steps) so a far click or hover never costs one long frame.
## Finished routes are kept for a moment, so the search the hover preview ran
## also serves the click on that cell.

## Cells settled between clock checks.
const CHUNK := 48
## How long a finished route is reused.
const KEEP_MSEC := 1500

## Searches still running, oldest first: [key, SimPathSearch, urgent].
var _jobs: Array = []
## key -> [route, finished msec]
var _done := {}


static func key_for(walker: SimEntity, to: Vector3i) -> Array:
	return [walker.id, walker.cell, to]


## The route for `walker` to `to` if it has been found ([] when there is no
## way), else null and the search is started (or kept going). A non-urgent
## request (the hover) drops the other non-urgent searches; an urgent one (a
## walk order) runs before them.
func find(state: SimState, walker: SimEntity, to: Vector3i, urgent: bool) -> Variant:
	var key := key_for(walker, to)
	var known: Variant = _done.get(key)
	if known != null and Time.get_ticks_msec() - int(known[1]) <= KEEP_MSEC:
		return known[0]
	var job: Array = []
	for j: Array in _jobs:
		if j[0] == key:
			job = j
	if not urgent:
		_jobs = _jobs.filter(func(j: Array) -> bool: return j[2] or j[0] == key)
	if job.is_empty():
		job = [key, SimPathSearch.new(state, walker.cell, to, walker.id, false, true, TravelCommand.MAX_SEARCH_CELLS), urgent]
		if urgent:
			_jobs.push_front(job)
		else:
			_jobs.append(job)
	elif urgent and not job[2]:
		job[2] = true
		_jobs.erase(job)
		_jobs.push_front(job)
	return null


func busy() -> bool:
	return not _jobs.is_empty()


## Runs the searches for up to `budget_usec`. Returns whether any finished.
func run(budget_usec: int) -> bool:
	var until := Time.get_ticks_usec() + budget_usec
	var finished := false
	while not _jobs.is_empty() and Time.get_ticks_usec() < until:
		var job: Array = _jobs[0]
		var search: SimPathSearch = job[1]
		if search.step(CHUNK):
			_jobs.pop_front()
			_done[job[0]] = [search.path if search.status == SimPathSearch.Status.FOUND else ([] as Array[Vector3i]), Time.get_ticks_msec()]
			finished = true
	if finished:
		_forget_old()
	return finished


func clear() -> void:
	_jobs.clear()
	_done.clear()


func _forget_old() -> void:
	var now := Time.get_ticks_msec()
	for key: Array in _done.keys():
		if now - int(_done[key][1]) > KEEP_MSEC:
			_done.erase(key)
