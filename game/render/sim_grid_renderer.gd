class_name SimGridRenderer
extends Node3D
## Draws a SimGrid with one MultiMesh per layer: solid tops, surfaces, gas, fire.
## Greybox visuals; call render() after the sim changes.

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


func _ready() -> void:
	_solid_layer = make_layer(self, Vector3(1, 1, 1), false, false)
	_surface_layer = make_layer(self, Vector3(0.96, 1, 0.96), true, false)
	_gas_layer = make_layer(self, Vector3(0.95, 0.95, 0.95), true, true)
	_fire_layer = make_layer(self, Vector3(0.55, 0.7, 0.55), false, true)


func render(grid: SimGrid) -> void:
	var solids := _Batch.new()
	var surfaces := _Batch.new()
	var gases := _Batch.new()
	var fires := _Batch.new()

	for i in grid.cell_count:
		var c := grid.coord(i)
		var base := Vector3(c.x + 0.5, c.y, c.z + 0.5)
		if grid.solid[i] != 0:
			if not grid.is_solid(c + Vector3i.UP):
				var shade := 0.32 + 0.09 * c.y
				solids.add(Transform3D(Basis(), base + Vector3(0, 0.5, 0)), Color(shade, shade * 0.95, shade * 0.85))
			continue

		var surface: int = grid.surface_type[i]
		if surface != SimMaterials.Surface.NONE:
			var fill := clampf(grid.surface_amount[i] / float(SimMaterials.AMOUNT_FULL), 0.0, 1.0)
			var thickness := 0.04 + 0.3 * fill
			surfaces.add(Transform3D(Basis().scaled(Vector3(1, thickness, 1)), base + Vector3(0, thickness / 2.0, 0)), SURFACE_COLORS[surface])

		var gas: int = grid.gas_type[i]
		if gas != SimMaterials.Gas.NONE:
			var color: Color = GAS_COLORS[gas]
			color.a = clampf(grid.gas_amount[i] / float(SimMaterials.AMOUNT_FULL), 0.05, 0.6)
			gases.add(Transform3D(Basis(), base + Vector3(0, 0.5, 0)), color)

		var fire: int = grid.fire[i]
		if fire > 0 and show_fire:
			var heat := fire / float(SimMaterials.FIRE_MAX)
			var height := 0.3 + 0.7 * heat
			fires.add(Transform3D(Basis().scaled(Vector3(1, height, 1)), base + Vector3(0, 0.35 * height, 0)), Color(1.0, 0.35 + 0.5 * heat, 0.05))

	solids.apply(_solid_layer)
	surfaces.apply(_surface_layer)
	gases.apply(_gas_layer)
	fires.apply(_fire_layer)


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


## Collects instances for one MultiMesh layer.
class _Batch:
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []

	func add(t: Transform3D, color: Color) -> void:
		transforms.append(t)
		colors.append(color)

	func apply(layer: MultiMeshInstance3D) -> void:
		var multimesh := layer.multimesh
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
			multimesh.set_instance_color(i, colors[i])
