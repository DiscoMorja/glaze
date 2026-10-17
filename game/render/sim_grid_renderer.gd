class_name SimGridRenderer
extends Node3D
## Draws a SimGrid with one MultiMesh per layer: solid tops, surfaces, gas, fire.
## Greybox visuals; call render() after the sim changes.
##
## Solids rarely change, so they are only rebuilt when the solid array does.
## Instance data is uploaded in one bulk buffer per layer instead of per
## instance calls, which keeps a redraw to a few milliseconds.

const SURFACE_COLORS := {
	SimMaterials.Surface.WATER: Color(0.2, 0.45, 0.95, 0.8),
	SimMaterials.Surface.OIL: Color(0.12, 0.08, 0.03, 0.95),
	SimMaterials.Surface.ICE: Color(0.8, 0.93, 1.0, 0.9),
}
const GAS_COLORS := {
	SimMaterials.Gas.STEAM: Color(0.95, 0.95, 1.0),
	SimMaterials.Gas.SMOKE: Color(0.2, 0.2, 0.2),
}

## Draw fire as greybox boxes. Scenes with a FireField turn this off.
var show_fire := true

var _solid_layer: MultiMeshInstance3D
var _surface_layer: MultiMeshInstance3D
var _gas_layer: MultiMeshInstance3D
var _fire_layer: MultiMeshInstance3D
var _drawn_solids := PackedByteArray()


func _ready() -> void:
	_solid_layer = make_layer(self, Vector3(1, 1, 1), false, false)
	_surface_layer = make_layer(self, Vector3(0.96, 1, 0.96), true, false)
	_gas_layer = make_layer(self, Vector3(0.95, 0.95, 0.95), true, true)
	_fire_layer = make_layer(self, Vector3(0.55, 0.7, 0.55), false, true)


func render(grid: SimGrid) -> void:
	if grid.solid != _drawn_solids:
		_render_solids(grid)
		_drawn_solids = grid.solid.duplicate()

	var surfaces := _Batch.new()
	var gases := _Batch.new()
	var fires := _Batch.new()
	var surface_types := grid.surface_type
	var gas_types := grid.gas_type
	var fire := grid.fire
	var full := float(SimMaterials.AMOUNT_FULL)

	for i in grid.cell_count:
		var surface: int = surface_types[i]
		var gas: int = gas_types[i]
		var flame: int = fire[i] if show_fire else 0
		if surface == 0 and gas == 0 and flame == 0:
			continue
		var c := grid.coord(i)
		var x := c.x + 0.5
		var z := c.z + 0.5
		if surface != 0:
			var fill := clampf(grid.surface_amount[i] / full, 0.0, 1.0)
			var thickness := 0.04 + 0.3 * fill
			surfaces.add(Vector3(x, c.y + thickness / 2.0, z), Vector3(1, thickness, 1), SURFACE_COLORS[surface])
		if gas != 0:
			var color: Color = GAS_COLORS[gas]
			color.a = clampf(grid.gas_amount[i] / full, 0.05, 0.6)
			gases.add(Vector3(x, c.y + 0.5, z), Vector3.ONE, color)
		if flame != 0:
			var heat := flame / float(SimMaterials.FIRE_MAX)
			var height := 0.3 + 0.7 * heat
			fires.add(Vector3(x, c.y + 0.35 * height, z), Vector3(1, height, 1), Color(1.0, 0.35 + 0.5 * heat, 0.05))

	surfaces.apply(_surface_layer)
	gases.apply(_gas_layer)
	fires.apply(_fire_layer)


func _render_solids(grid: SimGrid) -> void:
	var solids := _Batch.new()
	var solid := grid.solid
	var layer := grid.size.x * grid.size.z
	for i in grid.cell_count:
		if solid[i] == 0:
			continue
		var above := i + layer
		if above < grid.cell_count and solid[above] != 0:
			continue  # buried; only exposed tops are drawn
		var c := grid.coord(i)
		var shade := 0.32 + 0.09 * c.y
		solids.add(Vector3(c.x + 0.5, c.y + 0.5, c.z + 0.5), Vector3.ONE, Color(shade, shade * 0.95, shade * 0.85))
	solids.apply(_solid_layer)


static func make_layer(parent: Node, box_size: Vector3, transparent: bool, unshaded: bool) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	parent.add_child(instance)
	return instance


## Collects instances for one MultiMesh layer as a raw buffer: per instance a
## 3x4 transform (row-major basis + origin) followed by an RGBA colour.
class _Batch:
	const STRIDE := 16

	var data := PackedFloat32Array()
	var count := 0

	func add(origin: Vector3, scale: Vector3, color: Color) -> void:
		var base := data.size()
		data.resize(base + STRIDE)
		data[base + 0] = scale.x
		data[base + 3] = origin.x
		data[base + 5] = scale.y
		data[base + 7] = origin.y
		data[base + 10] = scale.z
		data[base + 11] = origin.z
		data[base + 12] = color.r
		data[base + 13] = color.g
		data[base + 14] = color.b
		data[base + 15] = color.a
		count += 1

	func apply(layer: MultiMeshInstance3D) -> void:
		var multimesh := layer.multimesh
		multimesh.instance_count = count
		if count > 0:
			multimesh.buffer = data
