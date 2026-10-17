# glaze — Game Design Document

Living document. Update it when a decision changes; record the change in the Decision Log at the bottom.

---

## 1. Vision

A top-down 3D, turn-based party RPG for online co-op, inspired by Divinity: Original Sin 1 & 2 — but built around **systems, not content volume**.

The fun we are chasing is the systemic moments those games produce: elemental and liquid interactions, moving any object in the world, pickpocketing and abusing systems, and setting up an encounter before it begins. We do not copy Divinity's mechanics; we keep what makes them fun and push further where a solo developer can win: simulation depth instead of content breadth.

**North-star goal:** a Prologue / Act 1 that the developer and their partner — veterans of thousands of hours of Divinity and Baldur's Gate — play together online and have a blast.

### Elevator pitch

> A handcrafted co-op tactics RPG where the world is a deterministic material simulation. Explore in real time, fight in turns. Every quest checks outcomes, not methods — systems are always a valid solution.

---

## 2. Design Pillars

1. **The world is the weapon.** Verbs act on the world, not just on enemies. Oil, water, gas, heat, height and mass are tools.
2. **Same rules for everyone.** Enemies, allies, NPCs, animals and furniture all obey the same simulation. Fairness makes chaos funny instead of cheap.
3. **Deterministic rules, chaotic chain reactions.** Every rule is predictable and previewable; the *combinations* produce surprise.
4. **Outcomes, not methods.** Quests and objectives check world state. Pickpocket, teleport, burn, bribe or kill — all valid.
5. **Readable chaos.** The player can always read the board. If a situation can't be understood, it isn't fun — fix the readability, don't cut the system.
6. **Better together.** Co-op is the default way to play. Systems should reward splitting up, coordinating and occasionally betraying each other.

### What we learned from Divinity (and want to improve)

| Divinity strength | Keep | Divinity weakness | Our answer |
|---|---|---|---|
| World-reactive verbs | Yes | Late-game surface clutter, unreadable boards | Surfaces decay, limited states per cell, strong previews and overlays |
| Same rules for all | Yes | Armor system blocks CC → kills creativity | Do not gate systemic effects behind armor pools |
| Pre-combat setup | Yes, as real-time exploration | Dominant combos (rain + lightning) | Varied encounter gimmicks, enemy counters, objectives beyond "kill all" |
| "Break the game" permission | Yes | Long, slow fights | Smaller encounters, fewer but deeper verbs, objective-based fights |
| Elemental combos | Yes | Surfaces are flat 2D decals | Volumetric sim with height: liquids flow, gas rises and drifts |

---

## 3. Scope

- **Solo developer, ~6–8 hours/week.** All code is written by Claude Code; the developer designs, directs, reviews, builds levels, writes, and playtests.
- **Target: Prologue / Act 1** playable in co-op within ~12–18 months.

| Content | Prologue target |
|---|---|
| Zones | 1 hub + 1 zone |
| Bespoke encounters | 5–6, each with a memorable gimmick |
| Quests & events | 8–12 (fact-driven) |
| Player characters | 4 (2 per player), lightly-written origins |
| Named NPCs with dialogue | ~10–20 |
| Playtime | 2–3 hours co-op |

Grow toward a fuller Act 1 only after the Prologue proves fun.

**Scope rules**
- No new system until the existing ones are fun.
- Fewer verbs, each deep. Every verb must interact with materials.
- Art is stylized low-poly using asset packs (Quaternius, Kenney, Synty) and shared humanoid rig + Mixamo animations.

---

## 4. Core Loop

```
Explore (real time) ──► interact with world, scheme, steal, set up ──► combat triggers
        ▲                                                                   │
        │                                                                   ▼
   consequences ◄── quest facts updated ◄── resolve (turn-based) ◄── fight with your setup
```

- **Exploration (real time):** move freely, talk, loot, pickpocket, sneak, move objects, prepare surfaces. This *is* the "prep phase" — there is no separate planning mode. The sim ticks live (4 Hz); characters walk the sim grid one cell per tick (paths around hazards, re-routing around anyone in the way). Right-click walks the party, the others following to the nearest free cells. Abilities need no AP outside combat, but cooldowns still run (8 ticks = one turn).
- **Combat (turn-based):** starts when hostility is triggered: an enemy with sight (6 cells for enemy roles) sees a party member with line of sight, or someone hurts a fighter of the other side. Preparing the ground (oil, water, moving barrels) does not. Enemy sight areas are tinted red while exploring. Everyone fights from their current positions, so exploration setup carries directly into combat; after a win the world goes back to real time.
- **Transition (v1):** when combat starts, the **whole world switches to turn-based** and all players join. (Divinity/BG3 allow split real-time/turn-based; deferred — see Open Questions.)

