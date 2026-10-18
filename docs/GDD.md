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
- Art is **low-poly, retro (early-2000s / PSX range)**: few polygons, small textures, a limited palette, simple per-vertex lighting with fog. Chosen because it is cheap to make and keeps a one-person content pipeline consistent: asset packs in that style (PSX packs, Kenney, Quaternius) mix well, and imperfections read as style. Shared humanoid rig + Mixamo animations. Not chasing high fidelity; a presentation layer unifies mixed assets. Prototype: `RetroLook` (P in game cycles off → early 2000s → PSX). Early 2000s: 60 % internal resolution with smooth upscale, blurrier textures (mipmap bias), Gouraud lighting, distance fog, a little extra saturation. PSX: 1/3 resolution with nearest upscale, 15-bit colour with dithering, nearest textures, vertex snapping. The full PSX pass read as too pixelated; early 2000s is the current favourite to evaluate.

---

## 4. Core Loop

```
Explore (real time) ──► interact with world, scheme, steal, set up ──► combat triggers
        ▲                                                                   │
        │                                                                   ▼
   consequences ◄── quest facts updated ◄── resolve (turn-based) ◄── fight with your setup
```

- **Exploration (real time):** move freely, talk, loot, pickpocket, sneak, move objects, prepare surfaces. This *is* the "prep phase" — there is no separate planning mode. The sim ticks live (4 Hz); characters walk the sim grid one cell per tick (paths around hazards, re-routing around anyone in the way). Right-click walks the party, the others following to the nearest free cells. One order reaches at most 40 cells along x or z (click again on the way); the walk preview waits for the cursor to settle. Abilities need no AP outside combat, but cooldowns still run (8 ticks = one turn).
- **Combat (turn-based):** starts when hostility is triggered: an enemy with sight (6 cells for enemy roles) sees a party member with line of sight, or someone hurts a fighter of the other side. Preparing the ground (oil, water, moving barrels) does not. Enemy sight areas are tinted red while exploring. Everyone fights from their current positions, so exploration setup carries directly into combat; after a win the world goes back to real time.
- **Transition (v1):** when combat starts, the **whole world switches to turn-based** and all players join. The fight itself is **local**: the whole party, plus the enemies that spotted or were hurt (or hurt someone) and their **packs** (`LevelSpawn.pack`, by default the parent node, so a pack is a group of markers under one node). Other packs sit it out; a pack joins at the start of a side turn if it sees a fighter, or as soon as one of its members is hurt. Combat ends when the joined enemies are down. (Divinity/BG3 allow split real-time/turn-based; deferred — see Open Questions.)

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
| Fire | Oil | The whole connected puddle catches at once and burns for 3 rounds (a flask puddle; bare-ground fire lasts 1.5); spreads to oil that flows into it |
| Fire / cold | Unit | Changes the unit's **temperature** (see Crowd control) |
| Unit | Oil | Slowed for 2 turns (this one and the next): moving costs double AP, walking takes twice as long |
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
| Rain | 2 | 7 | Lays a radius-2 water puddle at once (shallow water stays put on flat ground); puts out fire in the splash at once (washing burning oil away, making steam) |
| Teleport | 2 | 7 | Moves any entity under the mass limit to a free cell in sight; drop it from height or into fire (at most 3 cells above the ground, so a drop hurts but can't kill outright) |
| Shove | 1 | adjacent | Pushes 2 cells; walls and bodies hurt, ledges drop |
| Steal | 1 | adjacent | Takes an enemy's weapon, otherwise an item. Player characters can't be disarmed |
| Frost | 2 | 6 | Chills a radius: freezes water to ice now, puts out fire, 2 damage |
| Oil Flask | 1 | 6 | Splashes a radius-2 puddle at once, ready to be lit (thick oil stays put on flat ground); thrown onto or next to fire, the whole puddle catches at once |
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

### 5.4.1 Crowd control

Two kinds, both built from the systems rather than a single "stun" button:

- **Knocked down (stagger).** Most sources add 1 stagger: each physical hit by someone (attacks, Cleave, Shove), slamming into a wall or body or being shoved off a ledge (+1 on top of the shove), and every ice cell walked (in combat). Collision and fall damage alone don't. When stagger reaches the character's limit (per role: 3 by default, Vanguard and Pikeman 4, Brute 5) they are **knocked down**: their turn ends and they skip their next one, staying down through it (so an ally can still help them up, and then they act after all) and getting up when it ends. Stagger clears at the start of the target's own turn, so knocking someone down means landing hits together within one round — a co-op beat. **Help up** (every character, 1 AP, adjacent ally) gets a fallen ally back on their feet; on their own turn they can act right away.
- **Temperature.** Every character has a level: −2 **Frozen** (can't act: the turn ends and the next is skipped; they stay frozen through the skipped turn, so an ally can still thaw them, and thaw to Cold when it ends), −1 **Cold** (slowed: moving costs double), 0 Normal, +1 **Hot** (a warning step), +2 **Burning** (fire damage at each turn start for 3 turns, then Hot). Hot and Cold fade at the next turn start. Firebolt or fire lit under someone: +2; each fire cell walked over, or each tick standing in fire: +1; Frost: −2; Rain: −2 and walking into water: −1, but water never cools below Cold (only Frost freezes). Opposites cancel: a frozen character hit by Firebolt is back to Normal (and, on their turn, can act again); a burning one hit by Frost likewise.
- **Arriving in a cell** works the same however it happens — walking, shoved (every cell pushed through), teleported, blinked or falling: fire hurts and heats a level, water cools, oil slows, ice staggers (`EntityOps.enter_cell()`).
- Feedback: tags above the name (with turns left, and Stagger x/y), a looping effect per state, a knocked-down character lies down, a frozen one turns icy.

### 5.5 Combat

- **Side-based turns:** the whole player side acts, in any order, then the enemy side. Co-op partners plan combos together without waiting on each other.
- **Divinity-style AP pool:** each unit gains 4 AP per turn and can bank up to 6. Moving costs 1 AP per 2 m (diagonals 1.4 m, steps up/down extra); attacks and abilities have fixed costs.
- **The world advances between sides:** each side's end of turn runs a fixed number of sim ticks (4), so fire spreads and liquids flow while the other side reacts.
- **Combat movement on the sim grid:** units occupy cells and walk deterministic integer A* paths (8 directions, one-level steps), animated smoothly. Paths avoid fire and ice when a short detour exists. Walking through fire burns; stepping on ice makes you slip and lose the rest of your turn. Exploration uses the same grid movement in real time (see §4).
- **Previews:** hovering an action runs it on a copy of the sim and shows its outcome: path, AP cost, damage now and by end of turn, new fire and surfaces.
- **Optional undo** of the last action (setting) to encourage experimentation.
- **Objectives beyond "kill all":** assassinate, steal, rescue, survive, escape, protect.
- **AI (utility, `UtilityAi`):** for each enemy it generates candidate actions (attacks, its own abilities on sensible targets, a short list of move destinations), applies each to a copy of the sim and scores the outcome against doing nothing. Damage, kills and disarms on opponents score up; damage to its own side scores down; ending in fire or on fuel next to fire scores down; units want to be adjacent (melee) or ~5 cells away with sight (casters). Melee units measure distance by walking (a walk field searched out from the opponents each decision), so they take the ramp or stairs instead of crowding a cliff edge above their target. Melee units also **guard their casters**: they stay within 4 cells of the nearest ranged ally unless they can end next to an opponent, so a group advances together instead of its melee being lured off one by one. Casts are compared after advancing the world to the end of the turn, so the AI sees chain reactions. Moves are valued with the attacks or casts they set up. Decisions take up to ~100 ms on the M1 arena.
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

**Ground surfaces** (water, oil, ice) are drawn as smooth puddles, not grid squares (`SurfaceRenderer` + `surface.gdshader`): a mesh of the surface cells and a ring around them, with corners on the real floor (terrain heights sampled at cell corners, so neighbouring cells share vertices and there are no gaps), shaped by a one-texel-per-column mask that is sampled smoothly and cut at a noisy threshold, so outlines round off and merge across cells. Limits: one surface per column is shown (the topmost), and puddles don't continue across a step of more than ~0.6 m. Gas and greybox fire are still boxes.

**Readability.** Allies have a green outline, enemies a red one (stencil outline); ground markers (range, paths, previews) draw over grass but never over a character. The fallen stay where they died as grey corpses; after the fight any party member can **Revive** an adjacent fallen ally (25 % HP). Camera: WASD pan, Q/E or middle-mouse drag rotate, wheel zoom.

**Feedback rules.** Every hit shows a floating damage number coloured by its element (`EntityOps.Element`): white physical, orange fire, blue frost/water. Every debuff shows a coloured tag above the character's name with its turns left, and plays a looping effect on the character while it lasts (Burning: flames; Slowed: dripping oil). New debuffs follow both rules (`SimEntityRenderer.STATUS_LOOKS`). Damage at the start of a turn (burning) is shown with the turn change.

### 5.6 Generated Narration

A combat/event log and barks built from simulation events — e.g. *"Gerald was teleported into the well. Gerald cannot swim."* Provides "funny story" value at near-zero writing cost.

---

### 5.7 Perception, stealth and crime (M3)

- **Vision cones.** NPCs (enemies and townsfolk) see in a 120° cone along their facing, out to their sight (enemies 6, townsfolk 5, guards 7), with line of sight; someone walking normally is also heard within 2 cells from any side. Idle NPCs look around their post (±45° every 3 s); walking turns you to face the way you go. Level markers set facing from their rotation. Cones are drawn on the ground near the party: red = enemies (a fight starts), yellow = townsfolk (witnesses), orange = a suspicious one.
- **Sneaking** (C, per character, outside combat): half walking speed; only seen inside cones, at half range; no hearing. Combat ends it.
- **Pickpocket** (every party member, outside combat, adjacent, free): lifts the target's first item (never the weapon). Stolen items are tagged with their owner's group.
- **Crime.** Townsfolk (`Faction.NEUTRAL`, `LevelSpawn.team = NEUTRAL`) who see a pickpocket become **suspicious** (!); caught again, or seeing violence, and the whole group turns **hostile** and fights. Attacking a neutral turns its group hostile even unseen. A suspicious NPC who later sees someone carrying its group's stolen goods turns hostile too. Pickpocketing an enemy in its sight starts a fight.
- **Inventory** (I): a grid of 1-item slots per character, always with a free row (no limit). Items come from the catalog `sim/items/sim_items.gd` (value in gold, weight in grams, kind, blurb); drag an item onto another slot to move it (onto an empty slot: to the end; free, any time), or onto a party member's card to give it (outside combat); hover a slot for details, or click it to select and use the give buttons (stolen tags travel with it). The footer shows the count, total value and weight. Partners can pickpocket each other's characters (no crime).
- Start area: a small village (Merchant at a stall, Villager, Farmer, Guard) between the party and the pond.

### 5.8 Loot, items, trade and progression (M4)

All of these are commands on properties, never on item names (rule 9): items in `sim/items/sim_items.gd` carry `heal`, `temperature`, `slot`/`damage`/`armor`, `money`, `rest`.

- **Containers** (`LevelContainer` markers, `LootCommand`): anything with items that isn't a living character or a party member — chests, broken crates, enemy corpses. Click to open (walk over first); take one or all, outside combat. `key` locks it until someone carries that item; destroying it (bashing, fire) breaks it open with its contents. Containers under a neutral group's node are theirs: taking is theft (stolen tags, witnesses). Fallen enemies drop what they wore.
- **Consumables** (`UseItemCommand`): on yourself or an adjacent ally; 1 AP in combat. Healing potion, Bread, Cooling salve (puts out Burning), Warming draught (thaws).
- **Rest** (`RestCommand`): with a Bedroll in the party, outside combat, no enemies within 12 cells: the standing party heals fully and clears statuses and cooldowns. The fallen need Revive first.
- **Trade** (`TradeCommand`): characters carry `gold`. Traders (`LevelSpawn.trades`) offer it in dialogue (`~ trade`); one deal = buy and sell lists. Buying costs value (×1.5 when suspicious), selling fetches half (money at full value). A trader won't buy back its own group's stolen goods; other stolen goods get fenced.
- **Equipment** (`EquipCommand`, `EquipRules`, outside combat): a paperdoll of eleven slots — head, neck, body, hands, waist, legs, feet, two rings, main hand, off hand. Two-handed weapons fill both hands (wearing one takes the other off). Gear stats add up: weapon damage, extra damage (off-hand dagger, gloves), armour (each point takes 1 off a physical hit, at most half the hit; fire/frost ignore it), power, max HP. Characters can start wearing things (`LevelSpawn.equipment`); fallen enemies drop everything they wore.
- **Progression** (`ProgressionRules`): shared XP (everyone in the party gets all of it) from defeated enemies (4 × max HP) and quest outcomes (`xp:` line in .quest files). Level n+1 at 50·n·(n+1) XP: +2 max HP and a point for Vitality (+4 HP), Power (+1 damage, spells too) or Resolve (+1 stagger). Shown in the inventory's character sheet.
- Quests only end once known: clearing the camp before hearing of it ends the quest the moment you do.

## 6. Quests & Events — Outcomes, Not Methods

- Quests are **predicates over world facts**, never step-by-step scripts.
  - "Retrieve the ring" → `ring.holder in party`. Pickpocket, teleport the chest, kill the owner, buy it — all count.
  - "Stop the raid" → bandits dead, fled, bribed, or bridge burned.
- **Dynamic events** are small authored hooks that fire on world conditions:
  - Granary catches fire → farmer asks for help.
  - Guard captain dies → town faction state changes.
- Dialogue reads/writes facts directly.

### 6.1 Facts, dialogue and quests (M4)

- **Facts** (`SimFacts`): named integers. Stored facts live in `state.facts` (set by dialogue); derived facts are read from the world: `alive.<Group>`, `dead.<Group>`, `hostile.<Group>`, `has.<Item>` (the party carries it; `_` = space), `combat`, `quest.<id>.known|done|<outcome>`, and `self.*` for the NPC being talked to. Conditions are small integer expressions (`SimExpr`: `and or not`, comparisons, `+ -`).
- **Dialogue** is our own plain-text, ink-like format (`game/data/dialogue/*.dlg`, parsed by `SimDialogue`): `=== knot`, `Speaker: line`, `{condition}` before any statement, `~ fact = expr`, `~ give Item` / `~ take Item`, choices `* {cond} [text] -> knot`, `-> knot` / `-> END`. NPCs point at a knot with `LevelSpawn.dialogue`. It runs in the sim (deterministic, synced like any command): `TalkCommand` (outside combat, within 2 cells, not hostile) and `ChooseCommand`. Walking away or a fight ends the conversation.
- **Quests** (`game/data/quests/*.quest`, `QuestRules`): a quest becomes known when its `known:` expression holds, and ends with the first `outcome <name>: <expr>` that holds; each outcome has its own journal text. No steps: "The bandit problem" ends as `cleared` (bandit pack dead, however) or `turned` (the village turned hostile). Banner + narration on start/end; J opens the journal.
- **Co-op:** one talks, both see. Only the talking player chooses; the partner sees the conversation live.
- Content is loaded by `Content.load_all()` (game layer reads the files, the sim only sees text). Parse errors are pushed as warnings and checked by a test.

---

## 7. Co-op Design

- **Online only** (no split-screen). 2 players, each controls 2 characters (party of 4).
- **Separate inventories** — players can steal from each other.
- **Player disagreement** in dialogue (Divinity 1 rock-paper-scissors style — cheap and loved). Later; v1 is "one talks, both see".
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
- **Host-authoritative command stream** (listen server, `net/net_session.gd`, autoload `Net`). The sim is deterministic, so peers stay in sync by running the same commands in the same order rather than receiving state deltas: clients send commands; the host checks the sender controls the acting character and that the command is valid on its authoritative state, applies it, and broadcasts it as the next op of one numbered stream. Real-time ticks are ops too (only the host ticks); enemy AI runs on the host and goes through the same stream. Every peer, the host included, plays the stream in order on its own copy and animates it; events drive VFX and narration locally.
- **Joining and drift:** a joining guest receives a compressed snapshot of the whole sim (`SimState.to_snapshot()`, a few KB for the arena). Every command op (and every 16th tick) carries a checksum; a guest whose copy disagrees asks for a fresh snapshot.
- **Co-op turns:** the party's turn is shared — both players act at once with their own characters (`LevelSpawn.player`: host Ari + Bram, guest Cel + Dov; alone, the host plays all four) and the turn ends when both have pressed End Turn.
- Clients keep a local replica (the stream copy) for previews; they never apply anything that didn't come from the host.
- **Transport:** Godot high-level multiplayer (ENet). For dev/online play before Steam: direct IP over Tailscale/ZeroTier. Steam networking later.
- **Sessions:** the host's addresses (Tailscale first, then LAN) show on the menu and in game; F10 leaves; a guest who leaves or drops can rejoin mid-fight (the host plays their characters meanwhile); a dead connection is noticed within ~6 s; a join that gets no answer gives up after 10 s with a hint. Ping shows in the HUD.
- **Builds:** `bash tools/export_windows.sh` makes `build/glaze-windows.zip` (exe + `docs/PLAYTEST.md` as HOW_TO_PLAY_TOGETHER). Needs Godot 4.7.2 export templates.
- **Co-op testing:** the main menu has Solo / Host / Join. From the command line (after `--`): `--solo`, `--host`, `--join=ADDRESS`, `--level=arena|start|highlands`, and `--autoready` (that player ends turns on their own, so one person can test with two instances).

### 8.5.1 Levels

Levels are built freely in Godot and baked into the sim (`GameLevel.bake()`, runs at load in ~0.1 s):

- **Ground:** Terrain3D (1.0.2). Cells below the rounded terrain height are solid; `WorldSpace` keeps the real height so characters, surfaces and effects sit on the ground instead of 1 m steps. Steep slopes become cliffs (unclimbable, shove-off-able), gentle ones walkable: the bake also gives the sim each terrain column's real height (integer cm), and walking between neighbouring floors that differ by more than 1.1 m is not allowed (1 m structure steps still are), and between two terrain floors by more than 0.7 m (steep rocky slopes are cliffs).
- **Structures:** anything with collision on layer 1 (CSG blockout now, kit meshes later). Vertical rays find the surfaces each column crosses; cells inside closed meshes are solid. Terrain3D collision lives on layer 2 so it is not probed.
- **Gameplay markers:** `LevelSpawn` (role, name, team), `LevelBarrel`, `LevelSurface` nodes; they land on the floor below them.
- The sim grid is the level's footprint with the origin at its corner (start area: 64 × 12 × 64).
- **Nothing about the world is generated in code.** Every level is a scene a human edits: sculpt, paint and scatter grass with Terrain3D's editor tools (data in `levels/<name>/terrain/`, look in `terrain_assets.tres` / `terrain_material.tres`), place CSG/meshes and markers by hand. Each level owns its WorldEnvironment and Sun.
- **Look (start area):** CC0 ambientCG grass ground, rock on slopes via Terrain3D's auto-shader, ~10k grass cards on flat, dry ground. Grass is visual only for now; ground markers draw on top of it. Burnable grass is a natural next step for the sim.
- **Arena** (`levels/arena`): a CSG greybox level with `start_in_combat` set; it is both the M1 combat arena and the sim debug sandbox's level.

### 8.5.2 Saving

- **Save anywhere**, in combat too (on the party's turn, between actions). A save is the host's whole `SimState` snapshot (the same one co-op joins use) plus a header: title, level, time, playtime, party. Loading re-instantiates the level for its scenery and plays from the saved state instead of the bake, so level scenes must not hold game state.
- **Co-op: the host owns the save.** Only the host saves and loads (files in `user://saves/` on the host's PC); loading sends the guest the world like a join.
- **Slots:** F5 quicksave / F9 quickload; autosaves rotate through 3 slots (on a new quest, quest end, fight start, and every 5 minutes played); named saves from the Esc menu; the main menu continues any save, solo or hosted.
- **Compatibility:** the snapshot carries `SimState.SNAPSHOT_VERSION`. Missing entity/combat/state fields load with their defaults, so adding a field needs nothing; renaming or reinterpreting one, or a new grid array, bumps the version with a migration step. `tests/fixtures/snapshot_v<N>.bin` keeps a save from every version, and a test loads them all. Saves from a newer version are refused, not crashed on.
- Known limit: a save holds the baked grid, so editing a level's layout doesn't reach existing saves of it.

### 8.6 Data Layout (performance in GDScript)

- Structure-of-arrays: one `PackedInt32Array` (or `PackedByteArray`) per cell field, flat index `x + z*w + y*w*d`, y up — see `SimGrid.index()`.
- No per-cell objects.
- Process only active cells per tick: liquids and gases are found with the packed arrays' native search (skipped entirely while a field is known empty), fire and temperature keep sparse cell sets (`fire_cells`, `heat_cells`).
- **Copies are copy-on-write:** `duplicate_state()` shares the grid's arrays until one side writes, so previews and AI lookahead don't pay for the world's size. Grid writes go through `edit_*()` / `set_fire()` / `set_temperature()`.
- Measured on `levels/highlands` (256 × 40 × 256 = 2.6M cells, 164 entities, 32 packs): bake ~1–2 s, idle tick ~0.7 ms, state copy ~1.4 ms, enemy decision ~0.3 s, 240 FPS exploring (vsync), ~95 FPS with the whole map in view. Remaining costs that grow with size: the first write after a copy copies that whole field (~10 MB per int field), long A* paths (~30 ms for 100 cells), and the bake. Chunked storage is the next step if zones grow beyond this.

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
- Setting, tone and the four player characters.

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
| 2026-10-18 | Co-op sync is a host-authoritative **command stream** (deterministic replay, snapshot on join, checksums with resync) instead of state deltas. Shared party turn ends when both players are ready; fixed 2 + 2 character split. |
| 2026-10-18 | Terrain steps above 0.7 m are cliffs; melee AI guards its casters (stays within 4 cells unless it can engage). |
| 2026-10-18 | AI judges melee distance by walking routes, not straight lines. |
| 2026-10-18 | Movement respects real terrain height: no walking up or down a rise of more than 1.1 m between neighbouring cells. |
| 2026-10-18 | Ground surfaces render as smooth, ground-hugging puddles (mask + threshold shader) instead of per-cell boxes; the square grid doesn't show through. |
| 2026-10-18 | Rain splashes its full puddle instantly, like the Oil Flask; shallow water no longer creeps on flat ground; water cools to Cold at most. |
| 2026-10-18 | M3 stealth & crime: vision cones with facing and hearing, sneaking, pickpocketing, neutral townsfolk with suspicion → group hostility, stolen-goods tags, inventory panel with giving. Spotting uses cones for enemies too. |
| 2026-10-18 | First playtest feedback: middle-drag camera rotation, faction outlines, markers no longer cover characters, corpses stay and can be revived after combat. |
| 2026-10-18 | M2 two-PC essentials: Windows export, connection help (Tailscale/LAN/port 24560 UDP), leave/rejoin, fast disconnect detection, ping. Next: the real playtest together. |
| 2026-10-18 | Crowd control: stagger → Knocked down (skip next turn; Help up); body temperature −2..+2 with Frozen/Cold/Hot/Burning replacing the separate Burning status; ice staggers instead of ending your turn. |
| 2026-10-18 | Ground fire lasts longer: a lit flask puddle burns 3 rounds (was 1), bare-ground fire 1.5 (was 0.6). |
| 2026-10-18 | Feedback rules: damage numbers coloured by element; every debuff gets a tag and a looping effect. |
| 2026-10-18 | Burning status: fire under a character hits at once and burns for 3 turns (turn-start damage); each burning cell walked over hits again; water douses. |
| 2026-10-18 | Oil: flask splashes its full puddle instantly and oil puddles don't creep on flat ground; lighting oil ignites the whole connected puddle at once; walking through oil slows (double move cost) for 2 turns. |
| 2026-10-18 | Art direction refined: low-poly early-2000s look (soft, fogged, Gouraud) rather than full PSX pixelation, which read as too blocky. |
| 2026-10-18 | Art direction: low-poly, PSX-inspired look (not high fidelity), fitting a solo content pipeline. Engine stays Godot; a GDExtension port of `sim/` is the escape hatch if sim speed becomes the limit. |
| 2026-10-18 | Fights are local: the party plus spotting/provoked enemies and their packs; other packs sit out. Sim grid copies are copy-on-write; fire and heat keep sparse cell sets. Stress level `levels/highlands` (256 m, 32 packs). |
| 2026-10-18 | M4 dialogue & quests: own ink-like text format run inside the sim (talk/choose are commands), facts as integers (stored + derived from the world), quests as outcome predicates with journal text; first quest "The bandit problem". Co-op: one talks, both see. Dialogue tool question closed (no addon). |
| 2026-10-18 | Save system: save anywhere (combat too), host owns co-op saves, quick + rotating auto + named slots; saves are versioned sim snapshots with default-tolerant loading, migrations and per-version fixtures. |
| 2026-10-18 | Readability: world text kept to a minimum. Statuses are icons with turns left (spelled out on hover); names only on the hovered/selected character (Alt shows all); AP lives in the party bar; the HUD shows state and the current preview, with controls behind H and perf behind `. |
| 2026-10-18 | M4 slice systems: containers with keys (bash-open, theft from neutrals), consumables, bedroll rest, trading with gold, weapon/armour slots, shared XP with level points. All property-driven commands; quests end only once known. |
| 2026-10-18 | UI rework: party frames with portraits down the left edge; bottom action bar of uniform icon slots, 3 pages ([ ] or arrows), holding actions and usable items (drag from the inventory, right-click clears), layout saved per player; End turn bottom right (combat only). Hand-made SVG icons for every ability and bar item. Window 1920×1080 by default on a 1280×720 UI base (UI scales, shrinks to fit smaller screens). |
| 2026-10-18 | Paperdoll equipment (11 slots, two-handed weapons, gear stats, armour capped at half a hit) and an icon for every item; the inventory is the character sheet: paperdoll, icon bag, stats, drag to wear/take off. |
| 2026-10-18 | One UI standard: a shared theme and window style (`UiStyle`) and one item slot (`ItemSlot`) for inventory, paperdoll, trading and loot; trade and loot windows are icon grids with prices/details like the inventory. |
| 2026-10-17 | Scope: Prologue (1 hub + 1 zone, 2–3 h co-op) targeted at 12–18 months, 6–8 h/week, Claude Code writes the code. |
