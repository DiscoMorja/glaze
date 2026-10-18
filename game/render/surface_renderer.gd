class_name SurfaceRenderer
extends MeshInstance3D
## Draws ground surfaces (water, oil, ice, vines, poison) as smooth puddles
## instead of boxes.
##
## Geometry: one quad per surface cell plus a ring of neighbouring floor cells
## (so the rounded outline has room on every side), with corners on the ground
## from WorldSpace.corner_y(). Neighbouring cells share corner heights, so the
## mesh has no gaps and follows the terrain.
## Shape and look: surface.gdshader, from a mask texture with one texel per
## column (topmost surface in that column).
## The mesh is rebuilt only when the set of surface cells changes; the mask is
## updated whenever surfaces change.

const SHADER := preload("res://game/render/surface.gdshader")
## Above the floor, to stay clear of the ground it lies on.
const LIFT := 0.04
## Neighbours further apart than this (a step or ledge) don't share a puddle.
const MAX_STEP := 0.6
## Mask channel per surface type: [mask, channel colour]. Mask 0 holds water,
## oil and ice (R, G, B), mask 1 vines and poison (R, G).
const CHANNELS := {
	SimMaterials.Surface.WATER: [0, Color(1, 0, 0)],
	SimMaterials.Surface.OIL: [0, Color(0, 1, 0)],
	SimMaterials.Surface.ICE: [0, Color(0, 0, 1)],
	SimMaterials.Surface.VINES: [1, Color(1, 0, 0)],
	SimMaterials.Surface.POISON: [1, Color(0, 1, 0)],
}

var _image: Image
var _texture: ImageTexture
var _image2: Image
var _texture2: ImageTexture
var _material: ShaderMaterial
var _size := Vector2i.ZERO
## Column index -> true for every mask texel currently painted.
var _painted := {}
var _mesh_cells := PackedInt32Array()
## The grid and surface version last drawn: unchanged surfaces aren't redrawn.
var _drawn := []


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER


func render(grid: SimGrid) -> void:
	var now := [grid.get_instance_id(), grid.surface_version, grid.solid_version, grid.size]
	if now == _drawn:
		return
	_drawn = now
	_fit(grid)
	var cells := PackedInt32Array()
	if grid.has_any(SimGrid.FIELD_SURFACES):
		cells = SimGrid.indices_of(grid.surface_type, CHANNELS.keys())
	_paint_mask(grid, cells)
	if cells != _mesh_cells:
		_mesh_cells = cells
		_build_mesh(grid, cells)


func _fit(grid: SimGrid) -> void:
	var size := Vector2i(grid.size.x, grid.size.z)
	if size == _size:
		return
	_size = size
	_image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("mask", _texture)
	_image2 = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	_image2.fill(Color(0, 0, 0, 0))
	_texture2 = ImageTexture.create_from_image(_image2)
	_material.set_shader_parameter("mask2", _texture2)
	_material.set_shader_parameter("grid_size", Vector2(size))
	_painted.clear()
	_mesh_cells = PackedInt32Array()


## One texel per column: the channel of its topmost surface, alpha = how full.
@warning_ignore("integer_division")
func _paint_mask(grid: SimGrid, cells: PackedInt32Array) -> void:
	var layer := _size.x * _size.y
	var top := {}  # column -> cell index (cells ascend in y, so the last wins)
	for i in cells:
		top[i % layer] = i
	if top.is_empty() and _painted.is_empty():
		return
	for column: int in _painted:
		if not top.has(column):
			_image.set_pixel(column % _size.x, column / _size.x, Color(0, 0, 0, 0))
			_image2.set_pixel(column % _size.x, column / _size.x, Color(0, 0, 0, 0))
	for column: int in top:
		var i: int = top[column]
		var channel: Array = CHANNELS[grid.surface_type[i]]
		var color: Color = channel[1]
		# Vines are thin: they read as fuller than their amount.
		var full := SimMaterials.AMOUNT_FULL / 4 if grid.surface_type[i] == SimMaterials.Surface.VINES else SimMaterials.AMOUNT_FULL
		color.a = clampf(float(grid.surface_amount[i]) / full, 0.0, 1.0)
		var x := column % _size.x
		var y := column / _size.x
		_image.set_pixel(x, y, color if channel[0] == 0 else Color(0, 0, 0, 0))
		_image2.set_pixel(x, y, color if channel[0] == 1 else Color(0, 0, 0, 0))
	_painted = top
	_texture.update(_image)
	_texture2.update(_image2)


func _build_mesh(grid: SimGrid, cells: PackedInt32Array) -> void:
	if cells.is_empty():
		mesh = null
		return
	var quads := {}  # cell index -> true
	for i in cells:
		var c := grid.coord(i)
		quads[i] = true
		var y := WorldSpace.floor_y(c)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var n: Variant = grid.floor_near(c + Vector3i(dx, 0, dz), 1)
				if n != null and absf(WorldSpace.floor_y(n) - y) <= MAX_STEP:
					quads[grid.index(n)] = true

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for i: int in quads:
		var c := grid.coord(i)
		var p00 := Vector3(c.x, WorldSpace.corner_y(c, Vector2i(0, 0)) + LIFT, c.z)
		var p10 := Vector3(c.x + 1, WorldSpace.corner_y(c, Vector2i(1, 0)) + LIFT, c.z)
		var p01 := Vector3(c.x, WorldSpace.corner_y(c, Vector2i(0, 1)) + LIFT, c.z + 1)
		var p11 := Vector3(c.x + 1, WorldSpace.corner_y(c, Vector2i(1, 1)) + LIFT, c.z + 1)
		for tri: Array in [[p00, p11, p10], [p00, p01, p11]]:
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var d: Vector3 = tri[2]
			var normal := (b - a).cross(d - a).normalized()
			if normal.y < 0.0:
				normal = -normal
			vertices.append_array(PackedVector3Array([a, b, d]))
			normals.append_array(PackedVector3Array([normal, normal, normal]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = built
	material_override = _material