---

## 5. Systems

### 5.1 World Grid & Material Simulation

- **Square grid**, fine resolution (start at **1 m cells**, tunable), with **height levels**. The grid is mostly invisible; it drives simulation, not movement visuals.
- Square was chosen over hex because handcrafted 3D architecture (walls, doors, corridors, rooms) is rectangular. Circular area masks and 8-neighbour spreading hide square artifacts.

**Cell model (per cell)**
- **Ground layer:** liquid/surface material (water, oil, blood, poison, ice, mud…) + amount/depth.
- **Volume layer:** gas/cloud (steam, smoke, poison gas…) + density.
- **Temperature** (integer).
- **Fire** intensity (integer, 0 = none).
- **Charge** (electrified, integer duration).
- **Solid/occupancy:** blocked, object references.

**Behaviour**
- Liquids flow downhill and pool by depth.
- Gases rise and drift (wind is a zone/encounter parameter).
- Fire spreads along fuel; heat accumulates and transfers.
- States decay over time to avoid board clutter.

**Starter interaction table (draft, to be tuned)**

| A | B | Result |
|---|---|---|
| Fire | Oil | Burning oil surface, spreads |
| Fire | Water | Steam cloud, fire out |
| Cold | Water | Ice (slippery) |
| Fire | Ice | Water |
| Lightning | Water | Electrified water (stun on contact) |
| Lightning | Steam | Electrified cloud |
| Fire | Poison gas | Explosion |
| Water | Fire (on unit) | Extinguish |

### 5.2 Object Model — "Everything is an object"

Characters, barrels, chairs, doors, chests and potions share **one property model**:

- mass, material, flammable, conductive, wet, frozen, contents, owner, faction, hp/durability.

**Spells and verbs act on properties, never on types.** Teleport moves *anything* under a mass limit; freeze works on any liquid — including the potion in an enemy's pocket. New items cost one data entry; combinations emerge for free.

### 5.3 Verbs

| Verb | AP | Range | Notes |
|---|---|---|---|
| Firebolt | 2 | 7 | 4 damage and ignites the target cell |
| Rain | 2 | 7 | Water in a radius; douses fire (makes steam) |
| Teleport | 2 | 7 | Moves any entity under the mass limit to a free cell in sight; drop it from height or into fire |
| Shove | 1 | adjacent | Pushes 2 cells; walls and bodies hurt, ledges drop |
| Steal | 1 | adjacent | Takes an enemy's weapon, otherwise an item. Player characters can't be disarmed |
| Frost | 2 | 6 | Chills a radius: freezes water to ice now, puts out fire, 2 damage |
| Oil Flask | 1 | 6 | Oil in a radius, ready to be lit |
| Mend | 2 | 5 | Heals 6 (self or others) |
| Cleave | 2 | adjacent | Weapon hit on everything adjacent, allies included |
| Blink | 1 | 4 | Caster jumps to a free cell in sight |

Ranged verbs need line of sight. Every verb except Attack has a **cooldown** in combat: the number of the user's turns until it is ready again (Firebolt and Shove once per turn; Rain, Steal, Frost, Oil Flask, Cleave and Blink every 2 turns; Teleport and Mend every 3). Cooldowns count down at the start of the user's side turn and don't apply outside combat. Mend's cooldown keeps healers from out-healing damage forever. Every verb works on properties and the
material sim, so roles combo with each other and with the environment.

### 5.3.1 Roles (`SimArchetypes`)

Each character is built from a role: HP, weapon, mass and verbs. Roles are tuned in one table.

**Party** — built to combo:

| Role | Verbs | Job |
|---|---|---|
| Vanguard | Shove, Cleave | Front line; pushes enemies into hazards and off ledges |
| Pyromancer | Firebolt, Oil Flask | Area damage; lays oil, then lights it |
| Trickster | Steal, Blink, Teleport | Control; disarms, repositions enemies into fire or the air |
| Tidecaller | Rain, Frost, Mend | Support; heals, douses, makes ice that trips people |

**Enemies:** Brute (Shove, Cleave), Firecaller (Firebolt, Teleport), Skirmisher (Steal, Blink — takes items, never player weapons), Shaman (Mend, Rain, Frost), Pikeman (Shove), Thug (melee only).

