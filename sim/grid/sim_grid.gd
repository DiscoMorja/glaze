class_name SimGrid
extends RefCounted
## Voxel grid holding all per-cell simulation state as structure-of-arrays:
## one packed array per field, addressed by index(). Coordinates are
## Vector3i(x, y, z) with y up. Out-of-bounds cells count as solid.

const NEIGHBORS_4 := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const NEIGHBORS_6 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
]

var size: Vector3i
var cell_count: int

var solid := PackedByteArray()
var surface_type := PackedByteArray()
var surface_amount := PackedInt32Array()
var gas_type := PackedByteArray()
var gas_amount := PackedInt32Array()
var temperature := PackedInt32Array()
var fire := PackedInt32Array()

var _layer: int


func _init(p_size: Vector3i) -> void:
	assert(p_size.x > 0 and p_size.y > 0 and p_size.z > 0)
	size = p_size
	_layer = size.x * size.z
	cell_count = _layer * size.y
	for arr: Variant in [solid, surface_type, surface_amount, gas_type, gas_amount, fire]:
		arr.resize(cell_count)
		arr.fill(0)
	temperature.resize(cell_count)
	temperature.fill(SimMaterials.AMBIENT_TEMPERATURE)


func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < size.x and c.y < size.y and c.z < size.z


## Flat index: x fastest, then z, then y (one horizontal layer per y).
func index(c: Vector3i) -> int:
	return c.x + c.z * size.x + c.y * _layer


@warning_ignore("integer_division")
func coord(i: int) -> Vector3i:
	var r := i % _layer
	return Vector3i(r % size.x, i / _layer, r / size.x)


func is_solid(c: Vector3i) -> bool:
	return not in_bounds(c) or solid[index(c)] != 0


## A cell is supported when the cell below it is solid (liquids rest on it).
func is_supported(c: Vector3i) -> bool:
	return is_solid(c + Vector3i.DOWN)


## Sets (or clears) solid on an inclusive box. Making a cell solid clears its contents.
func fill_solid(from: Vector3i, to: Vector3i, value: bool = true) -> void:
	var lo := Vector3i(mini(from.x, to.x), mini(from.y, to.y), mini(from.z, to.z))
	var hi := Vector3i(maxi(from.x, to.x), maxi(from.y, to.y), maxi(from.z, to.z))
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var c := Vector3i(x, y, z)
				if not in_bounds(c):
					continue
				var i := index(c)
				solid[i] = 1 if value else 0
				if value:
					clear_surface(i)
					clear_gas(i)
					fire[i] = 0


## Open (non-solid) cells in a horizontal disc around center, in deterministic order.
func disc_cells(center: Vector3i, radius: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			var c := center + Vector3i(dx, 0, dz)
			if not is_solid(c):
				cells.append(c)
	return cells


## Adds liquid/surface to a cell. Fails if the cell holds a different surface.
func add_surface(c: Vector3i, type: int, amount: int) -> bool:
	var i := index(c)
	var current: int = surface_type[i]
	if current != SimMaterials.Surface.NONE and current != type:
		return false
	surface_type[i] = type
	surface_amount[i] += amount
	return true


## Adds gas to a cell. Fails if the cell holds a different gas.
func add_gas(c: Vector3i, type: int, amount: int) -> bool:
	return add_gas_at(index(c), type, amount)


func add_gas_at(i: int, type: int, amount: int) -> bool:
	var current: int = gas_type[i]
	if current != SimMaterials.Gas.NONE and current != type:
		return false
	gas_type[i] = type
	gas_amount[i] += amount
	return true


func clear_surface(i: int) -> void:
	surface_type[i] = SimMaterials.Surface.NONE
	surface_amount[i] = 0


func clear_gas(i: int) -> void:
	gas_type[i] = SimMaterials.Gas.NONE
	gas_amount[i] = 0


## Ascending indices of cells whose value is one of `kinds`. Uses the arrays'
## native search, so the cost grows with the number of matches, not the grid.
static func indices_of(values: PackedByteArray, kinds: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for kind: int in kinds:
		var i := values.find(kind)
		while i != -1:
			result.append(i)
			i = values.find(kind, i + 1)
	result.sort()
	return result


## Ascending indices of cells whose value is between 1 and max_value.
static func indices_in_range(values: PackedInt32Array, max_value: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if values.count(0) == values.size():
		return result
	for kind in range(1, max_value + 1):
		var i := values.find(kind)
		while i != -1:
			result.append(i)
			i = values.find(kind, i + 1)
	result.sort()
	return result


func total_surface(type: int) -> int:
	var total := 0
	for i in cell_count:
		if surface_type[i] == type:
			total += surface_amount[i]
	return total


func total_gas(type: int) -> int:
	var total := 0
	for i in cell_count:
		if gas_type[i] == type:
			total += gas_amount[i]
	return total


func duplicate_grid() -> SimGrid:
	var copy := SimGrid.new(size)
	copy.solid = solid.duplicate()
	copy.surface_type = surface_type.duplicate()
	copy.surface_amount = surface_amount.duplicate()
	copy.gas_type = gas_type.duplicate()
	copy.gas_amount = gas_amount.duplicate()
	copy.temperature = temperature.duplicate()
	copy.fire = fire.duplicate()
	return copy


func hash_into(ctx: HashingContext) -> void:
	ctx.update(PackedInt32Array([size.x, size.y, size.z]).to_byte_array())
	ctx.update(solid)
	ctx.update(surface_type)
	ctx.update(surface_amount.to_byte_array())
	ctx.update(gas_type)
	ctx.update(gas_amount.to_byte_array())
	ctx.update(temperature.to_byte_array())
	ctx.update(fire.to_byte_array())
