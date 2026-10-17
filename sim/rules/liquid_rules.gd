class_name LiquidRules
extends RefCounted
## Liquid transport: liquids fall when unsupported, otherwise spread to open
## neighbours with less liquid (and drain quickly off ledges). Reads the current
## grid and writes deltas, so results don't depend on iteration order. Only
## cells holding a liquid (and the cells they flow into) are visited.


const FLUIDS := [SimMaterials.Surface.WATER, SimMaterials.Surface.OIL]


@warning_ignore("integer_division")
static func step(state: SimState) -> void:
	var grid := state.grid
	if not grid.has_any(SimGrid.FIELD_SURFACES):
		return
	var types := grid.surface_type
	var amounts := grid.surface_amount
	var active := SimGrid.indices_of(types, FLUIDS)
	if active.is_empty():
		return
	# Sparse: only cells that hold or receive something get entries.
	var delta := {}
	var next_types := {}
	var touched := {}

	for i in active:
		touched[i] = true
		var t: int = types[i]
		var amount: int = amounts[i]
		var c := grid.coord(i)

		var below := c + Vector3i.DOWN
		if not grid.is_solid(below):
			var bi := grid.index(below)
			if _can_receive(types, next_types, bi, t):
				delta[i] = delta.get(i, 0) - amount
				delta[bi] = delta.get(bi, 0) + amount
				next_types[bi] = t
				touched[bi] = true
				continue

		if amount < SimMaterials.min_spread(t):
			continue
		var viscosity := SimMaterials.viscosity(t)
		for n: Vector3i in SimGrid.NEIGHBORS_4:
			var nc := c + n
			if grid.is_solid(nc):
				continue
			var ni := grid.index(nc)
			if not _can_receive(types, next_types, ni, t):
				continue
			# Over a ledge the neighbour holds nothing for long, so drain as if it were empty.
			var diff: int = amount if not grid.is_supported(nc) else amount - amounts[ni]
			var flow := diff / viscosity
			if flow <= 0:
				continue
			delta[i] = delta.get(i, 0) - flow
			delta[ni] = delta.get(ni, 0) + flow
			next_types[ni] = t
			touched[ni] = true

	if delta.is_empty():
		return
	grid.edit_surfaces()
	types = grid.surface_type
	amounts = grid.surface_amount
	for i: int in touched:
		var d: int = delta.get(i, 0)
		if d == 0:
			continue
		var a: int = amounts[i] + d
		if a <= 0:
			grid.clear_surface(i)
		else:
			amounts[i] = a
			types[i] = next_types.get(i, types[i])


## A cell can receive a liquid if it is empty or already holds the same liquid
## (including liquid scheduled to arrive this tick).
static func _can_receive(types: PackedByteArray, next_types: Dictionary, i: int, type: int) -> bool:
	var current: int = next_types.get(i, types[i])
	return current == SimMaterials.Surface.NONE or current == type