### 5.4 NPC Simulation (light)

Needed for pickpocketing, crime and abusing systems:

- **Perception:** sight cones, witnesses.
- **Ownership:** every item has an owner; theft is a world event.
- **Crime:** witnessed events propagate through factions → hostility, guards, prices.
- **Needs/states:** greed (grab dropped loot), fear (flee fire), loyalty. Schedules minimal.
- Throw gold → scramble. Enemies use the same rules as players.

### 5.5 Combat

- **Side-based turns:** the whole player side acts, in any order, then the enemy side. Co-op partners plan combos together without waiting on each other.
- **Divinity-style AP pool:** each unit gains 4 AP per turn and can bank up to 6. Moving costs 1 AP per 2 m (diagonals 1.4 m, steps up/down extra); attacks and abilities have fixed costs.
- **The world advances between sides:** each side's end of turn runs a fixed number of sim ticks (4), so fire spreads and liquids flow while the other side reacts.
- **Combat movement on the sim grid:** units occupy cells and walk deterministic integer A* paths (8 directions, one-level steps), animated smoothly. Paths avoid fire and ice when a short detour exists. Walking through fire burns; stepping on ice makes you slip and lose the rest of your turn. Exploration uses the same grid movement in real time (see §4).
- **Previews:** hovering an action runs it on a copy of the sim and shows its outcome: path, AP cost, damage now and by end of turn, new fire and surfaces.
- **Optional undo** of the last action (setting) to encourage experimentation.
- **Objectives beyond "kill all":** assassinate, steal, rescue, survive, escape, protect.
- **AI (utility, `UtilityAi`):** for each enemy it generates candidate actions (attacks, its own abilities on sensible targets, a short list of move destinations), applies each to a copy of the sim and scores the outcome against doing nothing. Damage, kills and disarms on opponents score up; damage to its own side scores down; ending in fire or on fuel next to fire scores down; units want to be adjacent (melee) or ~5 cells away with sight (casters). Casts are compared after advancing the world to the end of the turn, so the AI sees chain reactions. Moves are valued with the attacks or casts they set up. Decisions take up to ~100 ms on the M1 arena.
- **Per-character verbs:** each character's verbs come from its role (§5.3.1) and are checked by the sim.
- **Controls (M1 greybox):** right-click always moves. The action bar (keys 1–9) holds Attack in slot 1, then the character's verbs; left-click a target to use the aimed action. Hovering a button shows its tooltip, its range (red where there's no line of sight) and makes every entity it can target glow. WASD is camera only.

### 5.5.0 Turn presentation

- **World advance:** between sides the world's ticks are animated one at a time on a copy of the sim (fire spreading, barrels bursting, steam rising). The sim is deterministic, so the copy ends exactly where the real EndTurnCommand does; ticks where nothing visible changes are skipped.
- **Enemy turns:** each action is decided on a worker thread (the sim is plain data), then telegraphed — the camera glides to the actor, its path or target is marked and a caption names the action — before it happens and is given time to play out. Hold Space to fast-forward.
- **Banners** announce whose turn it is and victory/defeat.
- **Camera:** actions against a target (attacks, spells on others) glide the camera to the midpoint of caster and target, then back to the caster. It never rotates, and only zooms out if the two would not fit on screen. Moving enemies are followed.
- **Health bars** float over entities when they take damage or heal, when hovered, and while Alt is held. When an action is previewed they mark the predicted loss: bright for immediate damage, dim for damage by the end of the turn (fire), green for healing, flashing when lethal.

### 5.5.1 Effects

Effects come from the BinbunVFX_Vol2 pack where it has one (`PackVfx`: spell casts, Firebolt and Frost projectiles, fire/water areas, flames on burning cells, ice, heal, teleport and hit/impact effects) and fall back to procedural particles (`VfxFactory`) otherwise, so the game runs without the pack. The pack lives in git-ignored `assetlibs/` (see CLAUDE.md). `VfxPlayer` turns sim events into effects: projectiles for Firebolt, Frost and Oil Flask (the hit waits for the bolt to land), bursts for hits, fire, steam, ice, spills, teleports and collisions, floating damage and heal numbers, impact flashes and light camera shake. `FireField` keeps a looping flame on every burning cell. Presets live in `VfxFactory.PRESETS`, so authored effects can replace them one at a time.

### 5.6 Generated Narration

