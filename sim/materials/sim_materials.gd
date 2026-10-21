class_name SimMaterials
extends RefCounted
## Material definitions and tuning constants for the simulation.
## All values are integers (CLAUDE.md rule 4). Per-type tables are indexed by enum value.

## VINES: a tangle grown by Overgrowth: not a liquid, slows like oil, burns
## fast, frost kills it. POISON: tainted water (Blight): hurts whoever stands
## in it, flows like water, Rain washes it clean.
enum Surface { NONE, WATER, OIL, ICE, VINES, POISON }
## POISON gas is heavy: it creeps along the ground instead of rising, hurts
## whoever stands in it, and explodes when fire reaches it. DARKNESS (Shroud)
## is heavy too and lingers. Thick smoke and darkness block sight (SimLos).
enum Gas { NONE, STEAM, SMOKE, POISON, DARKNESS }

## Amount of liquid or gas considered one "full" cell.
const AMOUNT_FULL := 100

# Surfaces:                NONE   WATER  OIL    ICE    VINES  POISON
const _SURFACE_FLUID :=     [false, true,  true,  false, false, true]
const _SURFACE_FLAMMABLE := [false, false, true,  false, true,  false]
## Divisor for horizontal spread per tick; higher = thicker liquid.
const _SURFACE_VISCOSITY := [1,     5,     8,     1,     1,     5]
## Below this amount a liquid stops spreading (it stays as a puddle).
const _SURFACE_MIN_SPREAD := [0,    4,     6,     0,     0,     4]
## Puddles this deep or shallower stay put instead of creeping onto dry, flat
## ground. They still run off ledges, and deeper water (a pond) levels out.
const _SURFACE_HOLD :=      [0,    20,    24,    0,     0,     20]
## Fuel a burning cell uses up per tick (vines go up fast).
const _SURFACE_BURN :=      [0,    0,     2,     0,     4,     0]

# Gases:                   NONE  STEAM  SMOKE  POISON  DARKNESS
const _GAS_DECAY :=        [0,   2,     3,     2,      1]
const _GAS_RISES :=        [false, true, true, false, false]
## A rising gas this thick hangs where it is instead (a Smoke Bomb's cloud);
## it rises once it thins out. 0 = always rises.
const _GAS_HANGS_FROM :=   [0,   0,     30,    0,      0]
## A cell holding at least this much of the gas blocks sight (0 = never).
const _GAS_OBSCURES_FROM := [0,  0,     30,    0,      20]
## Damage at the start of a turn standing in poison (water or gas), and the
## fire damage of exploding poison gas to whoever is in or next to it.
const POISON_DAMAGE := 1
const EXPLOSION_DAMAGE := 5
const GAS_SPREAD_DIVISOR := 6
const GAS_MIN_SPREAD := 6

const AMBIENT_TEMPERATURE := 20
const FREEZE_TEMPERATURE := 0
const CHILL_TEMPERATURE := -60
const FIRE_TEMPERATURE := 200
## Temperature moves toward ambient by this much per tick.
const THERMAL_RELAX_PER_TICK := 1

## Fire lasts: while fuel remains (OIL_BURN_PER_TICK used per tick), then
## FIRE_MAX / FIRE_DECAY ticks dying down. A lit Oil Flask puddle (24 oil per
## cell) burns 12 + 12 = 24 ticks, three rounds; fire on bare ground 12 ticks.
const FIRE_MAX := 12
## Fire intensity lost per tick when there is no fuel.
const FIRE_DECAY := 1
const OIL_BURN_PER_TICK := 2
const SMOKE_PER_BURN_TICK := 4
## Water consumed and steam created when fire meets water.
const WATER_PER_EXTINGUISH := 20
const STEAM_PER_EXTINGUISH := 40


static func is_fluid(surface: int) -> bool:
	return _SURFACE_FLUID[surface]


static func is_flammable(surface: int) -> bool:
	return _SURFACE_FLAMMABLE[surface]


static func viscosity(surface: int) -> int:
	return _SURFACE_VISCOSITY[surface]


static func puddle_hold(surface: int) -> int:
	return _SURFACE_HOLD[surface]


static func min_spread(surface: int) -> int:
	return _SURFACE_MIN_SPREAD[surface]


static func gas_decay(gas: int) -> int:
	return _GAS_DECAY[gas]


static func gas_rises(gas: int, amount: int = 0) -> bool:
	return _GAS_RISES[gas] and (_GAS_HANGS_FROM[gas] == 0 or amount < _GAS_HANGS_FROM[gas])


static func obscures(gas: int, amount: int) -> bool:
	return _GAS_OBSCURES_FROM[gas] > 0 and amount >= _GAS_OBSCURES_FROM[gas]


static func burn_rate(surface: int) -> int:
	return _SURFACE_BURN[surface]
