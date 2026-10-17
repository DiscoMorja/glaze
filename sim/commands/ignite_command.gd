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
	var grid := state.grid
	for c in grid.disc_cells(center, radius):
		var i := grid.index(c)
		if grid.fire[i] == 0:
			state.emit_event(SimEvent.Type.IGNITED, c)
		grid.fire[i] = SimMaterials.FIRE_MAX


func to_dict() -> Dictionary:
	return {"type": TYPE, "center": center, "radius": radius}


static func from_dict(data: Dictionary) -> IgniteCommand:
	return IgniteCommand.new(data.center, data.radius)
