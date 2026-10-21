@tool
class_name LevelExit
extends Marker3D
## A way into another level (a mine mouth, a ladder, a cellar door): a party
## member standing on or next to the cell under it can take the whole party
## through (UseExitCommand, outside combat). They arrive at the LevelEntry
## named `target_entry` in `target_level`. Put something to see here (a
## frame, a hole); the marker itself is not drawn in game.

## What the party sees when hovering it ("Old mine").
@export var display_name := "Old mine"
@export_file("*.tscn") var target_level := ""
@export var target_entry := "start"
