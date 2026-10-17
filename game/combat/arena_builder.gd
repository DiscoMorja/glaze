class_name ArenaBuilder
extends RefCounted
## Greybox M1 arena: a bandit camp on a raised platform with oil barrels, an oil
## trail down the stairs, a flooded pit, and a wall to fight around. The Hexer
## casts Firebolt and Teleport, the Cutpurse steals, the Chief and Spearman shove. Floor is
## two cells thick, so the ground walk layer is y = 2 and the platform's is y = 4.

const SIZE := Vector3i(28, 6, 24)
const GROUND := 2
const PLATFORM := 4
const A := SimAbilities.Ability


static func build(seed_value: int = 1) -> SimState:
	var grid := SimGrid.new(SIZE)
	grid.fill_solid(Vector3i(0, 0, 0), Vector3i(SIZE.x - 1, 1, SIZE.z - 1))
	grid.fill_solid(Vector3i(9, 1, 14), Vector3i(14, 1, 19), false)  # pit
	grid.fill_solid(Vector3i(17, 2, 3), Vector3i(25, 3, 11))  # platform
	grid.fill_solid(Vector3i(15, 2, 6), Vector3i(16, 2, 8))  # stair step
	grid.fill_solid(Vector3i(9, 2, 4), Vector3i(9, 3, 10))  # wall

	var state := SimState.new(grid, seed_value)
	state.apply_command(SpawnSurfaceCommand.new(Vector3i(11, 1, 16), SimMaterials.Surface.WATER, 120, 2))
	for x in range(10, 15):
		state.apply_command(SpawnSurfaceCommand.new(Vector3i(x, GROUND, 7), SimMaterials.Surface.OIL, 20))

	var players := SimEntity.Faction.PLAYERS
	var enemies := SimEntity.Faction.ENEMIES
	var all := SimAbilities.all()

	state.add_entity(SimEntity.character("Ari", players, Vector3i(3, GROUND, 15), 20, "Sword", 4, [], all))
	state.add_entity(SimEntity.character("Bram", players, Vector3i(4, GROUND, 17), 24, "Axe", 5, [], all))
	state.add_entity(SimEntity.character("Cel", players, Vector3i(2, GROUND, 18), 16, "Dagger", 3, [], all))
	state.add_entity(SimEntity.character("Dov", players, Vector3i(5, GROUND, 19), 16, "Staff", 2, [], all))

	# Enemies get a few verbs each, and the AI uses them on the same rules.
	state.add_entity(SimEntity.character("Chief", enemies, Vector3i(22, PLATFORM, 7), 24, "Greataxe", 6, ["Camp key"], [A.SHOVE]))
	state.add_entity(SimEntity.character("Hexer", enemies, Vector3i(24, PLATFORM, 9), 12, "Staff", 2, [], [A.FIREBOLT, A.TELEPORT]))
	state.add_entity(SimEntity.character("Cutpurse", enemies, Vector3i(19, PLATFORM, 5), 12, "Club", 3, ["Gold"], [A.STEAL]))
	state.add_entity(SimEntity.character("Bandit", enemies, Vector3i(19, PLATFORM, 9), 12, "Club", 3))
	state.add_entity(SimEntity.character("Spearman", enemies, Vector3i(13, GROUND, 9), 12, "Spear", 4, [], [A.SHOVE]))

	state.add_entity(SimEntity.barrel("Oil barrel", Vector3i(21, PLATFORM, 6), SimMaterials.Surface.OIL, 150))
	state.add_entity(SimEntity.barrel("Oil barrel", Vector3i(21, PLATFORM, 8), SimMaterials.Surface.OIL, 150))
	state.add_entity(SimEntity.barrel("Oil barrel", Vector3i(13, GROUND, 11), SimMaterials.Surface.OIL, 120))
	state.add_entity(SimEntity.barrel("Water barrel", Vector3i(6, GROUND, 14), SimMaterials.Surface.WATER, 150))

	state.apply_command(StartCombatCommand.new())
	return state
