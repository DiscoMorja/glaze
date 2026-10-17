class_name LiquidRules
extends RefCounted
## Liquid transport: liquids fall when unsupported, otherwise spread to open
## neighbours with less liquid (and drain quickly off ledges). Reads the current
## grid and writes deltas, so results don't depend on iteration order.


@warning_ignore("integer_division")
static func step(state: SimState) -> void:
	var grid := state.grid
	var types := grid.surface_type
	var amounts := grid.surface_amount
	var delta := PackedInt32Array()
	delta.resize(grid.cell_count)
	delta.fill(0)
	var next_types := types.duplicate()

	for i in grid.cell_count:
		var t: int = types[i]
		if not SimMaterials.is_fluid(t):
			continue
		var amount: int = amounts[i]
		var c := grid.coord(i)

		var below := c + Vector3i.DOWN
		if not grid.is_solid(below):
			var bi := grid.index(below)
			if _can_receive(next_types, bi, t):
				delta[i] -= amount
				delta[bi] += amount
				next_types[bi] = t
				continue

		if amount < SimMaterials.min_spread(t):
			continue
		var viscosity := SimMaterials.viscosity(t)
		for n: Vector3i in SimGrid.NEIGHBORS_4:
			var nc := c + n
			if grid.is_solid(nc):
				continue
			var ni := grid.index(nc)
			if not _can_receive(next_types, ni, t):
				continue
			# Over a ledge the neighbour holds nothing for long, so drain as if it were empty.
			var diff: int = amount if not grid.is_supported(nc) else amount - amounts[ni]
			var flow := diff / viscosity
			if flow <= 0:
				continue
			delta[i] -= flow
			delta[ni] += flow
			next_types[ni] = t

	for i in grid.cell_count:
		var d: int = delta[i]
		if d == 0:
			continue
		var a: int = amounts[i] + d
		if a <= 0:
			grid.clear_surface(i)
		else:
			amounts[i] = a
			types[i] = next_types[i]


## A cell can receive a liquid if it is empty or already holds the same liquid
## (including liquid scheduled to arrive this tick).
static func _can_receive(next_types: PackedByteArray, i: int, type: int) -> bool:
	var current: int = next_types[i]
	return current == SimMaterials.Surface.NONE or current == type
