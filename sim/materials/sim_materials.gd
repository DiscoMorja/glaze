class_name SimMaterials
extends RefCounted
## Material definitions and tuning constants for the simulation.
## All values are integers (CLAUDE.md rule 4). Per-type tables are indexed by enum value.

enum Surface { NONE, WATER, OIL, ICE }
enum Gas { NONE, STEAM, SMOKE }

## Amount of liquid or gas considered one "full" cell.
const AMOUNT_FULL := 100

# Surfaces:                NONE   WATER  OIL    ICE
const _SURFACE_FLUID :=     [false, true,  true,  false]
const _SURFACE_FLAMMABLE := [false, false, true,  false]
## Divisor for horizontal spread per tick; higher = thicker liquid.
const _SURFACE_VISCOSITY := [1,     5,     8,     1]
## Below this amount a liquid stops spreading (it stays as a puddle).
const _SURFACE_MIN_SPREAD := [0,    4,     6,     0]

# Gases:                   NONE  STEAM  SMOKE
const _GAS_DECAY :=        [0,   2,     3]
const GAS_SPREAD_DIVISOR := 6
const GAS_MIN_SPREAD := 6

const AMBIENT_TEMPERATURE := 20
const FREEZE_TEMPERATURE := 0
const CHILL_TEMPERATURE := -60
const FIRE_TEMPERATURE := 200
## Temperature moves toward ambient by this much per tick.
const THERMAL_RELAX_PER_TICK := 1

const FIRE_MAX := 10
## Fire intensity lost per tick when there is no fuel.
const FIRE_DECAY := 2
const OIL_BURN_PER_TICK := 8
const SMOKE_PER_BURN_TICK := 12
## Water consumed and steam created when fire meets water.
const WATER_PER_EXTINGUISH := 20
const STEAM_PER_EXTINGUISH := 40


static func is_fluid(surface: int) -> bool:
	return _SURFACE_FLUID[surface]


static func is_flammable(surface: int) -> bool:
	return _SURFACE_FLAMMABLE[surface]


static func viscosity(surface: int) -> int:
	return _SURFACE_VISCOSITY[surface]


static func min_spread(surface: int) -> int:
	return _SURFACE_MIN_SPREAD[surface]


static func gas_decay(gas: int) -> int:
	return _GAS_DECAY[gas]
