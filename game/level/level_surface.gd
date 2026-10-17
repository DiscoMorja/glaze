@tool
class_name LevelSurface
extends Marker3D
## Pours a surface (water, oil, ice) onto the floor in a radius at level start.

enum Kind { WATER, OIL, ICE }

@export var kind: Kind = Kind.WATER
@export var amount := 60
@export_range(0, 8) var radius := 2


func surface() -> int:
	return [SimMaterials.Surface.WATER, SimMaterials.Surface.OIL, SimMaterials.Surface.ICE][kind]
