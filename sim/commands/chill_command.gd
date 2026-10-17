class_name ChillCommand
extends SimCommand
## Drops temperature in a horizontal disc around center and puts out fire there.
## Freezing water into ice is left to ThermalRules.

const TYPE := "chill"

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
		grid.temperature[i] = mini(grid.temperature[i], SimMaterials.CHILL_TEMPERATURE)
		if grid.fire[i] > 0:
			grid.fire[i] = 0
			state.emit_event(SimEvent.Type.EXTINGUISHED, c)


func to_dict() -> Dictionary:
	return {"type": TYPE, "center": center, "radius": radius}


static func from_dict(data: Dictionary) -> ChillCommand:
	return ChillCommand.new(data.center, data.radius)
