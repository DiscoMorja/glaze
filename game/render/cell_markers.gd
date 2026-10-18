class_name CellMarkers
extends Node3D
## Flat translucent tiles drawn on cells: cursor, paths, previews, selection.
## They draw over grass and other foliage so the ground stays readable.

## Characters write this stencil value (their outline pass); markers skip
## those pixels, so they show over grass but never over a character.
const CHARACTER_STENCIL := 1

var _layer: MultiMeshInstance3D


func _ready() -> void:
	_layer = SimGridRenderer.make_layer(self, Vector3(0.9, 0.05, 0.9), true, true)
	var material := _layer.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
	if material == null:
		material = (_layer.multimesh.mesh as BoxMesh).material as StandardMaterial3D
	material.no_depth_test = true
	material.render_priority = 5
	material.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	material.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
	material.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
	material.stencil_reference = CHARACTER_STENCIL


func show_cells(cells: Array[Vector3i], colors: Array[Color], lift: float = 0.06) -> void:
	var multimesh := _layer.multimesh
	multimesh.instance_count = cells.size()
	for i in cells.size():
		var c := cells[i]
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x + 0.5, WorldSpace.floor_y(c) + lift, c.z + 0.5)))
		multimesh.set_instance_color(i, colors[i])


func clear() -> void:
	_layer.multimesh.instance_count = 0
