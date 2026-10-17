class_name SpawnSurfaceCommand
extends SimCommand
## Pours a surface material onto open cells in a horizontal disc around center.

const TYPE := "spawn_surface"

var center: Vector3i
var surface: int
var amount: int
var radius: int


func _init(
		p_center: Vector3i = Vector3i.ZERO,
		p_surface: int = SimMaterials.Surface.WATER,
		p_amount: int = SimMaterials.AMOUNT_FULL,
		p_radius: int = 0) -> void:
	center = p_center
	surface = p_surface
	amount = p_amount
	radius = p_radius


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	return (_is_open_cell(state, center)
			and surface > SimMaterials.Surface.NONE
			and surface < SimMaterials.Surface.size()
			and amount > 0
			and radius >= 0)


func execute(state: SimState) -> void:
	for c in state.grid.disc_cells(center, radius):
		state.grid.add_surface(c, surface, amount)


func to_dict() -> Dictionary:
	return {"type": TYPE, "center": center, "surface": surface, "amount": amount, "radius": radius}


static func from_dict(data: Dictionary) -> SpawnSurfaceCommand:
	return SpawnSurfaceCommand.new(data.center, data.surface, data.amount, data.radius)
