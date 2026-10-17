class_name SpawnGasCommand
extends SimCommand
## Releases gas into open cells in a horizontal disc around center.

const TYPE := "spawn_gas"

var center: Vector3i
var gas: int
var amount: int
var radius: int


func _init(
		p_center: Vector3i = Vector3i.ZERO,
		p_gas: int = SimMaterials.Gas.STEAM,
		p_amount: int = SimMaterials.AMOUNT_FULL,
		p_radius: int = 0) -> void:
	center = p_center
	gas = p_gas
	amount = p_amount
	radius = p_radius


func get_type() -> String:
	return TYPE


func validate(state: SimState) -> bool:
	return (_is_open_cell(state, center)
			and gas > SimMaterials.Gas.NONE
			and gas < SimMaterials.Gas.size()
			and amount > 0
			and radius >= 0)


func execute(state: SimState) -> void:
	for c in state.grid.disc_cells(center, radius):
		state.grid.add_gas(c, gas, amount)


func to_dict() -> Dictionary:
	return {"type": TYPE, "center": center, "gas": gas, "amount": amount, "radius": radius}


static func from_dict(data: Dictionary) -> SpawnGasCommand:
	return SpawnGasCommand.new(data.center, data.gas, data.amount, data.radius)
