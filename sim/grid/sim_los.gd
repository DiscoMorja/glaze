class_name SimLos
extends RefCounted
## Line of sight between cells, in integers. The line runs from the viewer's
## eye (1.5 m above its cell floor) toward the target and is blocked
## by any solid cell it passes through, and by thick smoke or darkness
## (SimMaterials.obscures()). It aims 1 m above the target cell floor
## (body height), so knee-high cover does not hide a target. Entities do not
## block sight.

## Samples per half-cell step along the line.
const _SAMPLES_PER_STEP := 2


static func has_line_of_sight(grid: SimGrid, from: Vector3i, to: Vector3i) -> bool:
	# Work in half-cell units so cell centres and the eye height are integers.
	var a := from * 2 + Vector3i(1, 3, 1)
	var b := to * 2 + Vector3i(1, 2, 1)
	var d := b - a
	var steps := maxi(absi(d.x), maxi(absi(d.y), absi(d.z))) * _SAMPLES_PER_STEP
	if steps == 0:
		return true
	var denominator := 2 * steps
	for i in range(1, steps):
		var p := a * steps + d * i
		var c := Vector3i(_floor_div(p.x, denominator), _floor_div(p.y, denominator), _floor_div(p.z, denominator))
		if c == from or c == to:
			continue
		if grid.in_bounds(c):
			var at := grid.index(c)
			if grid.solid[at] != 0 or _obscured(grid, at) or (c.y > 0 and _obscured(grid, at - grid.size.x * grid.size.z)):
				return false  # a cloud on the ground hides a standing body too: its cell and the one above
	return true


static func _obscured(grid: SimGrid, i: int) -> bool:
	return grid.gas_type[i] != 0 and SimMaterials.obscures(grid.gas_type[i], grid.gas_amount[i])


@warning_ignore("integer_division")
static func _floor_div(n: int, d: int) -> int:
	return n / d if n >= 0 else -((-n + d - 1) / d)
