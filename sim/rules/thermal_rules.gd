class_name ThermalRules
extends RefCounted
## Temperature relaxes toward ambient each tick; water freezes at or below
## freezing and ice melts above it. Only hot or cold cells (grid.heat_cells)
## are visited, in index order; ice elsewhere is at ambient and melts.


static func step(state: SimState) -> void:
	var grid := state.grid
	var ambient := SimMaterials.AMBIENT_TEMPERATURE
	var relax := SimMaterials.THERMAL_RELAX_PER_TICK
	if not grid.heat_cells.is_empty():
		grid.edit_heat()
		var cells: Array = grid.heat_cells.keys()
		cells.sort()
		for i: int in cells:
			var temp: int = grid.temperature[i]
			if temp > ambient:
				temp = maxi(temp - relax, ambient)
			elif temp < ambient:
				temp = mini(temp + relax, ambient)
			grid.set_temperature(i, temp)
			var t: int = grid.surface_type[i]
			if t == SimMaterials.Surface.WATER and temp <= SimMaterials.FREEZE_TEMPERATURE:
				grid.edit_surfaces()
				grid.surface_type[i] = SimMaterials.Surface.ICE
				state.emit_event(SimEvent.Type.FROZE, grid.coord(i))
			elif t == SimMaterials.Surface.ICE and temp > SimMaterials.FREEZE_TEMPERATURE:
				grid.edit_surfaces()
				grid.surface_type[i] = SimMaterials.Surface.WATER
				state.emit_event(SimEvent.Type.MELTED, grid.coord(i))

	if ambient > SimMaterials.FREEZE_TEMPERATURE and grid.no_ice_at != grid.surface_version and grid.has_any(SimGrid.FIELD_SURFACES):
		var ice := SimGrid.indices_of(grid.surface_type, [SimMaterials.Surface.ICE])
		if ice.is_empty():
			grid.no_ice_at = grid.surface_version  # ice only comes with a surface edit
		for i in ice:
			if grid.temperature[i] > SimMaterials.FREEZE_TEMPERATURE:
				grid.edit_surfaces()
				grid.surface_type[i] = SimMaterials.Surface.WATER
				state.emit_event(SimEvent.Type.MELTED, grid.coord(i))