A combat/event log and barks built from simulation events — e.g. *"Gerald was teleported into the well. Gerald cannot swim."* Provides "funny story" value at near-zero writing cost.

---

## 6. Quests & Events — Outcomes, Not Methods

- Quests are **predicates over world facts**, never step-by-step scripts.
  - "Retrieve the ring" → `ring.holder in party`. Pickpocket, teleport the chest, kill the owner, buy it — all count.
  - "Stop the raid" → bandits dead, fled, bribed, or bridge burned.
- **Dynamic events** are small authored hooks that fire on world conditions:
  - Granary catches fire → farmer asks for help.
  - Guard captain dies → town faction state changes.
- Dialogue reads/writes facts directly.
- **Dialogue tool:** Dialogue Manager (Godot addon, GDScript-native) or Yarn Spinner — decide in M4.

---

## 7. Co-op Design

- **Online only** (no split-screen). 2 players, each controls 2 characters (party of 4).
- **Separate inventories** — players can steal from each other.
- **Player disagreement** in dialogue (Divinity 1 rock-paper-scissors style — cheap and loved).
- Systems reward co-op tricks: one distracts the merchant while the other steals; split up and set a pincer before combat.
- Design for splitting up and regrouping.

---

## 8. Technical Architecture

### 8.1 Engine & Language

- **Godot 4.7**, Forward+, Jolt Physics.
- **GDScript only** (no .NET). Rationale: no .NET build dependency, works natively with the godot-ai MCP addon, hot reload, simplest toolchain for AI-written code.
- **Performance escape hatch:** the simulation is written so hot loops can be ported to a GDExtension (C++ or Rust) later *if profiling shows a need*. Do not port pre-emptively.

### 8.2 Layering

```
sim/      Pure simulation. RefCounted classes + Packed arrays. No Nodes, no SceneTree,
          no rendering/physics/input. Grid, materials, rules, objects, commands, facts, AI.
game/     Godot layer: scenes, rendering of sim state, input → commands, UI, audio, VFX.
net/      Networking glue: command transport, state/event replication.
tests/    Headless unit tests for sim/ (GUT).
```

The sim layer must be runnable headless and in isolation — this enables previews, undo, AI lookahead, save/load, replays and automated tests from one design.

### 8.3 Simulation Clock

- The sim advances in discrete **ticks**.
- **Real time:** ticks at a fixed rate (start ~4 Hz).
- **Combat:** one round = N ticks, advanced in batches at turn/round boundaries.
- Same rules in both modes; only the pacing differs.

### 8.4 Determinism

- **Integers / fixed-point for all rules.** No floats in sim logic.
- Seeded RNG owned by the sim state; never global `randf()`/`randi()`.
- No dependence on frame time, node order, or physics engine results inside sim rules.
- State checksums for desync detection and debugging; command logs for replays.

### 8.5 Commands & Networking

- **Every action is a command** (`MoveTo`, `CastSpell`, `Pickpocket`, `UseItem`…), in single-player too. Single-player = host with no clients.
- **Host-authoritative** (listen server): clients send commands; host validates, runs the sim, broadcasts cell/unit deltas + an event stream (`Ignited`, `Teleported`, `Stolen`) that drives VFX and narration.
- Clients keep a local replica for previews; never mutate authoritative state locally.
- **Transport:** Godot high-level multiplayer (ENet). For dev/online play before Steam: direct IP over Tailscale/ZeroTier. Steam networking later.
- **Co-op testing:** run multiple instances from the editor (Debug → Customize Run Instances).

### 8.5.1 Levels

Levels are built freely in Godot and baked into the sim (`GameLevel.bake()`, runs at load in ~0.1 s):

- **Ground:** Terrain3D (1.0.2). Cells below the rounded terrain height are solid; `WorldSpace` keeps the real height so characters, surfaces and effects sit on the ground instead of 1 m steps. Steep slopes become cliffs (unclimbable, shove-off-able), gentle ones walkable.
- **Structures:** anything with collision on layer 1 (CSG blockout now, kit meshes later). Vertical rays find the surfaces each column crosses; cells inside closed meshes are solid. Terrain3D collision lives on layer 2 so it is not probed.
- **Gameplay markers:** `LevelSpawn` (role, name, team), `LevelBarrel`, `LevelSurface` nodes; they land on the floor below them.
- The sim grid is the level's footprint with the origin at its corner (start area: 64 × 12 × 64).
- **Nothing about the world is generated in code.** Every level is a scene a human edits: sculpt, paint and scatter grass with Terrain3D's editor tools (data in `levels/<name>/terrain/`, look in `terrain_assets.tres` / `terrain_material.tres`), place CSG/meshes and markers by hand. Each level owns its WorldEnvironment and Sun.
- **Look (start area):** CC0 ambientCG grass ground, rock on slopes via Terrain3D's auto-shader, ~10k grass cards on flat, dry ground. Grass is visual only for now; ground markers draw on top of it. Burnable grass is a natural next step for the sim.
- **Arena** (`levels/arena`): a CSG greybox level with `start_in_combat` set; it is both the M1 combat arena and the sim debug sandbox's level.

