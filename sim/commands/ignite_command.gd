class_name IgniteCommand
extends SimCommand
## Sets fire to open cells in a horizontal disc around center. What happens
## next is up to the rules: oil burns and spreads, water turns to steam.

const TYPE := "ignite"

var center: Vector3i
var radius: int


func _init(p_center: Vector3i = Vector3i.ZERO, p_radius: int = 0) -> void:
	center = p_center
	radius = p_radius


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	return _is_open_cell(state, center) and radius >= 0


func execute(state: SimState) -> void:
	for c in state.grid.disc_cells(center, radius):
		FireRules.ignite(state, c)


func to_dict() -> Dictionary:
	return {"type": TYPE, "center": center, "radius": radius}


static func from_dict(data: Dictionary) -> IgniteCommand:
	return IgniteCommand.new(data.center, data.radius)
