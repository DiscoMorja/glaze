extends RefCounted
## Shared sim setups for tests. The floor is solid at y = 0, so the walkable
## layer is y = FLOOR_Y.

const FLOOR_Y := 1


static func flat_state(size: Vector3i = Vector3i(9, 4, 9), seed_value: int = 1234) -> SimState:
	var grid := SimGrid.new(size)
	grid.fill_solid(Vector3i(0, 0, 0), Vector3i(size.x - 1, 0, size.z - 1))
	return SimState.new(grid, seed_value)


static func events_of_type(events: Array[SimEvent], type: SimEvent.Type) -> Array[SimEvent]:
	var matching: Array[SimEvent] = []
	for e in events:
		if e.type == type:
			matching.append(e)
	return matching
