@tool
class_name LevelBarrel
extends Marker3D
## Places a breakable barrel that spills its contents when destroyed.

enum Contents { OIL, WATER, EMPTY }

@export var contents: Contents = Contents.OIL
@export var amount := 150


func surface() -> int:
	match contents:
		Contents.OIL:
			return SimMaterials.Surface.OIL
		Contents.WATER:
			return SimMaterials.Surface.WATER
	return SimMaterials.Surface.NONE


func display_name() -> String:
	return ["Oil barrel", "Water barrel", "Barrel"][contents]
