class_name GameLevel
extends Node3D
## A handcrafted level: Terrain3D ground, structures with collision, and
## marker nodes for characters, barrels, containers and surfaces. Everything is edited in
## the scene; nothing about the world is built in code. Each level also owns
## its WorldEnvironment and lights. bake() turns it into the
## sim's world: a SimGrid plus entities.
##
## How the grid is built (1 m cells, origin at the level's corner, y up):
##   - Terrain columns: cells below round(terrain height) are solid, so the walk
##     layer follows the ground in 1 m steps; WorldSpace keeps the real height
##     for drawing.
##   - Structures (anything with collision on layer 1, e.g. CSG with collision):
##     inside their bounds, vertical rays find where surfaces are crossed; a
##     sample point with an odd number of crossings above it is inside, and a
##     cell with any inside sample is solid. Structures need closed meshes. Put
##     Terrain3D's collision on another layer so it is not probed.

## Cells in x, y (height) and z.
@export var grid_size := Vector3i(64, 12, 64)
## Physics layers probed as structures.
@export_flags_3d_physics var structure_layers := 1
## Start the level in turn-based combat (an arena) instead of exploring.
@export var start_in_combat := false

## Where the vertical sample lines run inside each 1 m column: a 5 x 5 grid
## 0.2 m apart, so a wall at least 0.2 m thick always crosses a line (two
## lines 0.5 m apart let 0.3 m walls slip between them and leave holes). The
## grid is shifted off round numbers so no line runs along an authored face
## (a ray grazing a face reports stray crossings).
const SAMPLE_STEPS := [0.1137, 0.3137, 0.5137, 0.7137, 0.9137]
const MAX_CROSSINGS := 16
static var SAMPLE_OFFSETS: Array[Vector2] = _sample_offsets()


static func _sample_offsets() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for z: float in SAMPLE_STEPS:
		for x: float in SAMPLE_STEPS:
			result.append(Vector2(x, z))
	return result


## Builds the sim state for this level. Waits for physics so structure
## collision exists. Also tells WorldSpace about the terrain.
## Most liquid steps the bake runs to let placed liquids come to rest.
const LIQUID_SETTLE_STEPS := 400


func bake(seed_value: int = 1) -> SimState:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var grid := SimGrid.new(grid_size)
	_bake_terrain(grid)
	_bake_structures(grid)
	var state := SimState.new(grid, seed_value)
	_place_markers(state)
	# Ponds and puddles placed by markers flow into place now, so the world
	# starts calm instead of spending its first ticks spreading them.
	LiquidRules.settle(state, LIQUID_SETTLE_STEPS)
	ExplorationRules.step(state)  # the party sees where it starts
	state.drain_events()
	if start_in_combat:
		state.apply_command(StartCombatCommand.new())
	return state


func _bake_terrain(grid: SimGrid) -> void:
	var terrain := _terrain()
	var columns := grid_size.x * grid_size.z
	var heights := PackedFloat32Array()
	var floors := PackedInt32Array()
	heights.resize(columns)
	floors.resize(columns)
	floors.fill(-1)
	if terrain == null:
		WorldSpace.clear()
		return
	var data: Object = terrain.get("data")
	for z in grid_size.z:
		for x in grid_size.x:
			var h: float = data.call("get_height", Vector3(x + 0.5, 0.0, z + 0.5))
			if is_nan(h):
				continue
			var top := clampi(roundi(h), 0, grid_size.y - 1)
			if top > 0:
				grid.fill_solid(Vector3i(x, 0, z), Vector3i(x, top - 1, z))
			heights[x + z * grid_size.x] = maxf(h, 0.0)
			floors[x + z * grid_size.x] = top
	var corners := PackedFloat32Array()
	corners.resize((grid_size.x + 1) * (grid_size.z + 1))
	for z in grid_size.z + 1:
		for x in grid_size.x + 1:
			var h: float = data.call("get_height", Vector3(x, 0.0, z))
			corners[x + z * (grid_size.x + 1)] = 0.0 if is_nan(h) else maxf(h, 0.0)
	WorldSpace.set_terrain(Vector2i(grid_size.x, grid_size.z), heights, floors, corners)
	var heights_cm := PackedInt32Array()
	heights_cm.resize(columns)
	for i in columns:
		heights_cm[i] = roundi(heights[i] * 100.0)
	grid.set_terrain(floors, heights_cm)


func _bake_structures(grid: SimGrid) -> void:
	var space := get_world_3d().direct_space_state
	grid.edit_solid()
	for bounds in _structure_bounds():
		var lo := Vector3i(floori(bounds.position.x), floori(bounds.position.y), floori(bounds.position.z))
		var hi := Vector3i(ceili(bounds.end.x), ceili(bounds.end.y), ceili(bounds.end.z))
		var bottom := bounds.position.y - 1.0
		var top := bounds.end.y + 1.0
		for z in range(maxi(lo.z, 0), mini(hi.z, grid_size.z)):
			for x in range(maxi(lo.x, 0), mini(hi.x, grid_size.x)):
				# A grid of vertical sample lines per column catches walls thinner than a cell.
				var lines: Array[PackedFloat32Array] = []
				for offset: Vector2 in SAMPLE_OFFSETS:
					lines.append(_crossings(space, Vector2(x + offset.x, z + offset.y), bottom, top))
				for y in range(maxi(lo.y, 0), mini(hi.y, grid_size.y)):
					if _cell_inside(lines, y):
						grid.solid[grid.index(Vector3i(x, y, z))] = 1


