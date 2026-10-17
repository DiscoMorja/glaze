class_name ThermalRules
extends RefCounted
## Temperature relaxes toward ambient each tick; water freezes at or below
## freezing and ice melts above it.


static func step(state: SimState) -> void:
	var grid := state.grid
	var temps := grid.temperature
	var types := grid.surface_type
	var ambient := SimMaterials.AMBIENT_TEMPERATURE
	var relax := SimMaterials.THERMAL_RELAX_PER_TICK

	for i in grid.cell_count:
		var temp: int = temps[i]
		if temp > ambient:
			temp = maxi(temp - relax, ambient)
		elif temp < ambient:
			temp = mini(temp + relax, ambient)
		temps[i] = temp

		var t: int = types[i]
		if t == SimMaterials.Surface.WATER and temp <= SimMaterials.FREEZE_TEMPERATURE:
			types[i] = SimMaterials.Surface.ICE
			state.emit_event(SimEvent.Type.FROZE, grid.coord(i))
		elif t == SimMaterials.Surface.ICE and temp > SimMaterials.FREEZE_TEMPERATURE:
			types[i] = SimMaterials.Surface.WATER
			state.emit_event(SimEvent.Type.MELTED, grid.coord(i))
