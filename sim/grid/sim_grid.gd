class_name SimGrid
extends RefCounted
## Voxel grid holding all per-cell simulation state as structure-of-arrays:
## one packed array per field, addressed by index(). Coordinates are
## Vector3i(x, y, z) with y up. Out-of-bounds cells count as solid.
##
## Copies (previews, AI lookahead) share arrays until one side writes
## (copy-on-write), so copying a big world is cheap. Code that writes a field
## calls its edit_*() first and only then reads the array it writes through;
## fire and temperature are written with set_fire() and set_temperature().

const NEIGHBORS_4 := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const NEIGHBORS_6 := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
]

## Fields, for copy-on-write ownership and activity flags.
const FIELD_SOLID := 1
const FIELD_SURFACES := 2
const FIELD_GASES := 4
const FIELD_FIRE := 8
const FIELD_HEAT := 16
const _ALL_FIELDS := 31

var size: Vector3i
var cell_count: int

var solid := PackedByteArray()
var surface_type := PackedByteArray()
var surface_amount := PackedInt32Array()
var gas_type := PackedByteArray()
var gas_amount := PackedInt32Array()
var temperature := PackedInt32Array()
var fire := PackedInt32Array()

## Real floor heights from the level bake (integer centimetres): the walk
## layer of each terrain column and the terrain height there (index
## x + z * width; empty when there is no terrain). See floor_cm(). Fixed after
## the bake, so copies share them.
var terrain_floor := PackedInt32Array()
var terrain_height_cm := PackedInt32Array()

## Cells whose temperature differs from ambient (index -> true), so heat is
## processed per hot or cold cell instead of over the whole grid.
var heat_cells := {}
## Burning cells (index -> true), so fire is processed per burning cell.
var fire_cells := {}

var _layer: int
## Fields whose arrays this grid owns (FIELD_* bits); the rest are shared.
var _owned := _ALL_FIELDS
## Fields that may hold something. Rules clear a bit when they find the field
## empty (an idle world then skips whole-grid scans); edit_*() sets it again.
var _maybe := _ALL_FIELDS
## Bumped by edit_surfaces() / edit_solid(), so rules and renderers can tell
## that nothing changed since they last looked (not saved: derived).
var surface_version := 0
var solid_version := 0
## [surface_version, solid_version] when liquids last found nothing to move:
## until either changes, the next step would move nothing too.
var liquids_still_at := [-1, -1]
## surface_version when there was last no ice anywhere.
var no_ice_at := -1


func _init(p_size: Vector3i, allocate: bool = true) -> void:
	assert(p_size.x > 0 and p_size.y > 0 and p_size.z > 0)
	size = p_size
	_layer = size.x * size.z
	cell_count = _layer * size.y
	if not allocate:
		return
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


# --- Floor heights ------------------------------------------------------------

func set_terrain(floors: PackedInt32Array, heights_cm: PackedInt32Array) -> void:
	terrain_floor = floors
	terrain_height_cm = heights_cm


## Whether a cell stands on terrain (its column's walk layer), not a structure.
func is_terrain_floor(c: Vector3i) -> bool:
	return not terrain_floor.is_empty() and terrain_floor[c.x + c.z * size.x] == c.y


## Height (cm) of the floor a cell stands on: the real terrain height on a
## terrain column's walk layer, else the cell's level (y * 100).
func floor_cm(c: Vector3i) -> int:
	if not terrain_floor.is_empty():
		var column := c.x + c.z * size.x
		if terrain_floor[column] == c.y:
			return terrain_height_cm[column]
	return c.y * 100


# --- Writing (copy-on-write) --------------------------------------------------

func edit_solid() -> void:
	if (_owned & FIELD_SOLID) == 0:
		solid = solid.duplicate()
		_owned |= FIELD_SOLID
	solid_version += 1


func edit_surfaces() -> void:
	if (_owned & FIELD_SURFACES) == 0:
		surface_type = surface_type.duplicate()
		surface_amount = surface_amount.duplicate()
		_owned |= FIELD_SURFACES
	_maybe |= FIELD_SURFACES
	surface_version += 1


## Gives up ownership of the surface arrays: the next edit copies them, so the
## current arrays stay as they are (a snapshot for rules that read old values).
func detach_surfaces() -> void:
	_owned &= ~FIELD_SURFACES


func edit_gases() -> void:
	if (_owned & FIELD_GASES) == 0:
		gas_type = gas_type.duplicate()
		gas_amount = gas_amount.duplicate()
		_owned |= FIELD_GASES
	_maybe |= FIELD_GASES


func edit_fire() -> void:
	if (_owned & FIELD_FIRE) == 0:
		fire = fire.duplicate()
		_owned |= FIELD_FIRE
	_maybe |= FIELD_FIRE


func edit_heat() -> void:
	if (_owned & FIELD_HEAT) == 0:
		temperature = temperature.duplicate()
		_owned |= FIELD_HEAT


## Writes a cell's fire intensity and keeps fire_cells current.
func set_fire(i: int, value: int) -> void:
	edit_fire()
	fire[i] = value
	if value > 0:
		fire_cells[i] = true
	else:
		fire_cells.erase(i)


## Burning cells in index order.
func burning_cells() -> PackedInt32Array:
	var result := PackedInt32Array(fire_cells.keys())
	result.sort()
	return result


