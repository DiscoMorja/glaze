class_name SimEvent
extends RefCounted
## Something notable that happened in the sim. Presentation (VFX, audio,
## narration) consumes these; the sim never knows about presentation.

enum Type { IGNITED, EXTINGUISHED, BURNED_OUT, FROZE, MELTED }

var type: Type
var cell: Vector3i


func _init(p_type: Type, p_cell: Vector3i) -> void:
	type = p_type
	cell = p_cell
