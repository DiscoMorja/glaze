class_name CellMarkers
extends Node3D
## Flat translucent tiles drawn on cells: cursor, paths, previews, selection.

var _layer: MultiMeshInstance3D


func _ready() -> void:
	_layer = SimGridRenderer.make_layer(self, Vector3(0.9, 0.05, 0.9), true, true)


func show_cells(cells: Array[Vector3i], colors: Array[Color], lift: float = 0.06) -> void:
	var multimesh := _layer.multimesh
	multimesh.instance_count = cells.size()
	for i in cells.size():
		var c := cells[i]
		multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(c.x + 0.5, c.y + lift, c.z + 0.5)))
		multimesh.set_instance_color(i, colors[i])


func clear() -> void:
	_layer.multimesh.instance_count = 0