## Heights where a vertical line crosses structure surfaces. Rays only report
## faces they enter through, so one pass goes up (finding undersides) and one
## goes down (finding tops); together they are every crossing.
func _crossings(space: PhysicsDirectSpaceState3D, at: Vector2, bottom: float, top: float) -> PackedFloat32Array:
	var result := _pass(space, at, bottom, top)
	result.append_array(_pass(space, at, top, bottom))
	return result


func _pass(space: PhysicsDirectSpaceState3D, at: Vector2, from_y: float, to_y: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var step := 0.001 if to_y > from_y else -0.001
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = structure_layers
	for _i in MAX_CROSSINGS:
		query.from = Vector3(at.x, from_y, at.y)
		query.to = Vector3(at.x, to_y, at.y)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		result.append(hit.position.y)
		from_y = hit.position.y + step
	return result


## A cell is solid if any of its sample points (each line at two heights) is
## inside a structure: an odd number of crossings above the point.
static func _cell_inside(lines: Array[PackedFloat32Array], y: int) -> bool:
	for crossings in lines:
		for sample_y: float in [y + 0.25, y + 0.75]:
			var above := 0
			for h in crossings:
				if h > sample_y:
					above += 1
			if above % 2 == 1:
				return true
	return false


## World bounds of every visual with collision on the structure layers.
func _structure_bounds() -> Array[AABB]:
	var result: Array[AABB] = []
	for node in find_children("*", "CSGShape3D", true, false):
		var csg := node as CSGShape3D
		if csg.use_collision and csg.is_root_shape() and (csg.collision_layer & structure_layers) != 0:
			result.append(csg.global_transform * csg.get_aabb())
	for node in find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if (body.collision_layer & structure_layers) == 0:
			continue
		for child in body.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			result.append(mesh.global_transform * mesh.get_aabb())
	return result


func _place_markers(state: SimState) -> void:
	for node in find_children("*", "LevelSurface", true, false):
		var marker := node as LevelSurface
		var r := marker.radius
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dz * dz > r * r:
					continue
				var floor_cell: Variant = _floor_cell(state, marker.global_position + Vector3(dx, 0, dz))
				if floor_cell != null:
					state.grid.add_surface(floor_cell, marker.surface(), marker.amount)
	var packs := {}
	for node in find_children("*", "LevelSpawn", true, false):
		var spawn := node as LevelSpawn
		var cell: Variant = _floor_cell(state, spawn.global_position)
		if cell == null:
			push_warning("Spawn %s is outside the level or has no floor" % spawn.name)
			continue
		var inventory: Array[String] = []
		inventory.assign(spawn.inventory)
		var e := SimArchetypes.make(spawn.role, spawn.entity_name if spawn.entity_name != "" else SimArchetypes.title(spawn.role), spawn.faction(), cell, inventory)
		if e.faction == SimEntity.Faction.PLAYERS:
			e.owner = spawn.player
		e.facing = spawn.facing()
		e.home_facing = e.facing
		e.group = spawn.group_name()
		e.dialogue = spawn.dialogue
		e.gold = spawn.gold
		e.model = spawn.look
		for item in spawn.equipment:
			var slot := EquipRules.default_slot(e, item)
			if slot == "":
				push_warning("%s can't wear %s" % [spawn.name, item])
			else:
				EquipRules.put(e, slot, item)
		e.trader = spawn.trades
		var pack_name := spawn.pack_name()
		if pack_name != "":
			if not packs.has(pack_name):
				packs[pack_name] = packs.size() + 1
			e.pack = packs[pack_name]
		state.add_entity(e)
	for node in find_children("*", "LevelContainer", true, false):
		var box := node as LevelContainer
		var cell: Variant = _floor_cell(state, box.global_position)
		if cell == null:
			push_warning("Container %s is outside the level or has no floor" % box.name)
			continue
		var items: Array[String] = []
		items.assign(box.items)
		var chest := SimEntity.container(box.display_name, cell, items, box.key, box.hp)
		chest.model = box.look
		chest.group = box.group_name()
		var pack_name := box.pack_name()
		if pack_name != "":
			if not packs.has(pack_name):
				packs[pack_name] = packs.size() + 1
			chest.pack = packs[pack_name]
		state.add_entity(chest)
	for node in find_children("*", "LevelBarrel", true, false):
		var barrel := node as LevelBarrel
		var cell: Variant = _floor_cell(state, barrel.global_position)
		if cell != null:
			state.add_entity(SimEntity.barrel(barrel.display_name(), cell, barrel.surface(), barrel.amount))


## The walkable cell under a marker: the highest open, supported cell in its
## column at or below the marker (markers above a roof land on the roof).
func _floor_cell(state: SimState, at: Vector3) -> Variant:
	var x := floori(at.x)
	var z := floori(at.z)
	var start := clampi(ceili(at.y), 0, grid_size.y - 1)
	if at.y <= 0.0 or start == 0:
		start = grid_size.y - 1
	for y in range(start, -1, -1):
		var c := Vector3i(x, y, z)
		if state.grid.in_bounds(c) and not state.grid.is_solid(c) and state.grid.is_supported(c):
			return c
	return null


func _terrain() -> Node3D:
	for child in find_children("*", "Terrain3D", true, false):
		return child as Node3D
	return null