### 8.6 Data Layout (performance in GDScript)

- Structure-of-arrays: one `PackedInt32Array` (or `PackedByteArray`) per cell field, flat index `x + z*w + y*w*d`, y up — see `SimGrid.index()`.
- No per-cell objects.
- Process only active cells per tick: rules find the cells that hold liquid, gas or fire with the packed arrays' native search, so a tick costs ~0.6 ms on the 49k-cell start area.
- Keep zones bounded (e.g. ~64×64×8 cells).

---

## 9. Roadmap

| Milestone | Goal | Approx. time |
|---|---|---|
| **M0** | Repo, docs, folder layout, GUT, first grid + material model with tests, debug grid renderer | 2–3 weeks |
| **M1** | Combat greybox: 1 arena, 4 materials, 5 verbs, turn system, previews — all via commands | ~2 months |
| **M2** | Online co-op on that arena — **first session together** (feasibility gate) | ~1.5 months |
| **M3** | Real-time exploration, combat transition, NPC perception, pickpocketing, crime (exploration + transition prototype done early, before M2) | ~2–3 months |
| **M4** | Fact/quest system, dialogue, vertical slice of one zone (~1 hour) | ~3 months |
| **M5** | Prologue content production | remainder |

**M2 is the real feasibility gate:** if co-op combat in a greybox arena makes both players laugh, continue.

---

## 10. Open Questions

- Split combat (one player in combat, the other exploring) — post-Prologue?
- Dialogue tool choice (M4).
- Setting, tone and the four player characters.
- Save system scope (anywhere vs checkpoints) in co-op.

---

## 11. Decision Log

| Date | Decision |
|---|---|
| 2026-10-17 | Small handcrafted campaign with bespoke encounters and fact-driven dynamic quests/events (not a roguelite). |
| 2026-10-17 | Deterministic rules with chaotic chain reactions; previewable. |
| 2026-10-17 | Real-time exploration doubles as prep; turn-based combat. Whole world goes turn-based on combat (v1). |
| 2026-10-17 | Online co-op only, 2 players × 2 characters; host-authoritative; command pattern from day one. |
| 2026-10-17 | Fine square grid (not hex) for simulation; navmesh movement. |
| 2026-10-17 | GDScript only (dropped C#/.NET); GDExtension as a later performance escape hatch. |
| 2026-10-17 | Combat: Divinity-style AP pool (4/turn, cap 6), side-based turns, movement on the sim grid (navmesh only for exploration). |
| 2026-10-17 | Enemy AI is utility scoring over simulated outcomes; abilities are per character and enemies use them on the same rules. |
| 2026-10-17 | Roles: Vanguard, Pyromancer, Trickster, Tidecaller for the party; six enemy roles. Five new verbs (Frost, Oil Flask, Mend, Cleave, Blink). Player characters can't be disarmed. |
| 2026-10-17 | Controls: right-click moves, Attack is an action-bar slot like any verb, action bar with instant tooltips and target highlights. |
| 2026-10-17 | VFX are event-driven: BinbunVFX_Vol2 pack effects where available, procedural fallbacks otherwise. |
| 2026-10-17 | Turn presentation: animated world advance, telegraphed enemy actions with camera follow and captions, AI on a worker thread. |
| 2026-10-17 | Abilities have cooldowns (in turns, per user, combat only); fixes endless heal-vs-damage duels. |
| 2026-10-17 | Exploration prototype before co-op: real-time walking on the sim grid (not navmesh) in both modes; combat starts on sight or hostility; levels are Terrain3D + collision structures + markers, baked to the sim grid at load. |
| 2026-10-17 | Scope: Prologue (1 hub + 1 zone, 2–3 h co-op) targeted at 12–18 months, 6–8 h/week, Claude Code writes the code. |
