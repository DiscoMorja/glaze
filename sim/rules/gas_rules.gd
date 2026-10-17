class_name GasRules
extends RefCounted
## Gas transport: gases rise when the cell above is open, otherwise spread
## sideways, then decay. Delta-based like LiquidRules for order independence;
## only cells holding gas (and the cells it moves into) are visited.

const GASES := [SimMaterials.Gas.STEAM, SimMaterials.Gas.SMOKE]


@warning_ignore("integer_division")
static func step(state: SimState) -> void:
	var grid := state.grid
	var types := grid.gas_type
	var amounts := grid.gas_amount
	var delta := PackedInt32Array()
	delta.resize(grid.cell_count)
	delta.fill(0)
	var next_types := types.duplicate()
	var active := SimGrid.indices_of(types, GASES)
	if active.is_empty():
		return
	var touched := {}

	for i in active:
		touched[i] = true
		var t: int = types[i]
		var amount: int = amounts[i]
		var c := grid.coord(i)

		var above := c + Vector3i.UP
		if not grid.is_solid(above):
			var ai := grid.index(above)
			if _can_receive(next_types, ai, t):
				delta[i] -= amount
				delta[ai] += amount
				next_types[ai] = t
				touched[ai] = true
				continue

		if amount < SimMaterials.GAS_MIN_SPREAD:
			continue
		for n: Vector3i in SimGrid.NEIGHBORS_4:
			var nc := c + n
			if grid.is_solid(nc):
				continue
			var ni := grid.index(nc)
			if not _can_receive(next_types, ni, t):
				continue
			var flow := (amount - amounts[ni]) / SimMaterials.GAS_SPREAD_DIVISOR
			if flow <= 0:
				continue
			delta[i] -= flow
			delta[ni] += flow
			next_types[ni] = t
			touched[ni] = true

	for i: int in touched:
		var t: int = next_types[i]
		if t == SimMaterials.Gas.NONE:
			continue
		var a: int = amounts[i] + delta[i] - SimMaterials.gas_decay(t)
		if a <= 0:
			grid.clear_gas(i)
		else:
			amounts[i] = a
			types[i] = t


static func _can_receive(next_types: PackedByteArray, i: int, type: int) -> bool:
	var current: int = next_types[i]
	return current == SimMaterials.Gas.NONE or current == type
