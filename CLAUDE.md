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
- In game, ` shows the perf readout and logs every frame over 25 ms with what the script spent in it (an empty list means the engine). Godot-ai screenshots cause ~60 ms frames themselves. Exploring walk routes are searched a few ms per frame (`RouteSearches`, `SimPathSearch`) and carried in the command; keep per-tick sim work proportional to what changed (`SimGrid.surface_version` lets settled liquids and renderers skip).

## Running tests

Run the sim tests headless (GUT 9.7.1, config in `.gutconfig.json`) after every sim change:

```bash
/c/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s addons/gut/gut_cmdln.gd
```

Leak/RID errors printed after "All tests passed!" are engine shutdown noise.

Don't run `--import` headless while the editor is open: it rewrites the class cache under the editor and the editor's class list goes stale. If the editor reports `Identifier "SomeSimClass" not declared` for a class that exists, touch the scripts and run `filesystem_manage(op="scan")`, or restart the editor.

## Scenes & levels

- `res://game/menu/main_menu.tscn` (main scene): Solo / Host / Join. Command line (after `--`): `--solo`, `--host`, `--join=ADDRESS`, `--level=slice|start|arena|highlands`, `--autoready`. To test co-op alone, start a host from a terminal with `--host --level=arena --autoready` and join from the editor run.
- `res://game/world/vertical_slice.tscn`: the main world, `levels/vertical_slice` (320 × 256 m, from the developer's paper sketches): the village with docks on the east coast (the party lands on the quay), forest north and centre, the bandit camp west, hills south, mountain passes north, a hidden shore north-west. A first block-out: buildings are CSG boxes, trees are `game/props/tree.tscn` instances; reshape and repaint it in the editor.
- `res://game/world/world.tscn`: explore `levels/start_area` (the small test level) in real time; combat starts on sight or hostility. Same controller as the arena (`game/combat/combat_arena.gd`, controls in its header) with `level_scene` set. P cycles the retro looks — off, early 2000s, PSX (`game/render/retro/retro_look.gd`, tuned in its STYLES; `retro_style` exports the start style).
- `res://game/world/highlands.tscn`: stress test — the same controller on `levels/highlands` (256 × 256 m, big height differences, 32 enemy packs), with `log_perf` printing the perf readout every 2 s.
- `res://game/combat/combat_arena.tscn`: same controller on `levels/arena` (a level with `start_in_combat`), straight into a fight.
- Levels (`levels/<name>/<name>.tscn`, root script `GameLevel`): Terrain3D ground (collision layer 2), structures with collision on layer 1, and `LevelSpawn` / `LevelBarrel` / `LevelContainer` / `LevelSurface` markers. Items are the catalog in `sim/items/sim_items.gd`; give new verbs a property there, never check item names. New abilities and items need an icon in `game/ui/icons/` (`ability_<name>.svg` / `item_<name>.svg`, lower case, spaces to `_`, apostrophes dropped, 64×64; `tests/ui/test_action_bar.gd` checks they exist). The UI is laid out for a 1280×720 base and scales with the window. All windows share one look: `UiStyle` (theme on the root window, `window_style()`, `title()`, `button()`) and `ItemSlot` for every item grid (icon, corner number, borders, `ItemSlot.details()` text). New windows use those instead of their own styles. Buildings you can enter are a root CSG with an `Inside` subtraction open to the top, a `Door` subtraction at least 2 m wide (narrower doors can bake shut on the 1 m grid), walls at least 0.2 m thick (the bake samples each cell every 0.2 m) and a `Roof` child: `BuildingCutaway` takes the roof off and cuts the walls to 1 m stubs while one of your characters is inside, and picking looks past the cut part. Fog of war: `ExplorationRules` marks explored 2 m tiles in `SimState.explored`; `FogOfWar` (game/render) draws it as a screen pass, hides characters out of sight (`FogOfWar.shows()`) and skips drawing level structures and trees on unexplored ground. Group enemy markers under one node per pack (they fight together). `GameLevel.bake()` builds the sim grid at load; use `WorldSpace` (not raw `c.y`) to turn cells into world positions. Nothing about the world is built in code: terrain is sculpted/painted/foliage-scattered with Terrain3D's editor tools, and each level scene owns its WorldEnvironment and Sun. Don't add generator scripts for level content. Shared terrain textures live in `levels/shared/terrain/` (CC0, see its LICENSE.txt).
- `res://game/debug/sim_debug.tscn`: material sim sandbox on `levels/arena` (real-time ticking, paint water/oil/fire/chill/steam; characters ignored).

## Written content

Dialogue (`game/data/dialogue/*.dlg`) and quests (`game/data/quests/*.quest`) are plain text, loaded by `Content.load_all()` into `SimDialogue` / `QuestRules`; the format is documented at the top of `sim/dialogue/sim_dialogue.gd` and `sim/quests/quest_rules.gd` (GDD §6.1). NPCs point at a knot with `LevelSpawn.dialogue`. New data folders must be added to the export preset's include filter. `tests/sim/test_dialogue.gd` fails on parse errors in the shipped content.

## Co-op (net/)

- `NetSession` (autoload `Net`) is the only way game code changes the sim: `Net.submit(command)` for player actions, `Net.submit_ai()` for enemies (host), `Net.host_tick()` for real time (host), `Net.set_ready()` for End Turn. The controller plays `Net.op_received` in order; never call `state.apply_command()` from game code outside that playback.
- Solo is a host without a guest, through the same path.
- With a guest connected, ops carry checksums (commands: everything but the grid; turn ends and every 16th tick: the grid too, which costs 100+ ms on big levels). Keep the sim deterministic (rule 5) or guests will resync constantly.

## Saves

Saves are `SimState.to_snapshot()` plus a header (`game/save/save_store.gd`, GDD §8.5.2). Anything the sim must remember belongs in `SimState` and its snapshot, nowhere else. New entity/combat/state fields: read them with `data.get(key, default)` in `from_dict`/`from_snapshot` and old saves keep loading. A rename, a changed meaning or a new grid array: bump `SimState.SNAPSHOT_VERSION`, add the step to `SimState._migrate()`, and write the new fixture with `tools/make_snapshot_fixture.gd` (never overwrite an old one; `tests/sim/test_save_format.gd` loads them all).

## Builds

`bash tools/export_windows.sh` exports `build/windows/glaze.exe` and `build/glaze-windows.zip` (git-ignored). Needs the Godot 4.7.2 export templates (Editor → Manage Export Templates). `docs/PLAYTEST.md` ships in the zip as the players' connection guide.

## Third-party assets

`assetlibs/` holds licensed asset packs and is git-ignored, so it only exists on machines it was copied to. Code must keep working without it.

- **BinbunVFX_Vol2** (`assetlibs/BinbunVFX_Vol2/`): effects used through `game/vfx/pack_vfx.gd`, which falls back to the procedural `VfxFactory` effects when the pack is missing. After copying a fresh pack in, run `bash tools/fix_binbun_vfx.sh` (it rewrites the pack's `res://assets/...` paths and drops stale UID hints), then rescan in the editor. Keep a single copy of the pack.

- **Characters and Weapons** (`assetlibs/Characters/`, `assetlibs/Weapons/`): placeholder models for party, enemies and townsfolk, and weapon models held in hand. `game/render/character_looks.gd` maps looks (`LevelSpawn.look`, or picked by side/role) to rigs, meshes and animations, and weapon items to models; `CharacterModel` builds and animates them; capsules are the fallback. The modular characters need `human_*_rigged.glb`, made with `tools/rig_modular_characters.py` in Blender (the pack's armour/heads/hair aren't bound to the armature). `game/debug/look_viewer.tscn` shows every look and animation (X cycles the hand axis for tuning).

## Tools

- The godot-ai MCP addon is installed — use it to inspect scenes, run the game and read logs.
- Co-op testing: multiple run instances (Debug → Customize Run Instances).
