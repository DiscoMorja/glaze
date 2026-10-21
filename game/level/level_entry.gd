@tool
class_name LevelEntry
extends Marker3D
## Where a party coming through a LevelExit arrives (it gathers on free cells
## around the floor under this marker). LevelExits name it by `entry_name`.

@export var entry_name := "start"
