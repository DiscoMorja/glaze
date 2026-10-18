# CLAUDE.md

glaze — a Divinity-inspired, systemic, online co-op, turn-based party RPG. Godot 4.7 (Forward+, Jolt), **GDScript only**.

**Read [docs/GDD.md](docs/GDD.md) before design or architecture work.** It is the source of truth for vision, pillars, scope and decisions. If a task conflicts with the GDD, stop and ask. When a decision changes, update the GDD and its Decision Log.

## Working context

- Solo developer, ~6–8 h/week. Claude Code writes all code; the developer designs, reviews and playtests.
- Prefer small, verifiable changes. Every sim change ships with tests.
- Scope is a Prologue (see GDD §3). Do not add systems, content or abstractions beyond the task.

## Architecture rules (non-negotiable)

1. **The simulation is engine-independent.** Code in `sim/` uses only `RefCounted` classes, Packed arrays, ints and integer vectors (`Vector2i`/`Vector3i`). No `Node`, no SceneTree, no rendering, physics, input, signals-to-nodes, or autoload access. It must run headless.
2. **All actions are commands.** Every player/AI action (`MoveTo`, `CastSpell`, `Pickpocket`, `UseItem`…) is a serializable command object applied to sim state. Single-player is a host with no clients. Never mutate sim state directly from UI or game code.
3. **The host is authoritative.** Clients send commands; the host validates and executes them, then broadcasts deltas and events. Clients may run previews on a local replica but never commit authoritative state.
4. **Rules use integers.** No floats in sim logic — use ints or fixed-point. Floats are fine in the `game/` presentation layer only.
5. **Deterministic.** Seeded RNG owned by sim state (never global `randf()`/`randi()`). No dependence on frame time, node order, physics results or unordered iteration inside rules.
6. **The sim emits events; presentation reacts.** VFX, audio and narration consume the sim event stream. The sim never knows about presentation.
7. **Data-oriented grid.** Structure-of-arrays (one Packed array per cell field, flat index `x + z*w + y*w*d`, y up — see `SimGrid.index()`). No per-cell objects. Process only active/dirty cells.
8. **Outcomes, not methods.** Quests and objectives are predicates over world facts, never step scripts.
9. **Properties, not types.** Verbs act on object properties (mass, material, flammable, conductive…), never on specific item/unit types.

## Layout

```
sim/      pure simulation (grid, materials, objects, commands, facts, AI)
game/     scenes, rendering of sim state, input → commands, UI, VFX, audio
net/      networking glue (ENet, command transport, replication)
tests/    GUT unit tests for sim/
docs/     GDD and design docs
addons/   third-party plugins (godot_ai, GUT)
```

## Conventions

- GDScript style: static typing everywhere (`var x: int`, typed arrays, return types). `class_name` for sim types.
- snake_case files and functions, PascalCase classes.
- Keep sim classes small and testable; prefer pure functions for rules.
- Grid copies are copy-on-write: before writing a `SimGrid` array call its `edit_*()` (then re-read the array), and write fire/temperature with `set_fire()` / `set_temperature()`. A direct write to a shared array silently corrupts previews or the authoritative state.
- Performance: profile before optimizing. GDExtension porting is a later escape hatch, not a default.

## Running tests

Run the sim tests headless (GUT 9.7.1, config in `.gutconfig.json`) after every sim change:

```bash
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s addons/gut/gut_cmdln.gd
```

Leak/RID errors printed after "All tests passed!" are engine shutdown noise.

Don't run `--import` headless while the editor is open: it rewrites the class cache under the editor and the editor's class list goes stale. If the editor reports `Identifier "SomeSimClass" not declared` for a class that exists, touch the scripts and run `filesystem_manage(op="scan")`, or restart the editor.

## Scenes & levels

- `res://game/world/world.tscn` (main scene): explore `levels/start_area` in real time; combat starts on sight or hostility. Same controller as the arena (`game/combat/combat_arena.gd`, controls in its header) with `level_scene` set. P cycles the retro looks — off, early 2000s, PSX (`game/render/retro/retro_look.gd`, tuned in its STYLES; `retro_style` exports the start style).
- `res://game/world/highlands.tscn`: stress test — the same controller on `levels/highlands` (256 × 256 m, big height differences, 32 enemy packs), with `log_perf` printing the perf readout every 2 s.
- `res://game/combat/combat_arena.tscn`: same controller on `levels/arena` (a level with `start_in_combat`), straight into a fight.
- Levels (`levels/<name>/<name>.tscn`, root script `GameLevel`): Terrain3D ground (collision layer 2), structures with collision on layer 1, and `LevelSpawn` / `LevelBarrel` / `LevelSurface` markers. Group enemy markers under one node per pack (they fight together). `GameLevel.bake()` builds the sim grid at load; use `WorldSpace` (not raw `c.y`) to turn cells into world positions. Nothing about the world is built in code: terrain is sculpted/painted/foliage-scattered with Terrain3D's editor tools, and each level scene owns its WorldEnvironment and Sun. Don't add generator scripts for level content. Shared terrain textures live in `levels/shared/terrain/` (CC0, see its LICENSE.txt).
- `res://game/debug/sim_debug.tscn`: material sim sandbox on `levels/arena` (real-time ticking, paint water/oil/fire/chill/steam; characters ignored).

## Third-party assets

`assetlibs/` holds licensed asset packs and is git-ignored, so it only exists on machines it was copied to. Code must keep working without it.

- **BinbunVFX_Vol2** (`assetlibs/BinbunVFX_Vol2/`): effects used through `game/vfx/pack_vfx.gd`, which falls back to the procedural `VfxFactory` effects when the pack is missing. After copying a fresh pack in, run `bash tools/fix_binbun_vfx.sh` (it rewrites the pack's `res://assets/...` paths and drops stale UID hints), then rescan in the editor. Keep a single copy of the pack.

## Tools

- The godot-ai MCP addon is installed — use it to inspect scenes, run the game and read logs.
- Co-op testing: multiple run instances (Debug → Customize Run Instances).
