class_name SimGridRenderer
extends Node3D
## Draws a SimGrid: ground surfaces as smooth puddles (SurfaceRenderer), and one
## MultiMesh per layer for solid tops, gas and fire. Greybox visuals for the
## latter; call render() after the sim changes.
##
## Solids rarely change, so they are only rebuilt when the solid array does.
## Instance data is uploaded in one bulk buffer per layer instead of per
## instance calls, which keeps a redraw to a few milliseconds.

const GAS_COLORS := {
	SimMaterials.Gas.STEAM: Color(0.95, 0.95, 1.0),
	SimMaterials.Gas.SMOKE: Color(0.2, 0.2, 0.2),
}

## Draw fire as greybox boxes. Scenes with a FireField turn this off.
var show_fire := true
## Draw solid cells. Levels with real geometry turn this off.
var show_solids := true

var _solid_layer: MultiMeshInstance3D
var _surfaces: SurfaceRenderer
var _gas_layer: MultiMeshInstance3D
var _fire_layer: MultiMeshInstance3D
var _drawn_solids := PackedByteArray()


func _ready() -> void:
	_solid_layer = make_layer(self, Vector3(1, 1, 1), false, false)
	_surfaces = SurfaceRenderer.new()
	add_child(_surfaces)
	_gas_layer = make_layer(self, Vector3(0.95, 0.95, 0.95), true, true)
	_fire_layer = make_layer(self, Vector3(0.55, 0.7, 0.55), false, true)


func render(grid: SimGrid) -> void:
	if not show_solids:
		if not _drawn_solids.is_empty():
			_Batch.new().apply(_solid_layer)
			_drawn_solids = PackedByteArray()
	elif grid.solid != _drawn_solids:
		_render_solids(grid)
		_drawn_solids = grid.solid.duplicate()

	_surfaces.render(grid)
	var gases := _Batch.new()
	var fires := _Batch.new()
	var gas_types := grid.gas_type
	var fire := grid.fire
	var full := float(SimMaterials.AMOUNT_FULL)

	# Only cells holding something, found with native searches, so a big
	# mostly-empty world costs little to draw.
	var cells := {}
	if grid.has_any(SimGrid.FIELD_GASES):
		for i in SimGrid.indices_of(gas_types, GAS_COLORS.keys()):
			cells[i] = true
	if show_fire:
		for i in grid.burning_cells():
			cells[i] = true

	for i: int in cells:
		var gas: int = gas_types[i]
		var flame: int = fire[i] if show_fire else 0
		if gas == 0 and flame == 0:
			continue
		var c := grid.coord(i)
		var x := c.x + 0.5
		var z := c.z + 0.5
		var floor_y := WorldSpace.floor_y(c)
		if gas != 0:
			var color: Color = GAS_COLORS[gas]
			color.a = clampf(grid.gas_amount[i] / full, 0.05, 0.6)
			gases.add(Vector3(x, c.y + 0.5, z), Vector3.ONE, color)
		if flame != 0:
			var heat := flame / float(SimMaterials.FIRE_MAX)
			var height := 0.3 + 0.7 * heat
			fires.add(Vector3(x, floor_y + 0.35 * height, z), Vector3(1, height, 1), Color(1.0, 0.35 + 0.5 * heat, 0.05))

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