## Writes a cell's temperature (after edit_heat()) and keeps heat_cells current.
func set_temperature(i: int, value: int) -> void:
	temperature[i] = value
	if value == SimMaterials.AMBIENT_TEMPERATURE:
		heat_cells.erase(i)
	else:
		heat_cells[i] = true


## Sets every cell to one temperature (tests and setup).
func fill_temperature(value: int) -> void:
	edit_heat()
	temperature.fill(value)
	heat_cells.clear()
	if value != SimMaterials.AMBIENT_TEMPERATURE:
		for i in cell_count:
			heat_cells[i] = true


## Whether a field (FIELD_SURFACES or FIELD_GASES) may hold anything. Scans
## at most once while the field stays empty.
func has_any(field: int) -> bool:
	if (_maybe & field) == 0:
		return false
	var empty := false
	match field:
		FIELD_SURFACES:
			empty = surface_type.count(0) == cell_count
		FIELD_GASES:
			empty = gas_type.count(0) == cell_count
	if empty:
		_maybe &= ~field
	return not empty


## Sets (or clears) solid on an inclusive box. Making a cell solid clears its contents.
func fill_solid(from: Vector3i, to: Vector3i, value: bool = true) -> void:
	edit_solid()
	edit_surfaces()
	edit_gases()
	edit_fire()
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
					set_fire(i, 0)


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


## The open, supported cell in c's column nearest c within `reach` levels (a
## splash lands on the ground below or on the step above), or null.
func floor_near(c: Vector3i, reach: int) -> Variant:
	for d in reach + 1:
		for dy: int in ([0] if d == 0 else [-d, d]):
			var n := c + Vector3i(0, dy, 0)
			if in_bounds(n) and not is_solid(n) and is_supported(n):
				return n
	return null


## Adds liquid/surface to a cell. Fails if the cell holds a different surface.
func add_surface(c: Vector3i, type: int, amount: int) -> bool:
	var i := index(c)
	var current: int = surface_type[i]
	if current != SimMaterials.Surface.NONE and current != type:
		return false
	edit_surfaces()
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
	edit_gases()
	gas_type[i] = type
	gas_amount[i] += amount
	return true


func clear_surface(i: int) -> void:
	edit_surfaces()
	surface_type[i] = SimMaterials.Surface.NONE
	surface_amount[i] = 0


func clear_gas(i: int) -> void:
	edit_gases()
	gas_type[i] = SimMaterials.Gas.NONE
	gas_amount[i] = 0


## Ascending indices of cells whose value is one of `kinds`. Uses the arrays'
## native search, so the cost grows with the number of matches, not the grid.
static func indices_of(values: PackedByteArray, kinds: Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	if kinds.size() > 1 and values.count(0) == values.size():
		return result
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


## Copy that shares this grid's arrays until either side writes them.
func duplicate_grid() -> SimGrid:
	var copy := SimGrid.new(size, false)
	copy.solid = solid
	copy.surface_type = surface_type
	copy.surface_amount = surface_amount
	copy.gas_type = gas_type
	copy.gas_amount = gas_amount
	copy.temperature = temperature
	copy.fire = fire
	copy.terrain_floor = terrain_floor
	copy.terrain_height_cm = terrain_height_cm
	copy.heat_cells = heat_cells.duplicate()
	copy.fire_cells = fire_cells.duplicate()
	copy._maybe = _maybe
	copy.surface_version = surface_version
	copy.solid_version = solid_version
	copy.liquids_still_at = liquids_still_at.duplicate()
	copy.no_ice_at = no_ice_at
	copy._owned = 0
	_owned = 0
	return copy


## Everything needed to rebuild this grid (see from_dict()), for snapshots.
func to_dict() -> Dictionary:
	return {
		"size": size, "solid": solid, "surface_type": surface_type, "surface_amount": surface_amount,
		"gas_type": gas_type, "gas_amount": gas_amount, "temperature": temperature, "fire": fire,
		"terrain_floor": terrain_floor, "terrain_height_cm": terrain_height_cm,
		"heat_cells": PackedInt32Array(heat_cells.keys()), "fire_cells": PackedInt32Array(fire_cells.keys()),
	}


static func from_dict(data: Dictionary) -> SimGrid:
	var grid := SimGrid.new(data.size, false)
	grid.solid = data.solid
	grid.surface_type = data.surface_type
	grid.surface_amount = data.surface_amount
	grid.gas_type = data.gas_type
	grid.gas_amount = data.gas_amount
	grid.temperature = data.temperature
	grid.fire = data.fire
	grid.terrain_floor = data.terrain_floor
	grid.terrain_height_cm = data.terrain_height_cm
	for i: int in data.heat_cells:
		grid.heat_cells[i] = true
	for i: int in data.fire_cells:
		grid.fire_cells[i] = true
	return grid


func hash_into(ctx: HashingContext) -> void:
	ctx.update(PackedInt32Array([size.x, size.y, size.z]).to_byte_array())
	ctx.update(solid)
	ctx.update(surface_type)
	ctx.update(surface_amount.to_byte_array())
	ctx.update(gas_type)
	ctx.update(gas_amount.to_byte_array())
	ctx.update(temperature.to_byte_array())
	ctx.update(fire.to_byte_array())
