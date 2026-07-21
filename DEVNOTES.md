# Noema — Dev Notes
	
	## Project Overview
	Godot 4 mobile game (landscape, iOS/Android). Single shared persistent sphere world where players influence colonies of dots via natural language chants. No direct control — chants accumulate as CCE (Cumulative Chant Exposure) which drives probabilistic dot behavior.
	
	Design bible: `Noema_Design_Bible_v0.4.docx` in repo root.
	
	---
	
	## Architecture
	
	### Client (Godot 4)
	- Single scene: `main.tscn` / `main.gd`
	- Mobile renderer, 1920x1080 landscape
	- USE_SERVER = false (local prototype mode)
	- When USE_SERVER = true, chants route to server via HTTP (not yet implemented)
	
	### Scene Structure
	- Node3D (Main) — main.gd attached
	  - WorldSphere (MeshInstance3D) — white sphere, radius 1.0
	  - SphereBody (StaticBody3D + CollisionShape) — collision for sphere surface
	  - Camera3D — orbital, driven by yaw/pitch angles
	  - DirectionalLight3D — soft (energy 0.3), shadows on
	  - WorldEnvironment — ambient light 0.85 to lift dark side
	  - UI (CanvasLayer)
	    - ChantButton — bottom center, opens modal
	    - ChantModal — center screen text input (Panel > VBox > LineEdit + buttons)
	    - DevBar (LineEdit) — always-visible bottom bar for dev chanting, Enter to submit
	
	---
	
	## CCE System
	
	### Dot Data Structure
	```
	dot_data[dot] = {
	  "age": int,           # ticks lived, dies at DOT_LIFETIME (100)
	  "cce": {
	    "motion": { "wander": float, "face_target": float },
	    "action": { "mark_surface": float, "build_upward": float, "gather": float,
	                "defend": float, "attack": float, "reproduce": float },
	    "dials":  { "range": float, "intensity": float, "frequency": float,
	                "affinity": float, "spiral": float }
	  }
	}
	```
	
	### Key Constants
	- DOT_LIFETIME = 100 ticks
	- TICK_SPEED = 5.0 seconds (active play rate — passive tick rate not yet implemented)
	- CCE_DILUTION = 0.7 (children inherit 70% of parent CCE)
	- CHANT_WEIGHT = 0.08 (weight delta per chant)
	- DIAL_BASELINE: range 0.5, intensity 0.5, frequency 1.0, affinity 0.0, spiral 0.0
	
	### Per-Tick Dot Behavior
	Each tick every dot:
	1. Builds a weighted pool from motion + action CCE weights
	2. Picks ONE primitive by weighted random roll
	3. Executes that primitive with dial modifiers applied
	4. Dies if age >= DOT_LIFETIME
	
	### Active Primitives (wired)
	- wander — random surface nudge, range dial controls distance, spiral dial biases direction
	- reproduce — probabilistic spawn adjacent dot, intensity dial controls chance
	- defend — moves toward colony center
	
	### Inactive Primitives (CCE accumulates, no execution yet)
	- attack — needs foreign dot detection
	- gather — needs resource system
	- build_upward — needs surface marking system
	- mark_surface — needs surface marking system
	- face_target — needs target system
	
	### Dial Notes
	- spiral is a wander modifier (not a standalone primitive) — high spiral makes wander orbit consistently
	- range: 0=tiny nudge, 1=large movement
	- intensity: 0=low effect, 1=high effect (e.g. reproduce chance lerps 0.1-0.9)
	
	---
	
	## CCE Color System
	Dot color reflects dominant CCE weights (blended proportionally):
	- wander → amber (1.0, 0.75, 0.1)
	- reproduce → green (0.3, 0.9, 0.3)
	- defend → blue (0.2, 0.5, 1.0)
	- attack → red (1.0, 0.2, 0.2)
	- neutral → white
	
	Children born with inherited CCE color already applied.
	Foreign dots in bleed range: visual system stubbed, not yet implemented.
	
	---
	
	## Claude Chant Bridge
	For testing LLM-style chant interpretation without a server:
	- Game polls `res://chant.json` each tick
	- Claude writes a CCE recipe JSON to that file via MCP
	- Game applies recipe, clears file
	- `chant.json` is gitignored (live file)
	
	Recipe format:
	```json
	{
	  "motion": { "wander": 0.1 },
	  "action": { "reproduce": 0.08 },
	  "dials": { "range": 0.1, "intensity": 0.05, "frequency": 0.0, "affinity": 0.0 }
	}
	```
	
	In-game DevBar uses local recipe dict as fallback (single words only).
	
	---
	
	## Local Recipe Dict (current trigger words)
	- wander/explore/roam → wander + range +0.05
	- spiral → spiral dial +0.1
	- reproduce/multiply/sex/breed → reproduce
	- attack/fight/war → attack + intensity +0.05
	- defend/protect/guard → defend
	- gather/collect/harvest → gather
	- build/construct → build_upward
	- mark/paint → mark_surface
	- far/farther/distant → range +0.1
	- close/near/tight → range -0.1
	- fierce/sharp/strong → intensity +0.1
	- gentle/soft/slow → intensity -0.1
	
	---
	
	## Camera
	- Orbital: yaw/pitch angles, always looks at Vector3.ZERO
	- RMB drag (desktop) / single finger drag (mobile) to orbit
	- Scroll wheel (desktop) / pinch (mobile) to zoom
	- Zoom: MIN 1.12 (just above surface), MAX 6.0
	- Smooth lerp zoom via zoom_target / zoom_distance split
	- Touch positions tracked manually in Dictionary (Godot 4 — no Input.get_touch_position)
	- Focus on colony runs once at startup only — camera does not reset during play
	
	---
	
	## Git / Deployment
	- Repo: https://github.com/UndoneIridium/dots
	- Commits via OS.execute git through Godot MCP (godot-mcp-pro)
	- Repo creation via gh CLI: /opt/homebrew/bin/gh
	- Node.js at /opt/homebrew/bin/node (used for docx generation only, not in game)
	- npm docx package installed temporarily for bible generation, then removed
	
	---
	
	## Known Issues / TODO
	- Passive tick rate not implemented (server-side concern)
	- CCE blending between colonies not implemented (needs foreign dot detection)
	- attack/gather/build/mark_surface primitives silently do nothing
	- No resource system
	- No surface marking system
	- No multiplayer / server layer
	- Foreign dot rendering stubbed but not wired
	- Population cap not implemented (reproduce will grow unbounded)

---

## Session Notes — 2026-05-06

### HUD
- Added `UI/HUD` Label node (top-left, always visible)
- Shows dot count and top 3 dominant CCE behaviors averaged across all dots
- Updates on chant apply and once at startup

### Spatial Grid (foreign dot exclusion)
- `spatial_grid`: Dictionary mapping `Vector2i` cell keys → `Array` of dots
- `GRID_RES = 200` (cells per axis, tunable)
- `_cell_key(dir)` quantizes a sphere direction to a grid coordinate
- `_rebuild_spatial_grid()` called once per tick after aging
- `_is_blocked_by_foreign(dir, colony)` — blocks movement/spawn into cells occupied by a different colony
- `_get_foreign_dots_near(dir, colony)` — returns all foreign dots in cell + 8 neighbors (ready for combat)
- `_is_cell_occupied(dir)` — checks exact cell only; blocks same-colony spawn stacking
- Spawn now requires target cell to be empty (any colony) — prevents FPS tank from dot stacking
- Naturally caps reproduce-heavy colonies at area saturation; must wander to expand
- Scales well for client-side prototype; server will own territory logic at scale

### Colony 1 (enemy test colony)
- Spawns 45° from colony 0 on the equator
- Preset CCE: attack 0.40, wander 0.40, reproduce 0.32
- `ENEMY_COLONY = 1` constant; colony ID stored in `dot_data[dot]["colony"]`
- Children inherit full CCE (no dilution) for testing — revert via `CCE_DILUTION` flag when ready
- `_create_dot()` now accepts `colony` and `preset_cce` params

### Fog of War
- Foreign colonies render as dim grey (0.25, 0.25, 0.25) until contact with colony 0
- `revealed_colonies` dictionary; colony 0 always revealed
- `_check_fog_of_war()` runs each tick after grid rebuild
- On first contact, colony is permanently revealed and all dot colors update
- Per-colony revelation (not per-dot)

### CCE Color Magnitude
- Color now lerps from white toward hue based on total CCE weight sum
- `MAX_CCE_FOR_SATURATION = 1.5` — dots with low total CCE appear washed out
- Diluted children correctly appear less saturated than parents

### Combat Design (decided, not yet implemented)
- Probabilistic: attacker rolls `attack` primitive, finds foreign dot via grid
- Combat power = attack CCE + defend CCE for each dot
- Higher total wins; ties go to attacker
- Both dots deleted if mutual attack resolves same tick (MAD)
- Pending deletions list processed after all primitives resolve
- attack primitive still a no-op pending implementation

### Known Issues / TODO
- Passive tick rate not implemented (server-side concern)
- attack/gather/build/mark_surface primitives silently do nothing (combat designed, not wired)
- No resource system
- No surface marking system
- No multiplayer / server layer
- CCE dilution disabled for ENEMY_COLONY (testing only — re-enable when tuning)
- HUD shows combined CCE across all colonies — should separate per-colony
	

---

## Session Notes — 2026-05-06 (cont.)

### Combat System (implemented)
- `COMBAT_TICKS = 3` — combat resolves after 3 ticks; intensity > 0.7 shortens to 2
- `combat_clusters` array — each entry: `{pairs: [{attacker, defender}], ticks_remaining}`
- `combat_locked` dict — dots in combat skip their primitive roll
- Attack primitive now a deliberate march: detects enemies within `ATTACK_DETECT_RADIUS = 10` cells, steps one cell per tick toward nearest, locks on contact
- `CELL_STEP` constant defines one grid-cell march distance
- March uses `_is_foreign_in_exact_cell` (exact cell only) so attacker advances right to the line
- Wander/defend still use full 8-neighbor `_is_blocked_by_foreign` for separation
- Cluster timer shared — multiple attackers can pile onto one defender, all resolve together
- Attacker wins ties; both deleted on mutual combat (MAD)
- `_remove_dot()` now cleans up combat clusters immediately when a dot is removed mid-combat — prevents zombie locked dots
- `_apply_recipe()` now filters to LOCAL_COLONY only — chants no longer affect enemy colony
- TICK_SPEED reduced to 1.0 for testing (was 5.0)
- `_is_foreign_in_exact_cell(dir, colony)` added — exact cell foreign check for march logic

### Known Issues / TODO
- Passive tick rate not implemented (server-side concern)
- gather/build/mark_surface primitives silently do nothing
- No resource system
- No surface marking system
- No multiplayer / server layer
- CCE dilution disabled for ENEMY_COLONY (testing only)
- HUD shows combined CCE across all colonies — should separate per-colony
- Client FPS tanks at ~8k dots — expected, server will own simulation at scale

---

## Session Notes — 2026-05-07

### Code Audit Pass
- Removed `face_target` from NEUTRAL_CCE (no execution path)
- Removed `frequency`, `affinity` dials (unused)
- Removed `DIAL_BASELINE` (unused)
- Promoted magic numbers to constants: `SPAWN_NUDGE`, `DEFEND_STEP`, `DOT_SURFACE_OFFSET`, `PARALLEL_EPSILON`, `MAX_CCE_FOR_SATURATION`
- `_local_recipe()` match statement → `CHANT_RECIPES` data-driven dict
- Reserved primitives (gather/build/mark) intentionally absent from chant aliases until execution paths exist
- `USE_SERVER` now `push_warning`s if accidentally enabled
- Stale `is_instance_valid` checks removed from grid lookups (now relying solely on `dot_data.has`, since `_remove_dot` is synchronous)
- `_apply_recipe` and `_update_hud` consolidated single-pass
- `_create_dot` parent CCE inheritance guards against missing keys (forward-compat for differently-shaped colony presets)

### Combat Cluster Index
- `cluster_by_defender = {}` provides O(1) lookup of "is this defender already in a cluster?"
- `_initiate_combat` uses index instead of nested O(n×m) scan over all clusters
- Index maintained on cluster create, append, resolution, and dot removal

### Incremental Spatial Grid
- `dot_cell = {}` tracks each dot's current cell key
- `_grid_insert(dot, key)` and `_grid_update_position(dot)` helpers
- `_place_dot_on_sphere` calls `_grid_update_position` after every move
- `_create_dot` inserts on creation, `_remove_dot` removes on death
- Per-tick `_rebuild_spatial_grid` call eliminated
- Big per-tick performance win at high dot counts

### Colony Population Tracking
- `colony_counts = {}` — colony_id → live dot count
- Maintained on `_create_dot` and `_remove_dot`
- `MAX_POPULATION_PER_COLONY = 1000` testing aid; `_spawn_dot_near` rejects if at cap
- HUD shows both p0 and p1 counts; updates every tick now (was chant-apply only)

### Fog of War (testing override)
- `_check_fog_of_war` short-circuits with `return` after the early-exit so ENEMY_COLONY stays grey for visual contrast during testing
- Remove the bare `return` to restore normal reveal-on-contact behavior

### Colony 0 Preset
- `COLONY0_CCE` constant added: wander 0.40, attack 0.30, reproduce 0.32 (vs. p1's 0.40/0.40/0.32)
- All p0 spawns use `full_inheritance: true` for stable testing
- `_spawn_player_dot` seeds with the preset

### Combat Resolution: Winner Advances
- When attacker wins, advances into defender's vacated cell after `_remove_dot` clears the spatial grid entry
- Multi-attacker case: first winner against a given defender claims the cell; others stay put (free to march toward new targets next tick)
- Implemented via `cell_claimed_by` per cluster + `to_advance` resolved after deletions

### Observations from Testing
- p1 with split CCE (wander 0.40 / attack 0.40) drifts uncommitted dots away from front during long runs
- With 1000-cap, p1 starves the front line as wandering dots can't be replaced by reproduction
- Without cap, p1 reproduction would replenish — but front line cohesion is still a real design issue worth thinking about (e.g. needing a "march toward enemy" or rallying behavior beyond detection radius)
- Combat math otherwise validates: p1's higher attack consistently wins individual engagements; observable issue is throughput/cohesion not correctness

### Known Issues / TODO
- gather/build/mark_surface primitives silently do nothing
- No resource system / surface marking system
- No multiplayer / server layer
- CCE dilution disabled for both colonies during testing (full_inheritance for both)
- p1 keeps using fog color even after contact (testing override — easy revert)
- Combat lock burden + wander competition causes aggressive colonies to lose front-line cohesion over long runs (design observation, not bug)


---

## Session Notes — 2026-05-09

### Rally Banners (combat cohesion fix)
- `RALLY_RADIUS = 30` cells, `BANNER_TTL = 6` ticks
- `banners` array: `{cell, colony, ticks_remaining}` — no visual, pure data
- Dropped on `_initiate_combat` for BOTH attacker and defender colonies at the contact cell
- Refresh-on-redrop semantics: existing banner at same cell+colony has TTL refreshed instead of duplicated
- Friendly-only pull: when a dot rolls `attack` and finds no foreign in `ATTACK_DETECT_RADIUS`, falls back to `_march_toward_banner` which targets nearest same-colony banner within `RALLY_RADIUS`
- Banner cell→sphere direction conversion via `_cell_to_dir` (inverse of `_cell_key`)
- `_torus_cell_dist_sq` helper for wrap-around grid distance
- `_march_toward` refactored to share tangent-step math with banner march via `_march_toward_dir`
- Validated by long-run match: p1 (0.40 attack) cleanly encircled and wiped p0 (0.30 attack) — the cohesion fix lets attacker CCE concentrate at the front rather than diffusing into wandering

### Walls / Blocks (Step 1 of defense system)
- "Block" is the user-facing term; `is_wall` flag and `wall_*` names retained for code load-bearing
- `WALL_DEFEND_VALUE = 0.5`, `WALL_DECAY_TICKS = 300`, `WALL_MESH_SIZE = (0.015, 0.003, 0.015)` (half a dot's height), `WALL_HEIGHT_STEP = 0.003`
- `wall_counts` dict tracks per-colony wall count separately from `colony_counts` (walls don't count toward population)
- `_create_wall(cell, colony)` creates a wall as a special dot: `is_wall: true`, immobile, no primitive ticking, separate decay counter, defend = 0.5
- Walls live in spatial_grid like normal dots; a wall cell appears occupied so dots can't move/spawn into it
- Wall-aware combat resolution: when an attacker beats a wall, the wall is removed but the attacker only advances if the cell becomes empty (i.e., the stack is exhausted)
- `_age_dots` branches on `is_wall`: walls decrement decay counter, dots increment age
- HUD now shows wall count: `p0: N (walls: M)   p1: K`
- `build_upward` added to `CCE_COLORS` (gray-purple)
- Enemy colony spawn commented out for build dev work (single-colony test environment)

### Build Banner Mechanic (block clustering / monuments)
- `BUILD_BANNER_RADIUS = 15`, `BUILD_BANNER_TTL = 6`, `BUILD_START_CHANCE = 0.05`, `BUILD_AT_BANNER_STACK_PREF = 0.8`
- `build_banners` array with unique IDs (separate from rally `banners`)
- Per-dot `build_banners_used` set tracks which banners a dot has already contributed to
- `_execute_build` flow:
  - Look for nearest unused build banner in radius
  - If found and at/adjacent: build in own cell, refresh banner, mark used
  - If found but not adjacent: march toward banner, no build this tick
  - If none found: 5% chance to start new monument (place block in own cell, drop banner, founder marks it used)
- Build always places in dot's own cell — no 8-neighbor scattering, builders that walked to the banner cluster their blocks at that cell
- Stack height: `_create_wall` counts existing same-colony walls in target cell to determine `stack_index`, places new wall at `radius + offset + stack_index * WALL_HEIGHT_STEP` along surface normal
- Active monuments don't crumble: when a new wall is added to a stack, all existing walls in the cell have their decay timer refreshed. Abandoned stacks decay top-down naturally.
- Founder placement defaults to own cell (changed from "any empty adjacent")

### Combat Mechanics Summary (current state)
Each tick, every dot rolls one primitive from its CCE pool weighted by current values. Rolling `attack` searches a 10-cell radius for any foreign dot, marches toward the nearest one if found (or marches toward the nearest friendly rally banner within 30 cells if not), and initiates combat on contact, which drops a 6-tick rally banner at the contact cell for both colonies and locks the attacker and defender in a 3-tick combat cluster (2 ticks if attacker intensity > 0.7). When the cluster expires, each pair compares `attack + defend` power deterministically with ties going to the attacker — the loser dies, the winner advances into the vacated cell unless the cell still contains other entities (e.g. remaining walls in a stack). Pile-ons against a single defender all resolve against that one defender's power.

In actual play, chants don't reshape spawning at all — they add CHANT_WEIGHT (0.08) to every existing same-colony dot's CCE on each chant — so a player chanting "attack" makes their living army incrementally more aggressive while reproduction continues diluting offspring at 70% of parent CCE per generation. Combat strength is a race between the player's chants pumping the existing population up and dilution pulling new dots back down toward neutral. Rally banners act as the connective tissue, taking the diffuse attack-CCE the chant has spread across the colony and concentrating it onto wherever contact actually happens.

### Defense Wall Design (Step 2, NOT YET IMPLEMENTED)
Future work, recorded for continuity:
- Defense banners (separate from build banners) drop anticipatorily based on threat scoring
- Threat score per cell ~= enemy_count * mean_enemy_attack_cce * proximity_falloff
- Banner shape is a rectangular line, perpendicular to threat bearing, sitting between colony center and threat
- Non-combat dots positioned on the line, then build under themselves (rider variant) — wall absorbs first combat, rider fights second
- Rider drops with 1-tick stun when wall destroyed
- Combat banners (existing rally system) suppress build_upward in their radius — no walling during active combat
- Threat scoring: cheapest viable function; possibly periodic global scan every ~5 ticks rather than per-tick per-dot

### Known Issues / TODO
- gather/mark_surface primitives silently do nothing
- No resource system / surface marking system
- No multiplayer / server layer
- CCE dilution still 0.7 — interacts non-trivially with reproduction (intensity falls off generationally, reproduction success collapses) — may want USE_DILUTION flag for clean static-CCE testing
- Defense banners and threat scoring unimplemented
- Rider mechanic for stacked wall+dot unimplemented
- Monument visualization: dots visually overlap with walls they just built (rider rendering not yet wired)
- p1 keeps using fog color even after contact (testing override)
- HUD shows combined CCE across all colonies — should separate per-colony
- Combat is deterministic (a + d power compared, ties to attacker) — probabilistic combat discussed but not implemented; would interact with dilution and noise floor at high generations



---

## Session Notes — continued (post-rally / build-banner work)

### Testing Iteration on Build Mechanic

After first build implementation, observed:
- Walls were forming as lines, not monuments
- Stacking wasn't happening visually
- Builders were placing into 8-neighbors rather than clustering

Iterated through several changes:

1. **First iteration — 8-neighbor scatter with attraction radius**: Builders scanned 8 neighbors, preferred placing in cells adjacent to existing same-colony walls, with a wider 3-cell attraction radius for isolated builders. Produced lines, not monuments.

2. **Second iteration — build banners with 8-neighbor placement**: Added `build_banners` (separate from rally `banners`) with `BUILD_BANNER_RADIUS = 15`, `BUILD_BANNER_TTL = 6`, `BUILD_START_CHANCE = 0.05`. Builders rolling build_upward find nearest unused banner in radius and march to it; if no banner, 5% chance to start one. Per-dot `build_banners_used` set prevents re-using same banner. Still produced lines.

3. **Third iteration — build in own cell**: Changed both founder and follower to build in their own cell. Removed all 8-neighbor scattering. Added `WALL_HEIGHT_STEP` and stack_index tracking — each new wall in a cell renders at `radius + offset + stack_index * WALL_HEIGHT_STEP`. Active monuments refresh decay on all walls in the cell when a new one is added (abandoned ones decay top-down). Monuments started forming, BUT still produced vertical lines aligned with sphere poles.

### Diagnosis of Vertical Line Pattern

The vertical-line bias (lines always grow toward poles, never east-west) is structural:

- Player dot spawns at the equator (`y = 0`)
- Colony grows from there via wander
- When a dot trips the 5% founder roll, it's wherever it happened to be in the spread cloud
- Follower dots roll build elsewhere in the cloud and march toward the banner
- Most followers approach the banner from the direction of the colony center
- Since the spawn cloud is roughly equatorial, founders tend to be slightly north or south of the cloud's centroid
- Followers therefore approach the banner from a consistent direction (pole-ward → equator-ward, or vice versa)
- When a follower's `_is_at_or_adjacent` check returns true, they're typically in the cell on the approach-side of the banner
- They `_create_wall(my_cell, my_colony)` — their *own* cell, which is 1 step away from the banner in the approach direction
- Next follower arrives, lands in the same cell (now occupied by a wall, but they're a dot not a wall so they can co-exist), builds in own cell again — stacks the lateral
- Result: a line extending from the banner toward the colony center, growing pole-ward because of the equatorial spawn

The implementation drifted from the original spec. Original spec was "80/20 stack vs lateral" — but "stack" meant "build at the banner cell" not "build in own cell which happens to be the banner cell sometimes." Builders standing adjacent to the banner build in their *own* cell (lateral), so they essentially never stack the founder block.

### Proposed Fix (UNRESOLVED — START HERE NEXT SESSION)

When a builder is at_or_adjacent to a banner:
- 80% of the time: build at the **banner cell** itself (stacks on founder block — vertical growth)
- 20% of the time: build in the **builder's own cell** (lateral spread in a random direction, since followers arrive from different angles)

This should produce real monuments: tall columns with occasional horizontal protrusions. The protrusions are in random directions because of natural variance in which builders trigger the 20% roll.

Implementation: change `_execute_build` so the at-banner case does:
```
if randf() < BUILD_AT_BANNER_STACK_PREF:
    _create_wall(banner_cell, my_colony)
else:
    _create_wall(my_cell, my_colony)
```

This matches the original 80/20 spec intent and decouples build placement from approach direction.

### UI: Manual Zoom Slider

Added a VSlider node (`UI/ZoomSlider`) for trackpad-zoom workaround on macOS:
- Range: 1.12 (closest) to 3.0 (starting/farthest)
- Vertical orientation, top-left of HUD
- Wired bidirectionally: trackpad/scroll updates slider via `set_value_no_signal`, slider drag updates `zoom_target` directly
- `ZOOM_MAX = 6.0` retained in code but unreachable via slider (cap is 3.0)

### Files Touched
- `main.gd`: rally banners, build primitive, build banners, wall stacking, zoom slider wiring
- `main.tscn`: added `UI/ZoomSlider` (VSlider)
- `DEVNOTES.md`: this file


---

## Session Notes \u2014 2026-05-11 (build mechanic diagnostic)

### Applied the 80/20 fix

Applied the spec'd fix from the previous session: at-banner builders now 80% stack at `banner_cell`, 20% build laterally. Stacking immediately started working visually \u2014 individual towers grew vertically at founder blocks. But towers grew **too fast** with no horizontal spread.

### Scaled stack pref by height

Added `STACK_HEIGHT_SOFTCAP = 10`. Stack preference now decays linearly:
```
stack_pref = BUILD_AT_BANNER_STACK_PREF * clamp(1 - height/STACK_HEIGHT_SOFTCAP, 0, 1)
```
- h=0 \u2192 80% stack / 20% lateral
- h=5 \u2192 40% / 60%
- h\u226510 \u2192 0% / 100%

New helper `_count_walls_in_cell(cell, colony)` for the height check. Same-colony walls only, so an enemy wall in the cell doesn't slow your tower.

### Lateral helper (`_pick_lateral_cell`)

The lateral branch was still building in `my_cell` \u2014 i.e. wherever the follower happened to be standing. Since most followers approach the banner from the same direction (colony cloud geometry), every "lateral" build piled into the same approach-side cell. Added `_pick_lateral_cell(banner_cell, colony)`: pick a random neighbor of the banner, preferring cells with no same-colony walls; fall back to a random neighbor if all 8 are full.

### Lines persisted \u2014 diagnostic logging

Visible behavior after all three fixes: stacking works, but lines still form alongside the towers, growing roughly north. Added test-mode infrastructure to figure out why:

- `TEST_MODE` flag, `TEST_POPULATION = 15`, `LOG_FILE = res://build_log.txt`
- `_spawn_test_population()` seeds 15 dots near the founder, forces all of them to `reproduce = 0` so population stays fixed
- `dot_id` (1..15) assigned per dot via `_next_dot_id` counter
- `_log(line)` appends to LOG_FILE (truncated at session start)
- Every primitive roll logged in `_tick_dot` with `dot_id`, cell, primitive name
- Every wall placement logged in `_create_wall` with builder_id, cell, reason (founder/stack/lateral), and post-build height
- `_tick_num` counter for chronological ordering

### Diagnosis from the log

30 ticks of clean data revealed two distinct issues:

1. **Founder chain** \u2014 `build_banners_used` (the per-dot set tracking which banners a dot has already contributed to) is the line generator. When a dot uses banner A, A is permanently dead to them. Next time they roll build, no eligible banner is in range \u2192 fall through to founder path \u2192 5% start a new monument **right where they're standing**, which is adjacent to A's footprint. Repeat: A, then B next to A, then C next to B, etc. The "lines" are actually a chain of distinct founder towers each just 1-2 cells from the last.

2. **Lateral helper produces height-6 "lateral" builds** \u2014 example from log: `[t26] wall: builder=7 cell=(164,98) reason=lateral height=6`. Tower B's banner sits at cell B, and one of B's neighbors is tower A's cell with 6 walls already on it. `_pick_lateral_cell` falls back through to A when... actually it shouldn't, since A is non-empty. Suspected cause: the banner driving builder 7 is somewhere whose neighborhood includes (164,98), and the lateral helper's empty-check is working but the founder chain has positioned banners such that "lateral" builds keep landing on existing tall stacks. Net effect either way: laterals are reinforcing existing tall towers instead of growing footprints.

### Proposed fixes (UNRESOLVED \u2014 START HERE NEXT SESSION)

A. **Kill the founder chain.** Remove `build_banners_used` tracking entirely. Dots can return to the same banner repeatedly. The 80/20 stack-vs-lateral logic and height-scaling provide enough variety; the cool-down is doing more harm than good. Founder path then only triggers when there's genuinely no monument anywhere within `BUILD_BANNER_RADIUS`.

B. **Expand lateral search to radius 2.** When all 8 banner-neighbors are non-empty, search the ring at distance 2 before falling back. Prevents laterals from stacking onto existing tall towers and actually grows the monument footprint outward.

Do A first \u2014 it may make B unnecessary if the founder chain was the primary driver. Re-run the 15-dot test, read the log, decide if B is still needed.

### Files Touched
- `main.gd`: 80/20 stack fix, `STACK_HEIGHT_SOFTCAP` scaling, `_pick_lateral_cell`, `_count_walls_in_cell`, test-mode infrastructure (`TEST_MODE`, `_log`, `_spawn_test_population`, `_next_dot_id`, `_tick_num`, log calls in `_tick_dot` and `_create_wall`)
- `build_log.txt`: created (game runtime output, gitignore candidate)
- `DEVNOTES.md`: this file



---

## Session Notes — 2026-05-12 (the "lines" were a rendering artifact)

### What we thought was happening

Coming into the session, the prior diagnosis blamed the `build_banners_used` cooldown for producing a founder chain — distinct founder towers each 1-2 cells from the last, reading as a "line." Plan A was to remove the cooldown.

### What was actually happening

Did the cooldown removal anyway (it's a real, independent bug — founders should be allowed back to refresh their own banner). Lines persisted.

Then widened `_is_at_or_adjacent` from `dist_sq <= 2` (3×3) to `dist_sq <= 8` (~5×5) and switched the lateral branch from `_pick_lateral_cell` back to `my_cell`. Lines still persisted.

Pulled the log and tabulated wall-counts per cell:

```
       114 115 116 117 118
y=95    4   7  16   2   3
y=96    8  10   8  11   1
y=97    6  10  16  11   3
y=98    6  13  16   2   2
y=99    3   4   5  11   7
```

A perfect 5×5 footprint. No line. But the user was still seeing parallel "lines" with "one dot's distance" of space between them.

The clue was the *exact* spacing: one dot wide.

- Wall mesh: `0.015 × 0.003 × 0.015`
- Cell spacing at the equator: `TAU/GRID_RES = TAU/200 ≈ 0.0314`
- Wall footprint is exactly half a cell

Adjacent cells with tall stacks render as adjacent pillars, each half a cell wide, with the other half-cell of empty space between them. Three adjacent stacked columns (x=115, 116, 117) read as three parallel rails separated by one-dot gaps. The "lines from two monuments would have met if extended" was also the same artifact — both monuments place walls on the same global lat/long grid, so the pillar-and-gap pattern aligns globally.

It was never a build logic problem. The mechanic was actually working — the 5×5 grid above is genuinely circular-ish with spikes, which is the desired behavior. The rendering just hid it.

### The fix

Single-line change:

```
const WALL_MESH_SIZE = Vector3(0.031, 0.003, 0.031)  # match cell spacing
```

Walls now tile cleanly. Adjacent cells with walls touch. The 5×5 footprint reads as a solid monument with varied-height spikes instead of striped rails.

### Cleanups also made

- `build_banners_used` writes removed from `_execute_build` (both the at-banner and founder branches). The field is still initialized in `_create_dot` and still filtered in `_find_eligible_build_banner` — dormant plumbing, costs nothing, easy to re-enable if needed.
- `_is_at_or_adjacent` widened to `dist_sq <= 8` so builders within ~2-3 cells of a banner participate. Reasonable on its own merits even though it wasn't the actual fix.
- Lateral branch builds in `my_cell` instead of `_pick_lateral_cell(banner_cell)`. Restores the original 80/20 spec intent ("stack at banner / build where you stand"). `_pick_lateral_cell` and `_count_walls_in_cell` are now unused but retained.
- TEST_MODE / LOG_ENABLED split: `TEST_MODE` controls the fixed 15-dot test population, `LOG_ENABLED` controls log writes. Lets us log organic runs without the test-population override. Currently `TEST_MODE = false`, `LOG_ENABLED = true`.

### Visual scale observation (not addressed)

Walls (0.031) are now visibly chunkier than dots (0.015) because the wall mesh now matches the cell, but the dot mesh is still half a cell. Three options discussed:

1. Scale up the world (radius, grid_res, all meshes proportionally) — lots of camera retuning.
2. Double `GRID_RES` to 400 so cell width ≈ dot width — clean, but every radius constant (`RALLY_RADIUS`, `BUILD_BANNER_RADIUS`, `ATTACK_DETECT_RADIUS`) is in cells and would need ~2× to preserve angular behavior.
3. Leave it. Walls being chunkier reads as worldbuilding — dots are living, walls are constructed.

Chose 3 for now. Easy to revisit if it starts looking wrong.

### Lessons

- Tabulating wall-cell counts as a 2D grid would have caught this in one minute on session start. Inferring spatial shape from chronological event logs missed the obvious cell-coordinate structure.
- The wall-mesh-size assumption (half a dot's height, ergo half-cell footprint) was load-bearing in a way nobody had documented. Comment now says "match cell spacing."
- Past-me's diagnoses across sessions had the right vibe (founders chain, approach bias) but the actual cause was downstream rendering. Build logic was probably fine after the iteration-3 fix; we've been iterating on a phantom.

### Known Issues / TODO

- gather/mark_surface primitives silently do nothing
- No resource system / surface marking system
- No multiplayer / server layer
- CCE dilution still 0.7 — interacts non-trivially with reproduction
- Defense banners and threat scoring unimplemented
- Rider mechanic for stacked wall+dot unimplemented
- HUD shows combined CCE across all colonies — should separate per-colony
- Combat is deterministic — probabilistic combat discussed but not implemented
- `_pick_lateral_cell` and `_count_walls_in_cell` are now dead code; remove on a future cleanup pass if confirmed unused
- Wall mesh visual scale relative to dot mesh — left at chunky-walls for now



---

## Session Notes — 2026-05-12 (cont., monument size cap)

### The stickiness problem

Once a banner is dropped, every nearby builder refreshes its TTL on placement. With ~half the colony rolling `build_upward` and a dense cluster around the founder, TTL essentially never decrements — banner is immortal. Result: the colony develops a magnet for the first monument site and never spreads.

### Approach: cap monument size by CCE, throughput by population

User's framing: cap should reflect the colony's *build character* (CCE alone), not population. A small population just takes longer to fill the cap, or never reaches it before the banner times out. A large population fills it fast and moves on. This expresses what the colony "wants to build."

Decided on a per-banner wall count cap. When count hits cap, banner expires immediately (TTL → 0). Builders downstream search for other banners or fall through to the 5% founder roll, naturally redistributing the colony spatially.

### Implementation

- `BUILD_MONUMENT_BASE = 10.0`, `BUILD_MONUMENT_SCALE = 200.0`
- `_compute_colony_avg_build_cce(colony)` averages `build_upward` across **all** living non-wall dots of the colony (entire population, not just active builders — selection bias would inflate the snapshot)
- At founder placement (`_drop_build_banner`), snapshot `wall_cap = round(BASE + SCALE * avg_build)` into the banner
- Banner now has `wall_cap` and `wall_count` fields
- In `_execute_build` at-banner branch: after `_create_wall`, increment `wall_count`. If it hits cap, expire the banner instead of refreshing
- Logging on banner creation and expiry, includes cap and avg_build snapshot

Cap numbers:
- avg=0.10 → cap=30
- avg=0.40 (current `COLONY0_CCE` preset) → cap=90
- avg=0.80 → cap=170

### Test plan (next session)

Three things to validate, in order:

1. **Does the cap fire?** With dilution still off (full_inheritance true for organic spawns), all dots stay at build=0.40 indefinitely, every banner gets cap=90. First monument should hit 90 walls and expire. Founders should fire in new locations. Run and watch logs for `banner: id=X completed at 90/90 walls — expiring` events.

2. **Does the cap scale with CCE?** Re-enable dilution (flip `full_inheritance` back to `false` in `_spawn_dot_near`). avg_build erodes over generations toward zero. Each successive banner should have a smaller cap. Eventually founders rarely fire because caps approach zero and dilution overcomes spawn CCE.

3. **Does chant counter dilution?** Add `build`/`construct` chants to `CHANT_RECIPES` (currently absent — past devnotes flagged this as a deliberate omission while build was unwired, but build is wired now). Chanting `build` adds `CHANT_WEIGHT = 0.08` to every living dot's build_upward, fighting dilution and pumping cap back up.

Doing (1) first in isolation lets us confirm the cap mechanic works without dilution as a confound.

### Files touched

- `main.gd`: BUILD_MONUMENT_BASE/SCALE constants, banner cap/count fields, `_compute_colony_avg_build_cce` helper, cap-check in `_execute_build`, log lines on banner create/expire
- `DEVNOTES.md`: this file

### Known issues / TODO

- Build chant recipes still missing — needed for test (3) and for player to actually influence monument size at runtime
- `_pick_lateral_cell` and `_count_walls_in_cell` still present as dead code (the lateral helper isn't called; the count helper is still used for stack-height softcap calculation, keep it)
- gather/mark_surface primitives still no-ops
- No monument_id on walls yet — wanted this in this session but bumped for next. Banner has an id and now a cap, walls don't carry it through. Easy add when needed for lineage queries.
- Dilution still off by default (full_inheritance true in `_spawn_dot_near`) — flip when ready for test (2)

### Files Touched

- `main.gd`: WALL_MESH_SIZE bump, removed `build_banners_used` writes, widened `_is_at_or_adjacent`, lateral builds in own cell, TEST_MODE/LOG_ENABLED split
- `DEVNOTES.md`: this file


---

## Session Notes — 2026-05-12 (cont., end-of-session discussion: wall mesh variants)

No code changed in this segment. Capturing the discussion thread so it survives the session boundary.

### Reframe: build was always about combat defense

The original intent for the build primitive was **walls during combat**, not monuments. Monuments are what build-CCE dots do when no enemy is around — a side effect of having a primitive with no immediate threat to respond to. We spent the last several sessions getting monument behavior to work, which validates the primitive's mechanics, but the *gameplay* purpose is fortification under attack. Easy to lose sight of with no enemy colony spawned.

### Idea: blocks have varying mesh sizes by context

Trigger: user observed that the old skinny mesh (0.015) was nice-looking *for a wall* and bad for a monument block. What if both exist?

Discussed three variants, in increasing ambition:

**Variant 1 — two block types, decided at placement.**
- Defense block: thin/long mesh, e.g. `(0.031, 0.003, 0.008)`. Placed when a build roll fires inside a rally banner's radius (combat context).
- Monument block: full-cell mesh `(0.031, 0.003, 0.031)`. Placed when no rally banner is in range (peaceful build).
- Same `is_wall: true`, same combat math, just a `mesh_variant` field on the wall.

**Variant 2 — block dimensions scale with CCE.**
- Mesh size correlates with build CCE concentration in the local cloud.
- High concentration → thicker walls, sparse → thinner.
- Several tunable axes, harder to read at a glance. Probably not v1.

**Variant 3 — blocks have orientation, not just footprint.**
- Defense block is a thin slab perpendicular to the threat vector.
- Multiple defense blocks join into a continuous wall facing the enemy.
- Flanking a wall means hitting its short edge.
- Coolest version, also the most geometry work (corners, joining, orientation tracking).

### Lean: variant 1 for v1

Smallest readable change. Rally banner infrastructure already tracks "is combat happening here," so the routing is nearly free. Slots into the original Step 2 design — instead of rally banners *suppressing* build_upward in combat, they *redirect* it to defense walls. The colony doesn't lose its action during combat; it expresses it as fortification.

### Mechanical pairing that fell out of the discussion

If defense walls don't stack and only spread laterally, while monument blocks stack but don't spread as aggressively, the *mechanical* difference matches the *visual* difference matches the *gameplay* difference:

- Defense walls: horizontal line, covers ground, urgent
- Monument blocks: vertical pillar, concentrates, leisurely

A colony that has lived through combat will have both side by side — old monuments from peaceful times, defense walls from when the enemy came. Terrain becomes a record of the colony's history. Worldbuilding for nearly free.

### Open questions parked for later

- Do defense walls and monument blocks coexist in the same cell? Probably not — different cells, different purposes.
- What happens to a defense wall after the threat is gone? Decays? Stays as a permanent fortification? Becomes a monument block?
- Wall orientation (variant 3) is appealing — revisit once variant 1 is in and we see how walls feel.

### Backend / scale anxiety check-in

User raised this and we talked through it briefly. Summary: the client is the design tool. Every mechanic we test locally either survives (and becomes a server requirement) or dies (and saves us server work). The right time for a server-shape sketch is after the next playable slice — combat + build + cap, with both colonies live. Then we write a one-pager on server responsibilities, tick model, message protocol, sharding. For now: keep going on game mechanics.

### Next session

Test plan from earlier in the session still stands. In order:

1. Validate cap fires (dilution off, all caps ≈ 90, banners expire on completion, founders fire elsewhere)
2. Re-enable dilution, watch caps shrink generation over generation
3. Add `build` / `construct` chant recipes, confirm chant counters dilution and bumps caps

Then revisit wall mesh variants once we have an enemy colony in play to actually exercise the combat-build pathway.

- `build_log.txt`: regenerated each session (gitignore candidate if not already)



---

## Session Notes — 2026-05-13 (cap validation, overshoot fix, build rate observation)

### Test 1: cap fires (PASSED)

Ran with dilution off (full_inheritance true) and the per-monument cap as shipped last session. All 18 founders over 85 ticks placed at avg_build=0.400 → cap=90, as expected. The redistribution loop works: when a banner hits cap, builders within radius dry up, fall through to the 5% founder roll, and new monuments start elsewhere.

### Overshoot bug (caught, fixed)

First run of test 1 surfaced an issue from the existing log without needing a fresh session: every banner overshot its cap by 8–24 walls on the cap-hit tick. Mechanism: `_execute_build`'s cap branch sets `banner["ticks_remaining"] = 0`, but the banner stays in the array until `_tick_build_banners()` cleans it up next tick. Within the current tick, every remaining builder who rolls `build_upward` still finds the banner via `_find_eligible_build_banner`, builds another wall, re-trips the cap check, and re-logs "expiring."

One-line fix: added `if banner["ticks_remaining"] <= 0: continue` to the eligibility loop. Banners marked for expiry are now invisible to lookup for the rest of the tick; cleanup still happens via the normal TTL decrement next tick. No state machine surface added — the immediate-removal alternative would have required tracking array indices and creating two exit paths.

Validation: rerun showed each banner with exactly one expire log line at exactly 90/90 walls. Zero overshoot.

### Spatial behavior at avg_build=0.40

After fix, tabulated 18 founders across 85 ticks. Footprint of all walls: 9×27 cells, with the main mass tightly clustered around the original founder. 14 of 18 founders fell within ~10 cells of the first one — they're not "starting farther away," they're starting *inside the previous monument's footprint*, because the 5% founder roll fires from wherever the builder happens to be standing, and builders cluster around the cell they were just at.

Two visible clusters emerged: a large mass at y=88–101 and a smaller one at y=109–114, separated by an 8-row gap of zeros. The southern cluster started at t64 when one wandering dot got far enough from the main cloud to be alone when its founder roll fired — a rare event, but the actual redistribution mechanism in action.

Cell wall counts at the hot spots: (11,92)=77, (10,94)=70, (10,92)=54, (10,95)=51, (10,91)=51. Stacks max around 77 because `STACK_HEIGHT_SOFTCAP=10` decays stack pref toward zero, so once a tower is height ~10 the builders are essentially all going lateral. Lateral:stack:founder ratio over the run was 1387:139:18 (~90:9:1).

### Build rate observation

**Even at build=0.40, build rate is faster than desired.** 1544 walls placed across 85 ticks with a single colony. The blending-into-cities effect the user noted is downstream of this — many overlapping monument footprints stacking up in the same general area. Tuning levers identified but not exercised:

- `BUILD_BANNER_RADIUS = 15` — smaller would make builders give up sooner and fall through to founder roll, dispersing the colony spatially.
- `BUILD_START_CHANCE = 0.05` — controls how often a "no banner in range" builder actually starts a new one.
- Anti-clustering check on founder placement — refuse founder if within some radius of an existing recent banner.
- Lowering `COLONY0_CCE.build_upward` from 0.40.

Tests 2 (re-enable dilution) and 3 (build chants) are deferred. Decision: pivot to **combat wall mechanic** next session — the original gameplay purpose of build_upward — rather than continue monument tuning.

### Files touched

- `main.gd`: added `ticks_remaining <= 0` skip in `_find_eligible_build_banner`
- `DEVNOTES.md`: this file

### Known issues / TODO

- Build rate at build=0.40 is faster than desired — tuning deferred until combat walls give us a reason to revisit
- Founders cluster inside dead monument footprints — no anti-clustering check yet
- Tests 2 (dilution generational decay) and 3 (build chant counter) skipped — pivot to combat walls instead
- Build chant recipes still missing
- `_pick_lateral_cell` still dead code (`_count_walls_in_cell` is live — used by stack-height softcap)
- gather/mark_surface primitives still no-ops
- HUD shows combined CCE across all colonies — should separate per-colony
- Combat is deterministic — probabilistic variant discussed but not implemented
- No monument_id on walls yet



---

## Session Notes — 2026-05-13 (cont., combat-walls design — observe + attack spec'd, defend pending)

This session's design work, no code written. Handing off to Claude Code for implementation; this writeup is the spec.

### Reframe: build was always about combat

Recapping the 2026-05-12 framing for continuity. Monuments validated the build primitive's mechanics, but the gameplay purpose of `build_upward` is **fortification under attack**. Defense walls are the original Step 2 of the wall system (per 2026-05-09 notes); monuments are what build-CCE dots produce when there's no enemy around.

This session designs the combat-walls mechanic from scratch, in the process introducing a new primitive (`observe`) and redesigning attack to fit the new model. Defend, wall banner mechanics, and combat-initiation details are partially specified and flagged below.

### New primitive: Observe

Standalone CCE primitive in the action pool. Weight, rolls like wander/attack/reproduce/etc. Conceptual role: the perception layer separate from the action layer. **Pure passive find** — no side effects beyond setting per-dot pending state.

**Mechanic when rolled:**
- Scans for nearest foreign dot in radius.
- Radius scales with observe CCE: `OBSERVE_BASE_RADIUS + OBSERVE_SCALE * dot.cce.action.observe` cells.
  - Suggested starting values: `OBSERVE_BASE_RADIUS = 3`, `OBSERVE_SCALE = 20`. Observe=0 → 3 cells, observe=0.5 → 13, observe=1.0 → 23. Tune.
- Consumes the tick. No other action this tick.
- Result stored on the dot for one tick: `{enemy: <dot or null>, expires_on_tick: current_tick + 1}`. Cleared on tick N+1 after the action resolves, regardless of whether it was used.

**Stateless** — observation is per-dot, per-tick, no colony-shared marker. Each observe roll starts fresh. (This is a deliberate departure from a "spotter drops a marker" model; the rally banner system already provides colony-shared combat memory, no parallel mechanism needed for observation.)

**The wiring that makes observe interesting:** observe's downstream effect depends on the dot's *other* CCE weights. Observe is the only primitive whose effect is not uniform — it finds, then on the next tick the dot's dominant observe-relevant CCE drives the action.

**Tick N+1 action rule:**
On the tick after an observe roll that found an enemy, **before the regular primitive roll**, the dot checks for a pending observation. If present:
- Highest-weighted observe-relevant CCE drives the tick's action. Skips the normal primitive roll.
- If `attack` dominates → march one cell toward the observed enemy (see Attack spec below).
- If `defend` dominates AND the waller-trigger probability roll succeeds → drop wall banner, build block, climb on, lock (see Defend / Waller spec — pending).
- If neither attack nor defend significant, or the waller-trigger probability fails → observation lapses, dot rolls normally on N+1.
- Pending observation cleared at end of N+1 regardless of outcome.

**Tie-break between attack and defend if equally weighted:** open question, flag for first implementation pass. Suggest random 50/50 until we see how it plays.

**Consequence: 2-tick reaction delay on detection.**
Today: attack rolls, scans, marches in one tick.
Future: observe on N, march/drop-wall on N+1, next scan on N+2 (if observe rolls again).

For an enemy at distance D, closing the gap takes ~2D ticks instead of D, since every other tick is a non-march observe. **First contact is slow, but escalation is fast** — once combat starts and rally banners drop, attack rolls march toward the banner on the *same* tick they roll (no observe delay needed for the rally path). Reads as: patrols are deliberate, fights are intense.

This intentionally slows combat pace. Accept it, don't compensate. Gives time for wall deployment to matter.

### Observe wires into all detection

Today, `attack` does its own scan within `ATTACK_DETECT_RADIUS = 10`. Under the new model, observe is the **only** detection mechanism. Attack loses self-scan entirely; detection-driven attack behavior fires via the tick-N+1 hook above.

This means **colonies need observe baseline to function**. Pure-attack-zero-observe colonies are blind — they never spot enemies, can only join fights via the rally banner path (which requires *someone* in the colony to have started a fight, which requires *someone* to have observed). Seed `COLONY0_CCE`, the enemy preset, and likely `NEUTRAL_CCE` with non-zero observe weights so colonies aren't useless at game start. Tuning values TBD; start by mirroring whatever attack weight a preset has.

Design payoff: "intelligence" (chant alias for observe) becomes universally meaningful, not a niche stat. A high-intelligence pure-defender colony spots threats early. A high-intelligence attacker engages faster than a low-intelligence one. Etc.

### Attack — pure march-toward-rally-banner primitive

Under the new model, the attack primitive itself does almost nothing exciting. All the detection-and-pursue behavior moved to observe's tick-N+1 hook. Attack is now:

**When the attack primitive fires (no pending observation):**
- Friendly rally banner in `RALLY_RADIUS` → march one cell toward it. (Same as today's rally fallback.)
- No rally banner in range → **inert**. The dot rolled attack and did nothing this tick.

**Inert vs wander-fallback was a design decision.** Locked in inert. Reasoning: cleanest expression of "observe gates everything." Wander-fallback would muddy the line between attack and wander. A high-attack-zero-observe colony being helpless until they've stumbled into a fight is the intended consequence — reinforces that intelligence is universally valuable. The dot wasted a tick, that's fine, the engine is probabilistic, the next roll might be more useful.

**Attack-with-pending-observation does NOT route through `_execute_attack`.** That path is the tick-N+1 hook: one cell toward the observed enemy, using `_is_foreign_in_exact_cell` (loose — can step adjacent, can't step onto a foreigner). No combat initiation inside this path either — that's the adjacency layer's job (see below, pending).

**Combat initiation moves out of attack entirely.** Today `_execute_attack` calls `_initiate_combat` on contact. Future: `_initiate_combat` fires from the adjacency-triggers-combat layer (see pending section) whenever any motion primitive ends with the dot adjacent to a foreigner. Attack no longer owns combat initiation.

**Cleanup needed in `_execute_attack` when this is implemented:** remove the self-scan, remove the call to `_march_toward` (only `_march_toward_banner` survives), remove the `_initiate_combat` call. `ATTACK_DETECT_RADIUS` constant becomes unused — leave for cleanup pass.

### Waller-trigger probability shape (Shape D)

When observe finds an enemy and defend dominates, the dot may trigger waller-drop. **Probability per qualifying observe roll**:

```
P(waller-drop) = clamp(dot.defend * dot.build_upward * WALLER_TRIGGER_SCALE, 0, 1)
```

- Pure-defender (defend=0.5, build=0.0) → 0% chance, never wallers.
- Pure-builder (defend=0.0, build=0.5) → 0% chance, never wallers.
- Balanced (defend=0.3, build=0.3) with SCALE=1.0 → 9% chance per observe-roll-that-finds-enemy.
- Strong balanced (defend=0.6, build=0.6) with SCALE=1.0 → 36%.

Tunable constant. Smooth interaction with chants (no thresholds, no cliffs). Matches engine pattern (everything is probabilistic, nothing is binary unlock).

**Cost of D vs threshold:** guaranteed wall response is impossible. High-defend-high-build dots are *likely* to wall but not certain. Considered acceptable — combat is chaotic, not every defender drops everything.

### Defend / wall banner / combat initiation — DESIGN PENDING

Spec for these was in progress when the session ended. Below is what was locked plus open questions.

**Locked:**
- Wallers are dots where `defend * build_upward` rolled successful per Shape D above, *after* an observe roll found an enemy.
- Waller-drop behavior at a high level: drop wall banner, build a half-thickness block in own cell oriented long-axis-toward-enemy, climb on top of the block, lock (no rolling any primitive including observe).
- Wall block visually looks like a wall (thin, oriented along threat tangent), not a monument cube.
- Other wallers respond to the wall banner by marching to it and placing their own blocks adjacent, extending the wall line perpendicular to the threat bearing.
- Combat hits land on the wall first. When wall dies (combat or decay), the waller unlocks, drops back to surface (visual only — already at that cell), resumes normal rolling.

**Open questions to resolve:**
1. **Combat initiation under A2.** Decided in principle: any two foreign dots in adjacent cells initiate combat, regardless of which primitive either rolled. Two sub-questions deferred:
   - **Sub-2a (foreign-cell-blocking):** today, `_is_blocked_by_foreign` (cell + 8 neighbors) blocks wander/reproduce/defend from stepping adjacent to foreigners; only attack's march uses the looser `_is_foreign_in_exact_cell`. Under A2, which primitives keep strict vs loose blocking? Proposed: all motion primitives go loose *except* reproduce-spawn-placement, which stays strict (don't spawn babies into combat). Not finalized.
   - **Sub-2b (where adjacency check lives):** per-movement (each primitive checks at end of move) or per-tick global scan (one function at end of tick). Proposed: per-movement, composes better with new primitives. Not finalized.

2. **Defend primitive under the new model.** Today defend = march toward colony center. With observe doing detection, does defend also gain an observe-driven branch (defend with pending observation → ???), or is defend's role purely "march home"? If wallers are the defend+observe interaction, what does pure-defend (high defend, low build) do when it observes an enemy? Tagged for next session.

3. **Wall banner specifics.** Banner type separate from rally and build banners. Open: radius, TTL, how second-wallers orient their block relative to first-waller's, when the banner expires (wall complete? cap? threat gone?), what "complete" even means for a wall.

4. **Wall banner vs build banner priority.** If a waller is in range of both an active wall banner and an active build banner, which wins? Lean: wall banner (combat is urgent). Not finalized.

5. **Wall mesh + orientation.** Half-thickness compared to monument blocks. Orientation: long axis perpendicular to threat bearing (i.e., long axis parallel to a tangent perpendicular to the vector pointing at the enemy). Today wall meshes don't have orientation — they're axis-aligned cubes on the sphere. Implementing oriented walls means computing a local frame at the wall cell and rotating the mesh into it. Doable but new.

6. **Combat-tick interaction.** Today `intensity > 0.7` shortens combat from 3 ticks to 2. Question raised: if defense walls are about *delaying* combat, intensity-shortened combat may be the thing they're racing against. Worth revisiting whether intensity-shortening should also apply to wall-mediated combat, or only to dot-on-dot.

### Test environment needs

To exercise combat-walls, enemy colony spawn must be re-enabled. Currently commented out for build dev (per 2026-05-09 notes). Uncomment `_spawn_enemy_colony()` and likely tune the enemy preset — current preset is attack 0.40, wander 0.40, reproduce 0.32, no observe. Under the new model that colony would be blind. Suggest seeding both colonies with `observe = 0.3` or so as a starting point.

### Suggested implementation order

1. Add `observe` to CCE schema, color system, neutral baseline, both colony presets. Wire into chant aliases ("observe", "intelligence", "watch", "scan", "intelligent").
2. Implement observe primitive: roll, scan, set pending state. No downstream action yet — verify pending state appears and clears correctly via logging.
3. Implement tick-N+1 pending-observation hook: for attack-dominant case, march toward enemy. Test with single-colony, enemy commented out (so observe always returns nothing — verify no crashes, observe rolls cleanly).
4. Re-enable enemy colony. Verify observe finds them, attack-pending-observation marches toward them.
5. Refactor `_execute_attack`: remove self-scan and `_initiate_combat` call, keep only rally-banner march. Add adjacency-triggers-combat layer (A2). Verify combat still initiates correctly, now via adjacency rather than attack.
6. Design defend / wall banner / waller-drop sequence (this is the next design session, not next implementation step). Then implement.

Steps 1–5 are the foundation. Step 6 is where wall mechanics actually appear. Splitting them keeps each commit focused and lets us validate the perception/action redesign before piling wall logic on top.

### Files this design will eventually touch (forecast)

- `main.gd`: new constants (`OBSERVE_BASE_RADIUS`, `OBSERVE_SCALE`, `WALLER_TRIGGER_SCALE`, wall-banner constants TBD), `observe` added to action CCE, `_execute_observe` and pending-state plumbing, tick-N+1 hook in `_tick_dot`, `_execute_attack` refactor, adjacency-triggers-combat layer, eventual waller-drop and wall-banner logic.
- `CHANT_RECIPES`: observe/intelligence aliases.
- Colony presets: add observe weights to `COLONY0_CCE`, enemy preset, `NEUTRAL_CCE`.

### Known issues / TODO

- Defend primitive design pending — interaction with observe TBD
- Wall banner spec pending (radius, TTL, completion, priority vs build banner)
- Wall mesh orientation logic doesn't exist yet
- Combat initiation layer (A2) sub-questions pending (2a foreign-blocking, 2b check location)
- Tie-break rule for equal attack/defend on observe-pending tick — currently spec'd as random 50/50
- Enemy colony spawn still commented out — re-enable before combat-walls work begins
- Both colony presets and `NEUTRAL_CCE` need observe weights added or colonies will be blind
- Combat is deterministic; probabilistic combat still on the long-term list


---

## Session Notes — 2026-05-28

### North Star architecture adopted

Adopted the procedural-civ-primitives design report as the project's target architecture. Key frame: a three-tier model.

- **Tier 1 — Verbs:** atomic per-dot primitives (wander, observe, attack, defend, reproduce, gather, build_upward). These are what the CCE engine already drives.
- **Tier 2 — Modes:** emergent colony-scale behaviors assembled from weighted primitive combinations (patrol, fortify, swarm, etc.). Not yet implemented — the current engine produces proto-modes organically but doesn't name or track them.
- **Tier 3 — Motifs:** named persistent structures or states that arise from sustained mode activity (monument, wall line, forward camp). Already partially present in the build/wall system.

Refactor strategy: incremental alongside the current engine, not a rewrite. Tier 1 work continues uninterrupted; Tier 2/3 framing guides design decisions as new mechanics are added.

### New resource subsystem decided: soul

A colony-level scalar resource called **soul** will enter the world as collectible specks on the sphere surface.

- **Source:** specks spawn at random surface positions on the world tick. Spawn rate and spatial distribution TBD.
- **Collection paths:** wander = incidental (dot happens to pass through a speck cell), gather = directed (gather primitive actively seeks nearest speck).
- **Consumption:** build consumes soul from the colony pool; combat plunders pool-to-pool on dot kill; exchange (TBD primitive) equalizes pools between aligned colonies.
- **Monument generation:** monuments passively generating soul is a natural loop (build consumes soul, monuments produce it) — deferred until basic collection and consumption are working.

**Open questions:**
- Spawn rate constant and target equilibrium soul density on the sphere.
- Universal vs. selective consumption: does every `build_upward` roll cost soul, or only specific build acts?
- Monument generation rate and whether it gates on monument height or count.

### Shipped: soul speck spawn + render (commit dd01951)

- `var specks = []` added alongside `dots`/`dot_data` at world-state scope.
- `_create_speck(dir: Vector3)`: creates `MeshInstance3D` (BoxMesh `0.008 × 0.003 × 0.008`), warm-gold emissive material (`Color(1.0, 0.85, 0.2)`, energy 1.2×), positioned at `dir.normalized() * (SPHERE_RADIUS + DOT_SURFACE_OFFSET)`, added as direct child of Main, appended to `specks`.
- `_tick_specks()`: 50% chance per tick to call `_create_speck` at a random grid-cell direction via `_cell_to_dir(Vector2i(randi() % GRID_RES, randi() % GRID_RES))`.
- Hooked into `_process` tick block after `_tick_all_dots()`, before `_update_hud()`.
- **Does NOT touch:** `dots`, `dot_data`, `spatial_grid`, or any existing tick function. Fully parallel structure.
- Spawn + render only. No collection, no pool, no removal, no dot interaction.

### Shipped: soul speck collection mechanic (commit 92e40d9)

- `"collect_lock": null` added to `dot_data` initializer in `_create_dot`, alongside `"pending_observe"`.
- Lock-guard inserted in `_tick_all_dots` after the existing `combat_locked` and `is_wall` guards, before `_tick_dot`. On the resolution tick (`lock["until_tick"] == _tick_num`): if the speck is still in `specks`, call `queue_free()` and erase it; in all cases set `collect_lock` back to `null` and `continue` (skip `_tick_dot`).
- Collision check appended to `_tick_dot` after `_execute_primitive` returns: compute `my_cell = _cell_key(dot.position.normalized())`, scan `specks` for a matching cell, set `collect_lock = { "until_tick": _tick_num + 1, "speck": speck }` on first match and break.
- Tick order flipped: `_tick_specks()` moved to run **before** `_tick_all_dots()` so specks spawned this tick are immediately collidable within the same tick.

### Collection mechanic design decisions

- **Simultaneous arrivers:** two dots landing on the same speck cell in the same tick both set a `collect_lock`. The first to resolve frees the speck; subsequent resolutions find it gone and clear silently. Rule: *the lock is the receipt* — whatever quantity the pool stage eventually grants will be granted to both. Intentional; exploits the probabilistic engine rather than fighting it.
- **Late arrivers:** a dot arriving on a speck cell on tick N+1 (the existing lock's resolution tick) finds the speck already gone after the first resolution fires within that tick's loop. The arriving dot never sets a lock because the collision check runs after `_execute_primitive` and the speck is no longer in `specks` by the time the late arrival's scan runs. Correct by ordering.
- **Newborn dots:** a dot spawned by `reproduce` into a speck cell has its first `_tick_dot` run naturally; the collision check fires at the end and sets a lock. No special-casing needed or added.
- **Combat interruption:** a dot whose `collect_lock` resolution is delayed past `until_tick` (because `combat_locked` fired before the lock-guard on the resolution tick) will clear the lock without removing the speck. Modeled as "hard to collect while in combat." The speck remains and can be collected by another dot. Accepted edge case; not worth complicating the guard for.
- **Lock state shape:** `{ "until_tick": int, "speck": <node ref> }` rather than a boolean. Stores the speck reference so the resolution handler knows exactly which node to free without a second scan. The integer leaves room for CCE-modulated variable lock durations later (e.g. `gather` CCE reducing lock duration).

### Verification

Verified end-to-end with a throwaway HUD counter (`Collections: N`), reverted before commit. Three confirmed resolutions observed in play. Collection rate is low relative to speck spawn rate because colony 0 dots are heavily occupied by build-banner activity and rarely wander into speck cells.

### Next stage: colony-level soul pool

The `collect_lock` resolution currently does nothing beyond removing the speck. Next: increment a per-colony scalar `soul_pool[colony]` on resolution. Display in HUD. No spending logic yet — pool accumulates freely. This is the "resource pool" stage referenced throughout the design.

### Open design questions carried forward

- Spawn rate constant and target equilibrium speck density on the sphere.
- Universal vs. selective soul consumption: does every `build_upward` roll cost soul, or only specific acts (e.g. founding a monument, not stacking)?
- Monument soul-generation snowball balance: if monuments generate soul and build consumes it, a large monument advantage compounds. Needs a cap or decay mechanism.
- Whether `wander` should be the incidental collection path or whether collection should require an explicit `gather` roll to keep primitives semantically clean.

### Shipped: colony-level soul pool (commit 0e21e24)

- `var soul_pool = {}` declared alongside `colony_counts` and `wall_counts` — same `colony_id → int` dict, same lazy-init pattern (`.get(colony, 0)` on every read and write, no explicit pre-init).
- Increment inserted in `_tick_all_dots` collect-lock resolution path, **outside** the `if lock["speck"] in specks:` block — fires for every resolved lock regardless of whether the speck was still present. Simultaneous arrivers each credit their own colony's pool. The lock is the receipt.
- HUD first line extended: `"p0: %d (walls: %d, soul: %d)   p1: %d"`. Empty-dots and wiped-out early-return paths deliberately unchanged — soul is silent when the colony is absent or wiped.
- No spending logic. Pool accumulates freely.

### Design clarification: enemy/NPC colonies are a testing fixture

Enemy colonies are not a permanent game element. Multi-population dynamics (combat, exchange, plunder) are between actual player-controlled colonies, not human-vs-NPC. This shapes everything downstream: the "monument soul-generation snowball" and "exchange equalizes pools" design notes both assume parity between colonies. Enemy soul is not displayed in the HUD; display will be added when inter-population soul movement (exchange, plunder) is implemented.

### Implementation note: multi-line git commit messages via OS.execute

`OS.execute("git", ["commit", "-m", msg], output, true)` silently drops multi-line messages — exits 0, empty output, no commit created. Reliable path: write the message to a temp file and use `git commit -F <tempfile>`, then delete the file. Observed and confirmed this session.

---

## START HERE NEXT SESSION

Resource system is complete enough for design work on the primitives. Specks spawn, dots collect, colonies accumulate. The next stage is **not** another resource feature — it's revisiting the primitive set in light of the working resource system.

The North Star report's Tier 1 verb set is the reference:
`move, gather, build, reproduce, exchange, teach, ritualize, defend, attack, incorporate`

Adoption is incremental. Likely flow for the next session:
1. Design discussion: which existing primitives map cleanly to North Star verbs, which need to be added, which need refactoring.
2. Identify the smallest first primitive-layer change.
3. Implement only that change — no sweeping refactor.

**Still-open design questions (unchanged from earlier this session):**
- Spawn rate / world supply cap for soul specks.
- Universal vs. selective soul consumption across primitives.
- Monument soul-generation snowball balance (cap or decay mechanism needed).

**New open question for the primitive work:**
Dots are heavily occupied by build-banner activity, so collection rate is low. This was acceptable when the pool had no effect, but may need revisiting once primitives actually consume soul — a colony that can never collect enough soul to act is a dead design.


---

## Session Notes — 2026-06-01 (primitive revisit, session 1)

Began revisiting the Tier 1 verb set against the North Star, now that the soul/speck system is working substrate.

### Decisions

- **Collection stays ambient for now** — soul collection remains a primitive-agnostic tick-level effect (any dot ending its tick on a speck cell collects). Confirmed working; gather refactor deferred, collection to be tuned when gather is wired as a real CCE verb.
- **Renamed primitive `wander` → `move`** (North Star Tier 1 name). Pure key rename, behavior identical (undirected drift, range/spiral dials, foreign-block). 8 literal sites in `main.gd`: NEUTRAL/COLONY0/COLONY1 motion keys, `CCE_COLORS`, three `CHANT_RECIPES` inner payloads, `_execute_primitive` match case. Generic consumers (selection pool, `_update_dot_color`, `_update_hud`, log) follow the key automatically.
- **Outer chant trigger words `"wander"`/`"explore"`/`"roam"` left intact** as player aliases — typing "wander" still raises `move`. No "move" trigger added (separate UX call, deferred).
- **Verification:** `validate_script` clean; grep confirmed 1 "wander" literal remaining (line-124 trigger) and "move" at all 8 sites; visual confirmed in editor (drift + gold color intact).

### Open threads

- **observe** — only live primitive producing nothing: writes `pending_observe` (tick+1) that nothing reads; overlaps attack's own radius-10 self-scan. Next decision: observe as the detection layer attack consumes vs. cut as redundant.
- **Scattered locomotion** — movement is `move` plus ad-hoc marches inside attack/defend/build_upward. Open whether those consolidate under `move` later. Not touched this session.
- **gather refactor + collection tuning; chant trigger-word naming** — both deferred.


### Observe refactor — Stage 1 (scan everything, persist until consumed)

Design session established a 3-level verb taxonomy:
- **Atomic operations** (building blocks): move, observe
- **Naked verbs** (fire standalone): build, reproduce, ritualize, exchange, teach, incorporate
- **Composite recipes** (emerge from observe+move sequences): gather, defend, attack

Key design decisions:
- **observe promoted to foundational atomic op** — the shared sensing primitive composite recipes consume.
- **Scans for everything**: enemies, specks, allies, build banners within radius. Dumb sensor, no filtering by intention.
- **Persist until consumed**: no expiry. Observations overwrite on re-roll (one per dot). Consumed by move in Stage 2.
- **Move consumes observations** (Stage 2, not yet built): when a dot rolls move with a pending observation matching a CCE weight (e.g., gather > 0 + speck), move becomes directed. Multiple matches: highest CCE weight wins. Threshold: > 0.0.
- **spiral parked as motif-layer material**; move defined as pure null-random drift + magnitude rides move weight.

**Implemented (Stage 1, this commit):** Rewrote `_execute_observe` to scan four entity types. New `pending_observe` = `{enemy, speck, ally, banner}`, each entry `{pos, dot/node}` or null. Dropped `expires_on_tick`. New helper `_find_nearest_ally_in_radius`. No consumer wired yet.

**Flagged:** distance-metric inconsistency — enemy/ally use non-wrapping box distance, speck/banner use torus-wrapped circular. Matches existing function patterns; harmonize later if needed.

**Design docs produced this session** (chat outputs, not in repo): `primitive_system_design_sketch.md` (full taxonomy + open questions), `pr_evaluation_worked_example.md` (NS formula walkthrough with numbers).

### Next: Stage 2 — move consumes observations

Wire the move case in `_execute_primitive` to check `pending_observe`, match against CCE weights, compute directed step toward target, validate target still exists, consume the observation. First composite recipe (gather = observe + directed move + ambient collection) works at runtime.

## Session 2026-06-08 — North Star P(r) softmax selection

- Replaced the linear roulette chooser in _tick_dot with NS softmax:
  P(k) = exp(score)/Σ exp(score) over the unchanged >0.0 weight pool.
  score = A + M + T + S_am + S_at + S_mt + C + E + H; only A is live
  (binds current CCE weight; chant still folded into A via _apply_recipe).
  The other eight terms are zeroed slots, each a one-line activation.
  Raw exp, no temperature/scale — flatter distribution accepted.
- Selection set, observe/move handling, ambient collection, attack
  self-scan, and dials all unchanged. Other NS systems (decay,
  inheritance, contagion, intensity) out of scope.
- Verified via temporary per-colony/verb counter + JSON dump (since
  stripped). Tick-200 run, colony 0, 1000 dots, 108,847 selections:
  build_upward 26.8%, move 26.8%, reproduce 26.7%, observe 19.7% —
  matches predicted softmax (~26.7% each for the three 0.40 verbs,
  ~19.8% observe). Only the four live verbs appeared (filter confirmed).
  Wall-gating did not suppress build's selection share.
- Single-colony finding: scene instantiates colony 0 only (~1000-dot
  population cap); COLONY1_CCE exists as a constant but is never spawned.
  Orthogonal to this refactor; two-colony spawn deferred as separate work.
- CORRECTION: Stage 2 (move consumes pending_observe) was never
  implemented — prior handoff/DEVNOTES were ahead of the tree.
  pending_observe is still write-only (set in _execute_observe, no
  consumer). Stage 2 remains pending.
- "Build focused" rebalance: moot. Build is selected at the same ~27%
  as move/reproduce; any build-heavy look is structure accumulation,
  not selection.

	
	---
	
	## Session Notes — 2026-06-09 (Stage 2 — move consumes pending_observe)
	
	### Shipped: move consumes pending_observe (speck -> gather)
	
	The first composite recipe is wired. `pending_observe` is no longer write-only — the `move` primitive now consumes it.
	
	- New const `OBSERVE_MOVE_MAP = { "speck": "gather" }` — maps a `pending_observe` key to the `cce.action` verb that claims it. One pair today; extending is a one-line edit.
	- Consumer block at the top of the `move` case in `_execute_primitive`, before the drift:
	  - Null-guard the `pending_observe` field (it's `null` until first observe and after consumption).
	  - Loop the map: a candidate exists when the observation entry is non-null AND the mapped verb's CCE weight > 0.0. Highest weight wins; strictly-greater comparison keeps the first map entry on ties (deterministic).
	  - On a match: `_march_toward_dir` one cell toward the observed `pos`, set `pending_observe = null` (consume), skip drift this tick.
	  - No match: existing undirected drift unchanged, observation persists (overwritten on next observe). "Persist until consumed."
	
	### Design decisions (planner)
	
	- **Only `speck -> gather` wired.** Deliberately NOT wiring the other three observation entries: `enemy -> attack` belongs to the still-open combat-walls redesign (2026-05-13; defend-under-observe, A2 adjacency combat, wall banners all unresolved); `banner -> build_upward` would collide with the existing `_execute_build` banner march; `ally -> ?` has no defined verb semantics. Each is later a one-line map entry.
	- **pos-only marching.** Consumer reads `pending_observe[key]["pos"]` (a normalized dir) only, never the node/dot/cell ref. Kills the stale-ref class and the per-type key-name inconsistency (`dot`/`node`/`cell`) in one move. A stale target = marching at a now-empty cell, harmless.
	- **`_march_toward_dir` reused unchanged.** Accepts its loose single-cell foreign block (`_is_foreign_in_exact_cell`, vs undirected move's 3x3) and its fixed `CELL_STEP` magnitude (ignores range/spiral dials). Tightening either is deferred tuning that would apply equally to a future combat march. The 2026-06-01 "magnitude rides move weight" line remains an aspiration, unimplemented.
	
	### Verification
	
	- `validate_script` clean after wiring and again after stripping scaffolding.
	- gather is unraisable in normal play (default weight 0, no gather chant trigger in `CHANT_RECIPES`), so the branch was exercised via temporary scaffolding: gather seeded to 0.3 on `COLONY0_CCE`, specks temp-spawned near the colony, temp print in the directed branch. Directed-march fired 52+ times across many distinct dots (ids 1-51), including diluted children that inherited gather — confirms the inheritance path carries the new weight. No-match dots kept drifting; no runtime errors.
	- All scaffolding stripped before review: gather reverted to 0.0, temp print removed, `_tick_specks` restored. Working tree left `M main.gd` only (keeper = const + consumer block). No `build_log.txt`.
	
	### Ambient-collection leg already existed
	
	The "collection" half of the gather composite was already wired (`collect_lock` set when a dot ends its tick on a speck cell; collection resolves and credits `soul_pool`). Stage 2 supplied only the directed-move leg. The composite (observe -> directed move toward speck -> ambient collect) is now mechanically complete end-to-end.
	
	### Next / still open
	
	- **gather chant trigger** is the obvious unblock — without a `gather`/`collect`/`harvest` alias in `CHANT_RECIPES`, gather can't be raised > 0 in play, so the composite is correct but unreachable by the player. Deferred as separate UX/vocabulary work (chant trigger-word naming has been parked repeatedly).
	- enemy/ally/banner observation consumers remain unwired; `enemy -> attack` is gated behind the larger combat-walls design.
	- Distance-metric inconsistency (enemy/ally box distance vs speck/banner torus) still flagged, cosmetic, untouched.
	
	
	---
	
	## Session Notes — 2026-06-09 (cont., rename build_upward -> build)
	
	Pure key rename of the action-CCE verb `build_upward` -> `build`. The `_upward` suffix baked in a direction that's merely the only current build option; the verb is `build` (cf. naming `move` rather than `move_tangentially`). Same shape as the 2026-06-01 `wander -> move` rename. Behavior identical — generic consumers (selection pool, `_update_dot_color`, `_update_hud`, logs) follow the key automatically.
	
	- 7 literal sites in `main.gd`: comment (line 57), `NEUTRAL_CCE`, `CCE_COLORS`, `COLONY1_CCE`, `COLONY0_CCE`, `_execute_primitive` match case, `_compute_colony_avg_build_cce` (`.get(...)` key).
	- Untouched: all `BUILD_*` constants, `_execute_build`, `build_banners`, `OBSERVE_MOVE_MAP`, selection logic, chant recipes (no build alias exists).
	- Verified: zero-residual grep in `main.gd`; project-wide `.gd` scan confirms no stray `build_upward` anywhere; `validate_script` clean.
	
	Note: the build verb is named generically now, but build still only places blocks upward (single direction is the sole option today). The rename is forward-looking — directionality becomes a property of the build act later, not the verb's identity.
	
	(Mid-session environment hiccup: Claude Code's terminal lost OS-level filesystem access (macOS TCC) before the first attempt; the Godot editor process retained access. Resolved by restarting the Code session. No code impact.)
	
	
	---
	
	## Session Notes — 2026-06-09 (cont., refactor catalog + landmine comment pass)
	
	### Refactor-candidate inspection (no edits)
	
	Ran an inspection-only refactor-candidate pass over `main.gd` (catalog produced in chat, not committed). Triaged into do-now-safe (Tier A) / defer (Tier B, no behavioral-equivalence harness exists) / never-touch (intentional) / needs-decision. Key rule reaffirmed: behavioral equivalence is unverifiable cheaply here (no test suite, stochastic per-tick sim), so only inspection-obvious changes (comments, renames, constant promotion) are in scope; dedups/extractions deferred until we're in that code functionally or build a seeded-RNG tally harness.
	
	### Shipped: landmine comment pass (comments only, zero executable change)
	
	Documented load-bearing assumptions at their code sites and fixed stale/half-true comments. `validate_script` clean; `git diff` confirmed comments-only. Sites:
	- `dot_data` schema comment rewritten to the real live-dot record + wall-record variant (was 3 fields, stale).
	- collect-lock resolution: "the lock is the receipt" — credit is outside the speck-in-specks check on purpose.
	- `CCE_DILUTION`: birth-time / between-generations only, never within a lifetime; **currently inert** because `_spawn_dot_near` passes `full_inheritance=true` (testing posture).
	- Newborn append-during-`for-in` in `_tick_all_dots` is intentional (newborns tick same pass), not a hazard.
	- `_process` tick-order constraints (specks→dots, combat→dots, age→center).
	- `ticks_remaining <= 0` skip in `_find_eligible_build_banner` is the cap-overshoot fix, not routine filtering.
	- Exact-cell vs 3x3 foreign-check granularity rationale (march-to-the-line vs separation).
	- Box (non-wrapping) vs torus distance metric — accepted choice.
	- `player_dot` fallback may resolve to a wall/enemy dot (harmless today).
	- `_remove_dot` synchronous-removal note mirrored onto the function.
	- `_pick_lateral_cell` marked intentionally-retained dead code (+ the only correct `+ GRID_RES` seam-wrap idiom).
	- `build_banners_used` marked dormant (never written).
	- Reserved-list comment reworded: gather has no match-case executor but its weight is NOT inert — it gates directed move via `OBSERVE_MOVE_MAP`.
	
	### Parked for combat-walls pre-work (NOT fixed — functional, out of cleanup scope)
	
	Two functional findings surfaced by the inspection, both confirmed by reading the actual code (not just hypotheses), both near-zero incidence today (single equatorial colony, no combat), both landing exactly where the combat-walls work will:
	
	- **F1 — collect_lock can stall a dot until age-death.** In `_tick_all_dots`, the `continue` runs whenever `collect_lock != null` but the lock is only cleared on the `until_tick == _tick_num` branch. If that resolution tick is skipped because `combat_locked` fired first that tick, the lock is never cleared and the dot skips `_tick_dot` every subsequent tick (still ages, dies at DOT_LIFETIME). DEVNOTES 2026-05-28 describes the *intended* behavior as "clear without removing"; the code does not do that. Decide intended semantics, then fix — when combat work begins, verify with a repro first.
	- **F2 — negative-modulo seam gap.** Neighborhood scans use `(key.x + du) % GRID_RES` with negative `du`; GDScript `%` truncates (`-1 % 200 == -1`), which never matches a 0..199 grid key, so 3x3/radius scans silently see nothing across the u=0/199 seam. `_pick_lateral_cell` and `_torus_cell_dist_sq` wrap correctly (`+ GRID_RES`). Affects foreign-blocking and enemy detection at the seam. (Separately: torus-wrapping the v axis is geometrically wrong — v=0 and v=199 are near opposite poles.) Verify + decide before combat work.
	
	### Remaining cleanup queue (do-now-safe, not yet done)
	
	- N1: rename `banners` -> `rally_banners` (4 touchpoints) — kills the `banners`(rally) vs `pending_observe["banner"]`(build) reader trap.
	- M1–M5: promote magic numbers to constants (esp. `SPECK_SPAWN_CHANCE`, an open tuning lever currently a literal).
	
	Deferred: all Tier B dedups/extractions (U1/U4/U5/U6/U7/U8/T1), N4 wall->block mass rename (project-parked), low-value constants/notes. Dropped: L11 (colony-center-includes-walls is a gameplay-design question, not cleanup).
	
	
	---
	
	## Session Notes — 2026-06-09 (cont., N1 rally-banner rename)
	
	Renamed the rally-banner cluster to `rally_*` for symmetry with the already-explicit `build_*` banner naming, killing the bare-`banners` reader trap (ambiguous against `build_banners` and the `pending_observe["banner"]` key). Pure whole-identifier rename, behavior identical, `validate_script` clean.
	
	- `banners` -> `rally_banners`
	- `_drop_banner` -> `_drop_rally_banner`
	- `_tick_banners` -> `_tick_rally_banners`
	- `_march_toward_banner` -> `_march_toward_rally_banner`
	
	Substring hazard handled: all `build_*` banner identifiers (`build_banners`, `build_banners_used`, `_drop_build_banner`, `_tick_build_banners`, `_refresh_build_banner`, `_find_eligible_build_banner`) confirmed untouched. Rally-context prose comments still say "banners" — left as-is (non-ambiguous in context; no-opportunistic-cleanup).
	
	Remaining do-now cleanup: M1–M5 magic-number constant promotions (esp. `SPECK_SPAWN_CHANCE`).
	
	
	---
	
	## Session Notes — 2026-06-09 (cont., M1–M5 constant promotions)
	
	Promoted five tuning literals to named constants (Tier A, behavior-identical). `validate_script` clean.
	
	- `SPECK_SPAWN_CHANCE = 0.5` — speck spawn roll in `_tick_specks`.
	- `REPRODUCE_CHANCE_MIN = 0.1` / `REPRODUCE_CHANCE_MAX = 0.9` — reproduce `lerp`.
	- `MOVE_NUDGE_MIN = 0.01` / `MOVE_NUDGE_MAX = 0.08` — undirected-drift `lerp` in the `move` case.
	- `COMBAT_INTENSITY_THRESHOLD = 0.7` — combat-shortening comparison in `_execute_attack`.
	- `BUILD_FOOTPRINT_DIST_SQ = 8` — squared torus-distance threshold in `_is_at_or_adjacent` (build-banner adjacency).
	
	Surgical, per-occurrence replacement: each value recurs (the separate `randf() < 0.5` colony coin-flip, `DEFEND_STEP = 0.01`, `CCE_DILUTION = 0.7`, dials/colors), and all non-target occurrences were left untouched — verified by re-grep. Placement: M1–M3 in the tuning block, M4/M5 beside their domain constants.
	
	### Do-now-safe cleanup queue (from the refactor catalog) is now complete
	
	Shipped this session: landmine comment pass (`cffc384`), N1 rally-banner rename (`d2e4bce`), and these constant promotions (pending commit). Remaining catalog items all deliberately deferred: Tier B dedups/extractions (U1/U4/U5/U6/U7/U8/T1 — no behavioral-equivalence harness), N4 wall->block mass rename (project-parked), N5 + low-value constants/notes. F1 (collect_lock stall) and F2 (negative-modulo seam) remain parked as functional findings for combat-walls pre-work.
	
	
	---
	
	## Session Notes — 2026-06-09 (cont., git/commit workflow fix + handoff)
	
	Resolved the recurring commit friction. Two root causes:
	1. `settings.local.json` was auto-approving ALL state-changing git (`Bash(git *)`, `Bash(git add *)`, `Bash(git commit *)`) — the opposite of the intended manual checkpoint. Removed those; `add`/`commit`/`push`/`reset` now prompt. Added auto-approve for read-only git (`status`/`diff`/`log`), read-only inspection (`cat`/`sed`/`ls`/`grep`), and the temp commit-message write/cleanup. Config lives in git-ignored `settings.local.json` (personal preference, not committed).
	2. Commit commands were `&&`-chained one-liners. Code's analyzer can't statically vet a compound chain (it warns "contains shell syntax that cannot be statically analyzed"), so the whole chain prompts regardless of allow rules — and the chaining is also what produced the heredoc / `cat -A` construction errors.
	
	**Standing commit convention (refined — apply going forward):**
	- Run commit steps as SEPARATE commands, never `&&`-chained: `git status --short`, write the message file, `git add <files>`, `git commit -F <file>`, `git push`.
	- Write the commit-message file via Code's file-write tool, NOT `printf`/heredoc with a shell redirect — avoids quoting/whitespace/indentation traps and the `/tmp` redirect-permission ambiguity.
	- State-changing git prompts by design (the manual checkpoint). The planning layer specifies message content + conventions; Code authors the actual string in its own environment.
	
	Current HEAD: `995782c` (M1–M5 constants). The settings change is not a commit (git-ignored).
	
	### NEXT STEP (named): gather chant trigger
	
	Make the Stage 2 `speck -> gather` composite reachable in normal play. gather is currently unraisable: default weight 0, and no gather trigger in `CHANT_RECIPES` (DEVNOTES notes gather/build triggers were deliberately absent). The consumer is wired and correct; it just can't fire for a player.
	
	Start with an INSPECTION of the chant pipeline before any implementation — cover: `CHANT_RECIPES` schema; `_apply_recipe` (how a recipe modifies CCE, scope, decay); chant->recipe matching (`_process_input`/`_process_chant_locally`); WHY gather/build were omitted and whether gather (a non-rolled verb) is special; consumer interaction (gather>0 + pending speck observation -> directed move; gate is purely weight>0); and the key dependency — the composite needs BOTH gather>0 AND a recent `pending_observe` with a speck entry (which only exists if the dot also rolls `observe`), so a gather chant may need observe active too. Then design the trigger word and implement.
	
	After gather: combat-walls pre-work (re-enable colony 1, verify F1/F2 with live data, then the combat mechanic). Tier B dedups remain deferred (no equivalence harness; disposable client). N4 wall->block parked.
	

---

## Session Notes — 2026-06-22 (gather chant trigger — Option A shipped)

### Shipped: gather chant trigger (speck -> gather composite now reachable)

The Stage 2 `speck -> gather` composite is reachable in normal play. Four aliases added to `CHANT_RECIPES`, each co-raising `gather` AND `observe` by `CHANT_WEIGHT` (0.08):

- `gather` / `collect` / `forage` / `harvest` -> `{ "action": { "gather": CHANT_WEIGHT, "observe": CHANT_WEIGHT } }`

Pure data-row addition (four rows in `CHANT_RECIPES`). No executor, selection, or consumer change — the path was already wired (Stage 2, 2026-06-09): `OBSERVE_MOVE_MAP = { "speck": "gather" }`, the `move`-case consumer, and ambient collection all pre-existing and correct. The trigger was the only missing piece.

### Why co-raise observe (the dependency)

Inspection confirmed the gate is two independent rolls: a dot must (1) roll `observe` while a speck is in radius (writes `pending_observe.speck`), then (2) on a later tick roll `move` while `gather > 0` (consumes it via the directed-march branch). `pending_observe.speck` is ONLY written by `_execute_observe` on an observe roll — no other writer. Default observe is just 0.10 on `COLONY0_CCE`. Raising gather alone arms condition (2)'s gate but does nothing for (1), and dilutes observe's softmax share as gather grows. So gather-only would be reachable but near-dead. Co-raising observe makes it playable: more observe rolls -> more live speck observations -> more directed-move consumption.

### Option A (accept the no-op tax), not B (pool-exclude first)

`gather` has no `_execute_primitive` executor — when selected as a standalone verb it is a no-op (wasted tick); its only functional role is the gate weight read by the `move` consumer. With the flat softmax (raw exp, no temperature; 2026-06-08), one "gather" chant (gather -> 0.08) makes ~16% of that dot's rolls no-op gather picks; heavier chanting scales the tax (~20% at gather 0.40) while observe's share barely climbs. The tax roughly cancels the sensing benefit in useful-ticks terms.

Chose A: ship the trigger now, accept the idle-tick tax, watch it in real play. Rationale is the project's data-before-hypotheses rule — the ~1-in-5-idle figure is a model prediction, not observed play. B (exclude gather from the selection pool so it's a pure gate, never rolled) is the clean end state but is a hot-path change to selection logic and earns its own inspection. If the idle reads badly in play, B becomes the next scoped change.

### Verification

- `validate_script` on `main.gd`: clean.
- In-play (via `execute_game_script` against a live run, no scaffolding added to `main.gd`): chanting "gather" once raised colony-0 dots gather 0.0 -> 0.08, observe 0.10 -> 0.18 (both +CHANT_WEIGHT — confirms `_apply_recipe` raises both). A dot with a speck in observe radius then fired the directed-move branch — marched ~0.0316 toward the speck (~one cell-step; cell spacing 0.0314 — directed, not random drift), `pending_observe` cleared on consumption. Composite confirmed end-to-end for a player-driven chant.

### Commit hygiene this session

Pre-existing uncommitted `DEVNOTES.md` delta (the prior git/workflow-fix + gather-handoff note) was landed first as its own docs catch-up commit (`1611a92`) to keep it from fusing with this feature commit. This gather note plus the `main.gd` trigger are the feature commit on top.

### Next / still open

- Watch the gather no-op tax in real play; decide B (pool-exclude gather) with evidence if idle reads badly.
- Combat-walls pre-work: re-enable colony 1, verify F1/F2 with live data, then the combat mechanic.
- enemy/ally/banner observation consumers still unwired (`enemy -> attack` gated behind the combat-walls design). Distance-metric inconsistency still flagged, cosmetic.
	
	---
	
	## Session Notes — 2026-06-22 (cont., F2 seam fix — combat-walls pre-work begins)
	
	### Context
	
	Combat-walls pre-work started, fix-first ordering: fix F2, then F1, then re-enable colony 1 into a clean environment. A read-only inspection first mapped the colony-1 re-enable surface and statically confirmed both parked findings (F1, F2) against the real code (line-anchored, quoted guards). This note covers the F2 fix; F1 and colony-1 re-enable follow as separate commits.
	
	### Shipped: F2 seam-scan fix (u wraps, v clamps)
	
	The four neighbor-enumeration scans computed wrapped coordinates as `(key.x + du) % GRID_RES` (same on `key.y`). GDScript `%` truncates toward zero (`-1 % 200 == -1`), so at the u=0/199 seam the negative coordinate never matched a real 0..199 key — the scan silently saw nothing across the seam. Fixed:
	
	- **u-axis (longitude):** `(key.x + du + GRID_RES) % GRID_RES` — genuine wrap, matching the reference idiom already in `_pick_lateral_cell`.
	- **v-axis (latitude):** no wrap. Raw `key.y + dv`; if `< 0` or `> GRID_RES - 1`, skip the cell (`continue`). v is `asin`-derived; v=0 and v=199 are near opposite poles, so wrapping there would falsely connect opposite-pole cells.
	
	Four functions, one enumeration site each (all identical bug, identical fix):
	- `_is_blocked_by_foreign` (~1142)
	- `_find_nearest_foreign_in_radius` (~1155)
	- `_find_nearest_ally_in_radius` (~1174)
	- `_get_foreign_dots_near` (~1199)
	
	Return contracts unchanged — coordinate-computation fix only. Diff +20/-4.
	
	### Design call: detection follows actual surface proximity
	
	The u-wrap/v-clamp choice means detection respects real local proximity: longitude wraps (going east far enough returns you west), latitude does not (a north-pole dot and a south-pole dot are physically far apart and must not detect each other). Replaces one wrong behavior (phantom pole-crossing on v / silent seam-blindness on u) with locally-correct edge handling.
	
	### Scope boundary: seam logic only, NOT the grid distortion
	
	Deliberately deferred: the equirectangular distortion — a fixed integer-cell radius covers more real longitude near the poles than at the equator, because `_cell_key` quantizes longitude into GRID_RES columns at every latitude. v-clamp fixes the seam but does NOT make detection radius uniform in real surface distance. Design intent (this session) is that detection should cover the same real distance regardless of position on the sphere; that is a separate, broader change touching every radius-based scan and the cell-vs-angular-distance metric (`ATTACK_DETECT_RADIUS`, observe radius, `RALLY_RADIUS`, `BUILD_BANNER_RADIUS`, `_torus_cell_dist_sq` usage). It earns its own inspection before implementation — no behavioral-equivalence harness exists and Code cannot run the game, so the detection-model rework is not a fold-in. The scans still use box `(key - occ_key).length_squared()` with integer-cell radii, unchanged. This F2 fix is the clean starting point for that grid rework.
	
	### Verification
	
	`validate_script` on `main.gd`: clean. grep confirms the only remaining `(key.x + du) % GRID_RES` is line 1088 — the dead fog-reveal scan (below the `return` in `_check_fog_of_war`), deliberately left untouched; it carries the same bug and gets fixed if/when fog reveal is restored as part of the colony-1 decisions. `_pick_lateral_cell` and `_torus_cell_dist_sq` (already correct) untouched. No game run — behavioral confirmation across the seam (a dot detecting a foreign across u=0/199) requires two colonies in contact near the seam, which is a player-driven run, not Code's.
	
	### Pre-work status / next
	
	- **F2 — done** (this commit).
	- **F1 — next.** collect_lock stall confirmed: in `_tick_all_dots` the `combat_locked` guard precedes the collect_lock block, and the lock clears only on the exact `until_tick == _tick_num` branch (lock set with `until_tick = _tick_num + 1`). A resolution tick skipped because combat fired first strands the lock forever — the dot hits `continue` every subsequent tick, never re-enters `_tick_dot`, but still ages (via `_age_dots`, unconditional) to DOT_LIFETIME and is removed. Agreed fix semantics (per 2026-05-28 "clear without removing"): clear the lock on `until_tick <= _tick_num`, but credit soul / free the speck only on exact `==` with the speck still present. Implementation prompt pending.
	- **Colony-1 re-enable — after F1.** `_spawn_enemy_colony` (main.gd:1227) places one founder 45° from the player via a single `_create_dot(enemy_dir, null, ENEMY_COLONY, COLONY1_CCE)`; it grows on its own reproduce (0.32). Re-enable is uncommenting main.gd:273 plus three deliberate override decisions: fog `return` (main.gd:1080), `full_inheritance=true` (main.gd:1286, makes CCE_DILUTION inert), `_apply_recipe` LOCAL_COLONY chant filter (main.gd:358-360). Plus enemy-preset call: single founder vs. seeded population. A second colony is wanted for ongoing dev work, so this lands rather than being reverted.
	- **Stale-prose note (recorded, not acted on):** older DEVNOTES "MAD / both deleted on mutual" combat framing is inaccurate vs. the code — `_tick_combat_clusters` resolves deterministic single-death-per-pair, ties to attacker; not literal simultaneous mutual deletion.
	
	
	---
	
	## Session Notes — 2026-06-24 (F1 collect_lock stall fix + batched pre-work push)
	
	### Shipped: F1 collect_lock stall fix
	
	The collect_lock stall (parked since 2026-06-09, confirmed static in the colony-1 pre-work inspection) is fixed. The bug: in `_tick_all_dots` the `combat_locked` guard precedes the collect_lock block, and the lock cleared only on the exact `until_tick == _tick_num` branch (lock set with `until_tick = _tick_num + 1`). A dot combat-locked on its exact resolution tick skipped the clear; next tick `== ` was permanently false, so the lock never cleared, the dot hit `continue` every tick thereafter (never re-entering `_tick_dot`), yet still aged to DOT_LIFETIME via `_age_dots` (unconditional). A silent frozen dot crediting nothing and acting never.
	
	Fix (collect_lock block only):
	- Resolution condition `== ` -> `<=` so a lock at or past its resolution tick is always handled (cleared), never stranded.
	- Payout (free speck + credit soul) nested inside an inner exact-`==` branch — fires on-time only.
	- Late branch (`until_tick < _tick_num`, the missed-resolution case): clear the lock and do nothing else. No `queue_free`, no `specks.erase`, no `soul_pool` increment.
	- Guard order (combat_locked -> is_wall -> collect_lock) and the `continue` placement unchanged.
	- The on-time soul credit still sits OUTSIDE the `speck in specks` check, now scoped inside the `==` branch — the "lock is the receipt" simultaneous-arriver semantics are preserved exactly, only narrowed to the on-time case.
	
	### Semantics decision (combat preempts collection)
	
	Per the 2026-05-28 "clear without removing" intent: a collection preempted by combat is silently lost — the dot is released back to normal ticking, but the missed collection does NOT pay out. The speck stays on the board for another dot; no soul is credited for a late clear. Confirmed this direction explicitly with Dustan before implementation (the one genuine design fork inside the fix: late clear releases the dot only, vs. late clear still credits — chose release-only).
	
	### Verification
	
	`validate_script` on `main.gd`: clean. Static confirmation that the condition is `<=`, payout is gated to exact `==`, the late branch clears-and-nothing-else, and guard order + `continue` are unchanged. No game run — runtime confirmation of the actual stall (combat_locked firing on the exact resolution tick) needs two colonies in contact, i.e. a player-driven run once colony 1 is live; that is Dustan's to run, not Code's.
	
	### Commit / push grouping — READ THIS IF GIT HISTORY LOOKS ODD LATER
	
	F2 and F1 are SEPARATE commits but were PUSHED TOGETHER as one batch (Dustan's call — push the pre-work as a group rather than per-commit).
	
	Timeline, because the dates don't line up with a naive reading of the notes:
	- F2 work was authored ~2026-06-22, but that session's commit prompt never executed (rate-limit pause; session ended on an unconfirmed commit). The F2 DEVNOTES note is dated 2026-06-22 "(cont.)" and says "this commit," narrating a commit that had not yet happened.
	- A fresh Code session on 2026-06-24 re-oriented (DEVNOTES + git status), found the F2 work sitting uncommitted in the working tree, and committed it as `e3d1144`.
	- F1 was implemented and committed immediately after on 2026-06-24.
	- Both `e3d1144` (F2) and the F1 commit were pushed together on 2026-06-24.
	
	So if later archaeology shows F2 (`e3d1144`) and F1 committing/pushing within minutes of each other despite the F2 note reading 2026-06-22 — that is expected, not a lost/duplicated commit. The 2026-06-22 F2 note narrates work that actually landed 2026-06-24.
	
	Pre-work commit sequence as landed: `209e057` (gather trigger, pre-existing HEAD) -> `e3d1144` (F2 seam) -> [F1 stall] -> push. Colony-1 re-enable is the next pre-work step, a separate commit after.
	
	### Pre-work status / next
	
	- **F2 — done & pushed** (`e3d1144`).
	- **F1 — done & pushed** (this commit).
	- **Colony-1 re-enable — next.** Uncomment main.gd:273 (`_spawn_enemy_colony`) plus three deliberate override decisions: fog `return` (main.gd:1080), `full_inheritance=true` (main.gd:1286, dilution inert), `_apply_recipe` LOCAL_COLONY chant filter (main.gd:358-360); and the enemy-preset call (single founder vs. seeded population). A second colony is wanted for ongoing dev work, so this lands rather than reverts.
	- **After pre-work:** the combat-walls mechanic design fork (keep the old self-scan attack vs. execute the 2026-05-13 observe-gated redesign), and separately the uniform-detection-radius inspection (the equirectangular distortion deferred from F2 — detection should cover the same real surface distance regardless of position on the sphere).
	
	
	---
	
	## Session Notes — 2026-06-24 (cont., enemy colony 1 re-enabled — combat-walls pre-work complete)
	
	### Shipped: enemy colony 1 re-enabled (single bundled commit)
	
	The last pre-work step. Colony 1 is turned back on after being dark since ~2026-05-09 (commented out for single-colony build dev). Three edits in `main.gd`, one commit:
	
	- **EDIT A — fog reveal restored.** Removed the `# TESTING:` comment + bare `return` short-circuit in `_check_fog_of_war`. The legitimate early-exit (`revealed_colonies.size() >= known_colonies.size()`) stays. Enemy now renders fogged grey until a LOCAL_COLONY dot reaches its 3x3 neighborhood, then permanently reveals + recolors (`_update_all_dot_colors`). Per-colony reveal, no re-fog path.
	- **EDIT A' — seam patch on the now-live fog scan.** Restoring reveal activated the one remaining bare-negative-modulo neighbor scan (the F2 bug, deliberately left dead below the `return` during the F2 fix). Patched with the identical F2 idiom (u-wrap `(key.x + du + GRID_RES) % GRID_RES`, v-clamp range-skip). **Milestone: this was the fifth and final application — a file-wide grep now shows ZERO bare `(key.x + du) % GRID_RES` scans remaining. The F2 seam class is fully eradicated.**
	- **EDIT B — spawn uncommented.** `_spawn_enemy_colony()` re-enabled in `_ready()`, call site unmoved (after `_spawn_player_dot()` so `player_dot` exists when read). Single founder placed 45° (PI/4) from the player; grows on its own reproduce (0.32). Function body and `COLONY1_CCE` untouched.
	
	### Settled override decisions (the four touch-points)
	
	1. **Fog — RESTORED** (reveal-on-contact). Want to see contact happen during dev work.
	2. **Dilution — KEPT INERT.** `_spawn_dot_near` still passes `full_inheritance=true`, so `CCE_DILUTION = 0.7` stays bypassed; both colonies breed true. Clean verification first; flip to realistic generational decay later as its own deliberate change.
	3. **Chant filter — KEPT.** `_apply_recipe`'s `!= LOCAL_COLONY -> continue` filter stays; the enemy is un-chantable. (A second identical guard exists at a later recipe-apply block; also untouched.)
	4. **Spawn shape — SINGLE FOUNDER.** Not a seeded cluster. Deliberate: a lone P1 dot doubly exercises reproduce + wander to establish itself, making the re-enable a live test of those paths, not just a sparring dummy.
	
	### Expected first-run behavior (for whoever runs it)
	
	- P1 founder spawns 45° from the player, renders fogged grey.
	- Combat runs via the OLD model — `_execute_attack`'s own self-scan (`ATTACK_DETECT_RADIUS = 10`); observe is NOT wired to combat detection yet, so the enemy's `observe 0.10` is currently inert (costs softmax share as idle observe rolls, feeds no combat behavior). The 2026-05-13 observe-gated combat redesign is still spec-only.
	- On contact: a P0 dot reaching P1's 3x3 neighborhood reveals colony 1 permanently and recolors all dots.
	- Combat resolution is deterministic single-death-per-pair, ties to attacker (NOT the stale "MAD/both deleted" prose in older notes).
	
	### IMPORTANT: combat path is runtime-unexercised against the current tree
	
	This is the first time the combat system runs since it went dark — before the observe refactor, the softmax selection rewrite, and the `move`/`build` renames. Static reads (this session + pre-work) say it's consistent and verb-name-clean, but "compiles and reads correctly" is not "has run against the current tree." The first live two-colony run is a genuine observation session, not a formality. Three reactivated paths to watch:
	- Fog reveal-on-contact (now seam-correct).
	- The full combat path (initiation, clusters, resolution, rally banners) against the newer softmax selection model.
	- The **F1 late-clear** — only fires when `combat_locked` collides with a collect_lock resolution tick (low-incidence race). Re-enable is the first scenario that can exercise it at runtime; absence in any given run just means the race didn't occur, not a defect.
	
	Behavioral confirmation is the player's run; Code's ceiling is `validate_script` (no game execution).
	
	### Verification
	
	`validate_script` on `main.gd`: clean. Grep: zero remaining bare-modulo scans. Dilution and chant filter confirmed unchanged. `M main.gd` only. No game run.
	
	### Pre-work status — COMPLETE
	
	- **F2 seam — done & pushed** (`e3d1144`).
	- **F1 collect_lock stall — done & pushed** (`2fccd1d`).
	- **Colony-1 re-enable — done** (this commit, local; push deferred pending telemetry-parsed confirmation, see below).
	
	### Next: persistent telemetry artifact, then live run, then push decision
	
	Plan agreed this session — push of the re-enable is HELD until parsed telemetry says the reactivation behaves:
	1. (this commit) Re-enable, local only.
	2. Scope + implement a PERSISTENT JSON state-dump (population per colony, soul_pool, combat events, reveal events, and an explicit log when the F1 late-clear branch fires) — kept as reusable dev instrumentation, not throwaway scaffolding. Its own commit.
	3. Player runs the game long enough for combat/capture to occur.
	4. Parse the JSON to judge whether the reactivation is push-worthy.
	5. Decide the push (both re-enable + telemetry, or revisit) with data in hand.
	
	Then (after pre-work): the combat-walls mechanic design fork (keep old self-scan attack vs. execute the 2026-05-13 observe-gated redesign), and the uniform-detection-radius inspection (equirectangular distortion deferred from F2 — detection should cover the same real surface distance regardless of position on the sphere).
	
	### Infrastructure changes this session (record for fresh sessions)
	
	- **Project root moved:** now `/Users/fd2023/Desktop/dkentbrown.dev/Dots/dots/` (was `/Users/fd2023/Desktop/Dots/dots/`). The inner `dots/` is the git repo root and Claude Code's launch dir (for `.mcp.json` / `CLAUDE.md`).
	- **GitHub remote renamed:** `origin` is now `git@github.com:dkentbrown/dots.git` (was `UndoneIridium/dots`). The GitHub account was renamed; the old URL only worked via GitHub's redirect. `git remote set-url origin` already applied locally and verified — pushes now go direct, no redirect dependency.
	
	
	---
	
	## Session Notes — 2026-06-24 (cont., persistent JSONL telemetry artifact)
	
	### Shipped: persistent telemetry instrumentation (telemetry.jsonl)
	
	Reusable dev instrumentation to parse after a live run rather than eyeballing the sphere — built ahead of the first two-colony run so the colony-1 reactivation can be judged from data. Dedicated, NOT an extension of `_log` (which is plain-text, build-scoped, LOCAL_COLONY-only, and wiped each launch).
	
	**New constants** (beside `LOG_*`): `TELEMETRY_ENABLED = true`, `TELEMETRY_FILE = "res://telemetry.jsonl"`, `TELEMETRY_SNAPSHOT_INTERVAL = 1` (snapshot every N ticks).
	
	**Writer** `_telemetry(record)`: opens `TELEMETRY_FILE` READ_WRITE (create-via-WRITE fallback), `seek_end`, `JSON.stringify(record) + "
"`, close. Defensive double-null return. **Never truncates** — persistence is the point.
	
	**Format: JSONL** (one complete JSON object per line). Chosen over a single JSON blob specifically because the run is killed by closing the game — each line is independently parseable, so whatever was captured before the kill survives intact.
	
	**Persistent across runs.** Runs accumulate into one file; a `run_start` boundary record (written once in `_ready`, `run_id` = Unix timestamp, plus `grid_res`) segments them at parse time. Output is gitignored (instrumentation code committed; run data not).
	
	**Record types:**
	- `run_start` — `{run_id, grid_res}`, once per launch.
	- `snapshot` — once per tick at the END of the tick block (post-mutation, after `_tick_all_dots`/`_update_hud`): `{tick, pop, soul, walls, combat_active, combat_locked, revealed, specks}`. Aggregate dicts `.duplicate()`'d to avoid aliasing live state. Covers ALL colonies (unlike `_log`). `combat_active` reads clusters still in-flight at tick end (combats that resolved this tick already cleared); transitions are captured by the events below.
	- `combat_init` — at `_initiate_combat`: `{tick, attacker_colony, defender_colony, cell, intensity}`.
	- `combat_resolve` — in `_tick_combat_clusters`, between power computation and the win/loss branch (colonies read BEFORE deferred `_remove_dot`): `{tick, winner_colony, loser_colony, a_power, d_power, defender_was_wall, cell}`.
	- `f1_fired` — in the F1 late-clear branch of `_tick_all_dots` (guarded by `until_tick < _tick_num`; the unconditional lock-clear is byte-identical): `{tick, colony, until_tick, dot_id}`. Makes the invisible F1 race greppable. `dot_id` read defensively (`.get(..., -1)`; absent in organic runs).
	- `reveal` — at the fog reveal set in `_check_fog_of_war`: `{tick, colony}`.
	
	All six hooks are purely additive — no control flow, combat resolution, collect_lock, or fog logic changed at any site. Verified against the actual file (planning layer read source directly this once because the Code report arrived garbled and hook placement in new persistence infra needed confirmation; not a standing practice — Code-report-driven review is the norm).
	
	### Parse notes (for analysis)
	
	- `JSON.stringify` stringifies int dict keys: `pop`/`soul`/`walls` parse as `{"0":..., "1":...}`; `revealed` is an int array.
	- Segment runs by `run_start` boundaries; discard prior runs at parse time.
	- `combat_active`/`combat_locked` in a snapshot = in-flight at tick end; pair with `combat_init`/`combat_resolve` events for the full combat picture.
	
	### Watch-item (not a blocker)
	
	`_telemetry` opens/seeks/closes per record. Snapshots fire every tick and combat events per resolving pair across both colonies, so heavy two-colony combat = potentially hundreds of open/close cycles per tick. At `TICK_SPEED = 1.0` this is almost certainly fine and won't corrupt records (each fully written before close), but a visible hitch during a big fight would point here; fix is holding the handle open or batching. Not pre-optimized.
	
	### Plan status (push still held)
	
	The push of BOTH the re-enable (`59db728`) and this telemetry commit stays held until parsed telemetry confirms the reactivation behaves. Sequence:
	1. Re-enable — committed local (`59db728`).
	2. Telemetry — this commit (local).
	3. Player runs the game long enough for combat/capture to occur.
	4. Parse `telemetry.jsonl` (segment by latest `run_start`): does P1 spawn, reproduce, wander, get revealed on contact; does combat initiate and resolve sanely; does `f1_fired` ever appear.
	5. Decide the push (both commits, or revisit) with data in hand.
	
	After that: combat-walls mechanic design fork, and the uniform-detection-radius inspection (equirectangular distortion deferred from F2).
	
	
	---
	
	## Session Notes — 2026-06-24 (cont., N4 wall→block rename + combat-walls grounding)
	
	### Context: first two-colony telemetry run analyzed
	
	Before the rename, the held re-enable + telemetry commits were exercised by the first live two-colony run (telemetry.jsonl, run_id 1783011133, 146 ticks). Grounded findings from reading the artifact directly:
	- **Instrumentation confirmed working** — 417 valid JSONL records, run_start + per-tick snapshot + all four events firing (reveal @ t66, combat_init/combat_resolve with sane winner/loser/power/cell payloads, defender_was_wall flipping correctly). f1_fired never fired (expected — low-incidence race, didn't land in this window).
	- **F2 seam fix validated in the wild** — combat clusters resolved correctly at u=192–199 (right on the u=0/199 seam F2 was blind to). Fix-first ordering paid off exactly where predicted.
	- **Observations (recorded as observations, NOT balance conclusions from one run):** both colonies grow; P1 reaches the shared MAX_POPULATION_PER_COLONY=1000 cap at t76 and pins there (cap is colony-agnostic, not a combat lever). P0 never nears the cap because build rolls consume its activity budget. Once P0's build ramps, combat_resolve records flip to defender_was_block(was_wall):true / winner:0 — blocks at defend 0.5 beat attackers at attack 0.4. P0 block count climbed to ~2807, still rising. This is the build-monument system, NOT a combat-walls mechanic — which triggered the rename below. Balance conclusions need more runs (vary presets, longer windows) before any fix; one run does not establish a bug.
	
	### Combat-walls grounding: ZERO implementation exists
	
	An inspection searched the full codebase (not just "wall" tokens — also the 2026-05-13 spec vocabulary: waller, WALLER_TRIGGER_SCALE, rider, mesh variants, plus generic barrier/fortify/blockade terms) and confirmed: **there is no combat-wall implementation, partial or whole, under any name.** Every "wall" token in code is the build/monument (now block) system, plus exactly one reservation comment. Structural corroboration: only two banner arrays (rally + build, no "wall banner"); observe consumers sensed-but-dormant with no enemy→attack wiring; combat path has no defense structure beyond the block-defender advance rule. DEVNOTES spec status markers agree (Defense/rider/wall-mesh/wall-banner all UNIMPLEMENTED / DESIGN PENDING). Of the 2026-05-13 foundation, only the observe primitive landed — it carries no wall vocabulary. **The "wall" namespace in code is now free for the future combat-walls mechanic.**
	
	### Shipped: N4 wall→block mass rename (un-parked)
	
	Un-parks the previously-cataloged "N4 wall→block mass rename." Pure rename, zero behavior change (verified: diff-filtering for changed lines without a wall/block token yielded exactly one line — the retired "will rename later" marker). Vocabulary split now enforced in code:
	- **block** = the unit (one placed cube). Was "wall".
	- **monument** = the stacked structure of blocks (BUILD_MONUMENT_* — already correct, unchanged).
	- **wall** = reserved, unclaimed in code, for the future combat-walls mechanic.
	
	Renamed (main.gd only): is_wall→is_block; WALL_DEFEND_VALUE/DECAY_TICKS/MESH_SIZE/HEIGHT_STEP → BLOCK_*; wall_counts→block_counts; _create_wall→_create_block; _count_walls_in_cell→_count_blocks_in_cell; banner wall_cap/wall_count→block_cap/block_count; locals defender_is_wall→defender_is_block, wall_cell→block_cell, p0_walls→p0_blocks; ~15 descriptive comments; log/HUD strings. The defender_is_wall combat-resolution branch was renamed to defender_is_block (it is block code — blocks incidentally defending, the E2 behavior — NOT combat-wall code to carve out).
	
	**Telemetry schema rename (D1, decided):** snapshot key "walls"→"blocks", combat_resolve key "defender_was_wall"→"defender_was_block". Landed before the telemetry commit was pushed. The gitignored telemetry.jsonl from the first run carries OLD keys; post-rename runs carry new keys — segment by run_start when parsing (heterogeneous keys across the run boundary, no live parser to break).
	
	Verification: validate_script clean (also proves identifier consistency); case-insensitive grep for "wall" returns exactly ONE surviving token — the reservation comment (now main.gd:722, shifted −2 after the marker retirement): "(combat-walls design pending, see DEVNOTES 2026-05-13)". Namespace clean save for that intentional reservation.
	
	### Parked (combat-walls design questions, NOT touched by rename)
	
	- **E1** — _apply_recipe filters on colony only, so P0 chants mutate P0 *block* CCEs; a defend-raising chant strengthens existing monuments in combat. Chant-buffed monuments are already de facto combat walls. The combat-walls design must reconcile this.
	- **E2** — the monument/combat-wall conflation lives in UNFILTERED scans (_find_nearest_foreign_in_radius, _get_foreign_dots_near, _is_foreign_in_exact_cell, _is_blocked_by_foreign, _check_fog_of_war, _compute_colony_center, _execute_observe) that never check is_block. Blocks act as combat defenders / movement blockers / fog contacts / colony-center mass / rally triggers / observe-"enemy" targets purely because these scans treat them as ordinary foreign dots. The rename relabels this; it does NOT partition it. When combat walls are designed, EACH scan site becomes an explicit "blocks, combat walls, or both?" decision.
	- Pre-existing comment inaccuracy preserved verbatim (pure rename): _create_block's "same-colony blocks" comment vs. code counting any-colony occupants.
	
	### Commit / push status
	
	Three commits pushed together this session (user-approved batch push): 59db728 (re-enable), 4b8dfc2 (telemetry), + this rename commit. After the held gate cleared (first run parsed, instrumentation + seam fix confirmed), all three went to origin as a group.
	
	### Next
	
	Combat-walls mechanic design — now unblocked (namespace free, E1/E2 boundary mapped). Separately: the uniform-detection-radius inspection (equirectangular distortion deferred from F2). And a combat-balance question raised but NOT settled: does the block-defender-beats-attacker / reproduction-rate asymmetry replicate across runs — needs more data before any fix.
	
	
	---
	
	## Session Notes — 2026-06-24 (cont., observe-consumption grounding for combat-detection fork)
	
	### Purpose
	
	Grounding pass (read-only inspection, no code) to answer precisely: how is an observe tick produced and consumed today, and does combat detection route through it? This settles the combat-detection design fork on real code rather than recollection, ahead of combat-walls design. DEVNOTES' own "each is later a one-line map entry" note (re: wiring observe slots to verbs) was found to be optimistic — see below.
	
	### How observe is produced and consumed (grounded, main.gd)
	
	**Two separate softmax draws.** observe and its consumption are not one action:
	
	1. **Production** — `_execute_observe(dot)` runs when the softmax picks "observe". Scan radius is weight-scaled: `radius = int(OBSERVE_BASE_RADIUS + OBSERVE_SCALE * observe_weight)` (3 + 20·w cells). It scans four slots — enemy (`_find_nearest_foreign_in_radius`), speck (linear scan, specks aren't grid-indexed), ally (`_find_nearest_ally_in_radius`, same-colony, excludes self+blocks), banner (nearest active same-colony build banner) — and writes ALL FOUR to `dot_data[dot]["pending_observe"]` every observe tick (unfound = null), overwriting any prior observation. Per-dot, single dict, all keys always present. Entry shapes: enemy/ally carry "dot", speck carries "node", banner carries "cell"; all carry "pos".
	
	2. **Consumption** — `pending_observe` is READ in exactly ONE place: the "move" case of `_execute_primitive`. Gated by `OBSERVE_MOVE_MAP`, whose entire contents are `{ "speck": "gather" }`. On a later move roll: iterate mapped slots, skip nulls, look up the mapped verb's CCE weight, keep the highest non-zero, and if any survives march one CELL_STEP toward `pending[best_key]["pos"]` and null the WHOLE `pending_observe`. Otherwise fall through to undirected wander/spiral.
	
	**Only speck is consumed. enemy, ally, banner are written every observe tick and read by NOTHING** — sensed-but-dead. (The `gather` verb that gates the speck path has no executor of its own; its only live effect in the engine is gating this directed move.)
	
	### Combat detection does NOT route through observe
	
	`_execute_attack` does not read `pending_observe` at all. It self-scans independently: `_find_nearest_foreign_in_radius(my_dir, my_colony, ATTACK_DETECT_RADIUS)` with `ATTACK_DETECT_RADIUS = 10` (fixed, unrelated to observe weight). Found → initiate combat if within `_get_foreign_dots_near` adjacency, else march toward; not found → rally-banner fallback.
	
	**Two fully independent sensing paths coexist:** the P(r)-driven observe layer (weight-scaled radius, feeds only gather) and attack's self-scan (fixed radius 10, feeds combat). They share the helper `_find_nearest_foreign_in_radius` but call it with different radii and share no state. An enemy's observe rolls feed no combat behavior today — inert softmax share.
	
	### The combat-detection fork, grounded (NOT resolved — user's call)
	
	The fork is NOT "should detection route through P(r)" (observe already is on P(r)). It is: **does combat detection keep attack's free fixed-radius self-scan, or consume `pending_observe.enemy` the way move consumes speck (observe-gated detection, attack loses self-scan — the 2026-05-13 redesign)?**
	
	Concretely, to make it observe-gated:
	- **Consumer:** NOT literally a one-line `OBSERVE_MOVE_MAP` add. The current consumer (move case) only produces a directed MARCH; `speck→gather` works because gather is just directed movement. `enemy→attack` needs actual combat initiation (adjacency test, combat_locked guard, `_initiate_combat`), which the move-consumer does not do. So either repoint `_execute_attack` to read the slot, or build a genuine attack-verb consumer path. DEVNOTES' "one-line map entry" optimism is corrected here.
	- **Remove from `_execute_attack`:** the self-scan target line; `ATTACK_DETECT_RADIUS` becomes dead (detection range would then derive from observe weight). The rally fallback, combat_locked guard, adjacency test, and initiate/march branch stay — only the target SOURCE changes.
	- **Build-on:** `_execute_observe` already writes `pending_observe.enemy` every observe tick (weight-scaled radius) — the write exists and is live; only the READ is missing. Plus a clear-on-consume rule for the enemy slot (speck nulls the whole dict; enemy needs its own consistent rule).
	
	**The trade-off the fork encodes (this is the gameplay decision, needs user):** self-scan = every attacker gets free, fixed-radius, always-on enemy omniscience regardless of what it rolls. Observe-gated = a colony must SPEND softmax share on observe to see enemies, detection range scales with observe weight, and a colony that doesn't observe is blind and cannot fight. This directly interacts with the parked combat-balance question (does the P1-fights-freely asymmetry replicate?) — observe-gating makes sensing a costed action, changing aggression dynamics.
	
	### Related flags (recorded, not resolved)
	
	- **Radius-semantics side effect:** switching detection source silently changes detection range (fixed 10 vs. weight-scaled 3+20w). Interacts with the still-pending uniform-detection-radius inspection (equirectangular distortion deferred from F2).
	- **Clear-on-consume differs per design:** speck nulls the whole `pending_observe`; an enemy consumer in `_execute_attack` (a different verb than move) needs its own explicit clear rule or observations go stale across ticks.
	- **Distance-metric inconsistency (cosmetic, pre-existing):** `_find_nearest_foreign_in_radius` / `_find_nearest_ally_in_radius` use a non-wrapping box metric; `_torus_cell_dist_sq` (speck/banner) wraps. The enemy slot is populated by the box-metric helper.
	
	### Status / next
	
	- Grounding complete; tree clean, origin current (nothing to commit from this pass — inspection only).
	- **DECISION PENDING (user):** self-scan vs. observe-gated combat detection. This is the load-bearing fork for combat-walls design and should be decided on the balance implication (costed sensing), ideally alongside more combat-balance run data, not on architectural elegance alone.
	- Once decided, combat-walls mechanic design proceeds (E1 chant-buffed-blocks and E2 unfiltered-scan boundary reconciliation both feed into it).
	
	
	---
	
	## Session Notes — 2026-07-07 (combat-detection fork resolved — observe-gated, shipped + verified live)
	
	### Context
	
	Fresh session, resumed from the 2026-06-24 observe-consumption grounding note. The load-bearing combat-detection fork (self-scan vs. observe-gated) was DECISION PENDING at that note's close. This session: decided, planned, implemented, diagnosed, verified live, committed, pushed.
	
	### Decision: observe-gated (2026-05-13 spec direction)
	
	Dustan chose observe-gated over keeping attack's fixed self-scan. `_execute_attack` no longer scans independently — combat detection now costs softmax share on `observe`, matching the original design intent that observation is universally meaningful.
	
	### Report-delivery convention change (infrastructure)
	
	Two consecutive Code reports pasted through chat corrupted in transit — words merged, sentences truncated at line-wrap points; short fenced code blocks survived, long prose did not. Root cause never fully isolated (terminal soft-wrap vs. copy-paste), so the fix routes around the whole chain: **Code now writes every report (INSPECTION/IMPLEMENTATION/TRIVIAL) to `res://code_report.md`, overwritten each task, gitignored, never staged. The planning layer reads it directly via `read_script` instead of requiring the user to paste it in chat.** Recorded as a standing memory edit. Does not change the separate rule against the planning layer reading `.gd` source to reason about logic — report files only.
	
	### Shipped: `_execute_attack` reads `pending_observe["enemy"]`
	
	Single-site change plus one removal, per an inspection-then-implementation pair:
	
	- `_execute_attack`'s self-scan (`_find_nearest_foreign_in_radius(..., ATTACK_DETECT_RADIUS)`) replaced with a read of `dot_data[dot]["pending_observe"]["enemy"]["dot"]`.
	- **Mandatory liveness guard** (not optional): `target == null or not dot_data.has(target)` treated as no-target, falling through to the existing rally-banner-march branch. A stored node can go stale (target removed between the observe tick and the attack tick) in a way the old self-scan never could.
	- **Clear-on-consume: Option A** — attack never writes to `pending_observe`. The enemy slot is refreshed only by the dot's next `observe` roll (closest to the old self-scan's persistent-pursuit feel; staleness bounded only by observe frequency — the trade-off was surfaced, Option A chosen over B/C which broke mid-pursuit without added branching).
	- `ATTACK_DETECT_RADIUS` removed — re-confirmed zero remaining references at implementation time (not just trusting the earlier inspection's grep).
	- Everything downstream (rally fallback, `combat_locked` guard, adjacency test, `_initiate_combat`, `_march_toward`) is source-agnostic and untouched.
	
	### Shipped: observation-age telemetry diagnostic
	
	Additive instrumentation, planned separately (persistent per-dot state shape change, so it got its own inspection pass rather than riding the TRIVIAL lane):
	
	- `_execute_observe`'s enemy-slot write now stamps `"observed_tick": _tick_num` alongside the existing `"pos"`/`"dot"` keys.
	- `_initiate_combat`'s `combat_init` telemetry record gains `"observe_age"` — `_tick_num - observed_tick`, read from the **attacker's** `pending_observe["enemy"]` (confirmed via the actual call path: `_initiate_combat`'s first param is the observing dot). Defensive `-1` sentinel if the stamp is somehow missing (unreachable via the current single guarded caller, but `_initiate_combat` is a standalone function — guarded for a hypothetical future second caller).
	- Speck/ally/banner entries deliberately left unstamped — enemy only, per scope.
	
	### Verified live (191-tick run, `run_id 1783434358`)
	
	- 226 `combat_init` events, **100% carried `observe_age`**, zero `-1` sentinels, zero negatives.
	- Distribution: min 1, max 15, mean 3.64 ticks stale. ~64% of initiations (144/226) fired on an observation 1–3 ticks old. `observe_age` never hit 0 in this run — expected, since each dot rolls exactly one primitive per tick, so a dot can't observe and attack in the same tick.
	- Informal cadence check against the old baseline run (`run_id 1783011133`, self-scan code): 226 vs. 142 `combat_init` events, reveal at tick 83 vs. 66. Combat did not visibly get starved by the reduced detection radius (fixed 10 → weight-scaled 3+20·observe_weight, ≈5 cells at the current `observe=0.10` preset) — but this is one run against one run, different RNG, not a controlled comparison, and shouldn't be read as settling the still-open combat-balance question (block-defender-beats-attacker asymmetry, flagged 2026-06-24, not yet resolved either way).
	
	### Commit / push
	
	Two focused commits, pushed together (Dustan's explicit "commit and push" this session):
	- `f23526b` — `chore: ignore code_report.md scratch file` (the new report-delivery convention's `.gitignore` rule, carried over from earlier in the session).
	- `77946a8` — `feat: observe-gated combat detection + observation-age diagnostic` (both `main.gd` changes, designed/reviewed/verified together this session, treated as one commit since the diagnostic only makes sense instrumenting the fix it rides on).
	
	Push: fast-forward `a6c3ec5..77946a8`. HEAD now `77946a8`, level with `origin/main`, tree clean.
	
	### Next
	
	Combat-walls pre-work resumes — colony 1 is already re-enabled (2026-06-24) and both F1/F2 fixes are landed; next is verifying F1 and F2 with live two-colony data now that combat detection has actually changed underneath them, before combat-walls mechanic design proceeds (E1 chant-buffed-blocks, E2 unfiltered-scan boundary reconciliation, both parked 2026-06-24). Still open, unchanged: the uniform-detection-radius inspection (equirectangular distortion deferred from F2), and the combat-balance question (does the block/attacker asymmetry replicate across runs — needs more data, no fix without it).
	
	
	---
	
	## Session Notes — 2026-07-07 (cont.) — waller stage (a) shipped, preset tuning applied, verification run still pending
	
	### Context
	
	Continuation of the same session, after the combat-detection-fork closeout above. Moved on to the next item on the horizon: designing and starting the waller (combat-walls) mechanic. Session hit its cap before a live verification run could happen — that run is the immediate next step, not yet done.
	
	### Decision: waller reaction model — defend mirrors attack, no interrupt layer
	
	Considered two models for how a dot reacts to an observed enemy: a deterministic tick-N+1 interrupt (whichever of attack/defend has the higher raw CCE weight always wins, softmax skipped, per the literal 2026-05-13 spec text) vs. defend reading `pending_observe["enemy"]` on its own normal softmax roll, exactly mirroring what attack already does (probabilistic, proportional to CCE share, no interrupt layer, no A2 adjacency-triggers-combat redesign).
	
	Dustan's stated vision was the deciding input: a smooth specialization *ladder* (most colonies plain-attack; fewer get banners; fewer still get rare bonuses; wallering — needing both `defend` and `build` high simultaneously — is meant to be rare by construction, not by a hard behavioral cliff). The deterministic-interrupt model produces a cliff (two colonies with nearly-identical attack/defend weights would behave *oppositely*, every time, with no in-between). The softmax-roll model produces a gradient for free. **Chose the softmax-roll model.** This session's already-shipped attack change (commit `77946a8`) needed no rework as a result.
	
	### Combat-effectiveness redesign — described, explicitly parked
	
	Dustan described a separate, not-yet-scoped vision for combat *effectiveness* (as opposed to action *selection*, which is what P(r) governs): base combat stays a plain deterministic comparison (defend wins ties) for most colonies; a mirrored "defend banner" (~2-defenders-worth per attacker) as a tier-1 counterpart to the existing attack rally banner; a "roll twice, take the highest" bonus for heavily-attack-specialized colonies as a tier-2 payoff — this is the first time "probabilistic combat" (discussed-but-never-decided repeatedly since 2026-05-09) has an actual answer, via a bolt-on luck modifier rather than replacing the deterministic core; simultaneously build-and-defend-heavy colonies (waller precondition) being rare is already satisfied for free by Shape D's existing multiplicative gate; the powerful version of the attack rally banner and the full oriented wall-banner mechanic (blocking territorial ingress) are explicitly envisioned as the rarest, end-game tier. **None of this is scoped or touched.** It's a separate future design pass and does not block waller work — noted here so the vision isn't lost before that pass happens.
	
	### Inspection: waller dependency grounding + staged roadmap
	
	Full inspection report reviewed and approved (see `code_report.md` history, not preserved — key findings recorded here):
	
	- **Blocks are already full combat participants today, for free.** Both foreign-detection filters (`_find_nearest_foreign_in_radius`, `_get_foreign_dots_near`) filter on `colony != my_colony` only, never `is_block`. "Combat lands on the wall first" needs no new detection code once a wall block exists — the only real unknown is *geometric* (does the wall actually sit between attacker and shielded dots), which is a placement problem for later stages, not a detection gap.
	- **Mesh/orientation capability already exists.** `_create_block` already computes a full local `Basis` frame (surface normal + two tangents) and already accepts an arbitrary `Vector3` mesh size. An oriented wall is the same frame math, sourced from threat bearing instead of a fixed reference vector — no new geometry infrastructure needed.
	- **`wall` namespace confirmed genuinely free** — one comment reference only, post-N4-rename.
	- **`combat_locked` is a model to mirror, not reuse** — it auto-clears on combat resolution; a waller lock must persist independent of any particular fight resolving, only clearing when the wall itself dies. Needs its own lock.
	- **Staged roadmap** (dependency-ordered, each independently playtestable where noted): (a) defend reads `pending_observe.enemy` + Shape D roll, log-only — root, standalone. (b) wall banner data structure + drop — needs (a)'s success path pointed at it. (c) oriented half-thickness block + mesh — needs (a) for threat bearing, playtestable alone. (d) waller lock (blocks all rolls incl. observe, unlocks on wall death) — needs (c), not playtestable without it. (e) other wallers extend the wall line — needs (b)+(c). (f) block-attackability — **not real work**, collapses to a live-run verification per the finding above, unless a future targeting-priority decision adds scope.
	- **Three open design questions surfaced, still unresolved**: wall banner radius/TTL/completion condition; wall-banner-vs-build-banner priority when both in range (no two banner types are ever compared today — this would be new); whether combat-tick-shortening (`intensity > 0.7` → 2 ticks) should apply to wall-mediated combat.
	
	### Shipped: stage (a) — defend + Shape D diagnostic (log-only, no movement change)
	
	`_execute_primitive`'s `"defend"` arm now checks `pending_observe["enemy"]` (identical guard pattern to the shipped attack change: null-check `pending_observe`, null-check the `enemy` entry, extract the node, liveness-guard via `dot_data.has`). If a live observation is pending: rolls Shape D = `(this dot's own defend CCE) × (colony-avg build CCE) × SHAPE_D_SCALE` (new placeholder constant, 2.0), logs a new `shape_d_roll` telemetry record (tick, colony, prob, success). **The existing colony-center march still runs unchanged in both branches — no movement behavior changed this stage.** Not yet committed.
	
	### Resolved: `build_upward` is not a distinct stat
	
	Traced and confirmed: `build_upward` was never a separate tracked value — no such key exists or ever existed in code. It was descriptive language for what the existing height-decayed build-stacking preference (inside `_execute_build`) already does: taller monuments become progressively less likely to keep stacking, an effect already parameterized entirely by the single `build` CCE weight (Dustan confirmed: added specifically to cap tower height and differentiate tall/narrow from wide/area monuments, not as a player-chantable stat of its own). Stage (a)'s use of `_compute_colony_avg_build_cce` (keyed on plain `"build"`) is correct as originally implemented — no revision needed.
	
	### Applied: preset tuning for Shape D verification (not a final balance decision)
	
	Both presets had `defend = 0.0`, making `shape_d_prob` structurally always 0 — no diagnostic data possible. Raised `defend` 0.0 → 0.10 in both `COLONY0_CCE` and `COLONY1_CCE`, each tagged with an explicit "verification tuning pass, not a final balance decision" comment. Confirmed via inspection: weights are raw softmax inputs (`exp(weight)`, no normalization/clamp, only a `>0.0` pool-membership gate) — raising defend proportionally suppresses every other pooled action ~16–17% relative in both colonies, including a small dip to `observe` itself (the self-interaction: observe is what feeds the very observations Shape D depends on). Small, judged acceptable for a diagnostic.
	
	Resulting math: **COLONY0** — defend 0.10 × avg_build ≈0.40 × 2.0 = **0.08** (non-degenerate, useful telemetry expected). **COLONY1** — avg_build = 0.0 (COLONY1's `build` weight is 0 for every dot), so `shape_d_prob` = **0.0 regardless of defend value** — structurally degenerate, not fixable without also raising COLONY1's `build`, which is out of scope for a tuning pass (a real balance decision). **Decided: accept COLONY0-only useful Shape D telemetry** for this verification; COLONY1 logging clean, correctly-computed zeros is still valid confirmation the zero-build case computes correctly rather than erroring. Not touching COLONY1's `build` right now. Not yet committed.
	
	### Still pending — next session starts here
	
	1. **Live verification run has not happened yet.** Run a two-colony session with the tuned presets in place; confirm `shape_d_roll` telemetry shows sane, non-degenerate probability/success values on COLONY0, and clean (correctly-zero, non-erroring) records on COLONY1.
	2. Once verified, proceed to stage (b) (wall banner data structure + drop), per the staged roadmap above.
	3. `main.gd` currently carries two uncommitted pieces: stage (a)'s diagnostic code and the preset tuning pass. Plan is to commit them together (the tuning only exists to exercise stage (a)'s new code — same reasoning used earlier this session for bundling the observe-gate fix with its own diagnostic) — flag if a split is wanted instead.
	4. Combat-effectiveness/tiered-balance redesign (luck modifier, banner tiers, roll-twice-take-highest) remains fully parked — a separate future design pass, only scoped when explicitly picked up.
	
	
	---
	
	## Session Notes — 2026-07-07 (cont. 2) — waller stage (a) verified live, stage (b) shipped, block-immunity finding discovered
	
	### Context
	
	Continuation of the same session. Stage (a) (defend + Shape D diagnostic) got its live verification run; stage (b) (wall banner data structure) was designed, implemented, and also verified live. A separate, unrelated finding surfaced during the stage (b) verification run and is recorded here flagged, not resolved.
	
	### Verified live: stage (a) + preset tuning (191→177-tick runs, run_id 1783462314)
	
	`shape_d_roll` behaved exactly as designed: COLONY0 held a constant computed probability of 0.08 across 4,652 rolls (matches the predicted math, `0.10 defend × 0.40 avg_build × 2.0 scale`, exactly), with 363 empirical successes — a 7.80% empirical rate against an 8.00% theoretical rate, essentially a perfect match and strong confirmation the `randf() < prob` roll itself works, not just that the formula computes correctly. COLONY1 held a constant 0.0 (its `build` weight is 0, so `avg_build` is 0) across 2,748 rolls with zero successes and zero errors — the degenerate case computes cleanly. `observe_age` continued to show a healthy distribution (min 1 / max 9 / mean 2.21), no regressions. This closes out stage (a) verification.
	
	### Shipped: stage (b) — wall banner data structure, dropped on Shape D success
	
	Per the staged waller roadmap. Modeled on the rally banner's minimal shape (event-side-effect drop; no `id`/cap/count — the build banner's heavier structure wasn't justified since this stage has no block or cap to track yet). New `wall_banners` list (`{cell, colony, ticks_remaining}`), `WALL_BANNER_RADIUS` (15, explicitly inert until stage (e) consumes it) and `WALL_BANNER_TTL` (6, matching both existing banner types), `_drop_wall_banner` and `_tick_wall_banners` mirroring the rally banner's functions exactly (dedup/refresh by cell+colony, else append; decrement-and-expire on tick). Wired additively into stage (a)'s already-computed `shape_d_success` boolean — the existing `shape_d_roll` telemetry line is untouched, a `wall_banner_dropped` event fires alongside it (on both the refresh and fresh-append paths) whenever a success lands a live banner. Nothing consumes `wall_banners` yet — stages (c)/(d)/(e) still ahead.
	
	### Verified live: stage (b) (run_id 1783462314, same run as above)
	
	264 `wall_banner_dropped` events, exactly matching COLONY0's 264 `shape_d_roll` successes out of 3,113 rolls (8.48% empirical this run, still consistent with the 8% theoretical). Zero from COLONY1, as expected. Stage (b) confirmed working exactly as designed.
	
	### Finding (flagged, not resolved): block-defenders show a fixed d_power regardless of stack height, and winning a fight doesn't reliably destroy the block
	
	Dustan observed in play: monument blocks one layer tall got cleared by attackers; two-or-more-layer blocks appeared immune. Hypothesis offered was that stacked defense value might exceed attacker power. Checked directly against this run's `combat_resolve` telemetry (204 block-defender fights): **`d_power` was exactly 0.5 in all 204 fights, with zero variation** — stacking-adds-defense is refuted directly, `WALL_DEFEND_VALUE` really is fixed regardless of height. `a_power` was also exactly 0.5 in all 204 (a dead-even tie every time), and the attacking colony won all 204 — consistent with ties going to the attacker.
	
	But grouping those 204 fights by cell surfaced the real phenomenon: only **44 distinct cells** account for all of them, and while most were fought 1–3 times (consistent with quick one-block clears), several were fought far more — one cell was fought **12 separate times across a 30-tick span** (ticks 152–181), with the attacker winning every single logged fight there and combat still recurring at the end of the run. **Winning a `combat_resolve` against a block does not appear to reliably destroy it** — likely because a multi-block stack needs its layers cleared individually and something in that bookkeeping isn't behaving as expected, though the actual mechanism (per-layer health tracking? re-selection of the same top block without state change? something else?) has not been traced in code — this is telemetry-grounded pattern-spotting, not a code-level diagnosis. Explicitly not investigated further this session; needs its own inspection. Unrelated to the waller roadmap in progress, but worth fixing given it directly affects how "a wall dies" will need to work once stage (d)'s waller lock depends on wall-death as its unlock condition.
	
	### Not committed yet
	
	`main.gd` carries stage (b)'s 31-line additive diff, uncommitted as of this note. Plan is a single commit (mirrors stage (a)'s bundling reasoning — this is one coherent, already-verified piece of work).
	
	### Next
	
	1. Commit + push stage (b).
	2. Block-immunity finding needs its own inspection (separate from the waller roadmap) before combat-walls can safely depend on "wall death" as a concept in stage (d) — worth resolving before, not after, the waller lock is built on top of it.
	3. Otherwise, waller roadmap continues at stage (c) (oriented half-thickness block + mesh) once picked up.
	

---

## 2026-07-10 — Multi-block stack destruction: block-immunity finding inverted, topmost-removal + count-based combat lock (committed 4319c3e)

Session picked up the block-immunity finding from 2026-07-07 (queued as its own inspection). Baselined clean at ff19e57, level with origin. Fresh session note: the git repo + Godot project root is the nested `dots/` subdir, not the outer `Dots/` container — the outer path is not a repo.

### The finding was inverted by inspection

The 2026-07-07 note hypothesized "winning a `combat_resolve` against a block does not reliably destroy it." Inspection refuted that directly: a won block-defender fight DOES delete a node unconditionally (`to_delete[defender] -> _remove_dot`, no failure path; 204/204 attacker wins = 204 real deletions last run). The visible immunity was three compounding facts, not a failed deletion:

	1. Removal ordering (defect): within a stack cell all blocks tie on distance, and the strict `<` tie-break keeps the FIRST array occupant (oldest = stack_index 0 = bottom). So combat always deleted the BOTTOM node; survivors never repositioned, so the silhouette never shrank — floaters.
	2. Build/combat concurrency (defect): `_execute_build` had zero combat awareness; COLONY0 block count grew 16 -> 2163 monotonically in one run, swamping serialized combat removals (~1 per 3 ticks per cell) roughly 10:1. Re-adds overlapped floater heights because stack_index is recomputed as live node count.
	3. Fixed `d_power = 0.5` (NOT a defect): per-node BLOCK_DEFEND_VALUE, as designed. This closes the stacking-adds-defense thread permanently.

### Concurrency confirmed empirically

Before choosing lock design, checked telemetry (run 1783466273) for two block-fights live on one stack cell in the same tick: found it — cell (125,111) had x2 `combat_init` at tick 165 and x2 `combat_resolve` at tick 168. So the lock had to be a COUNT, not a boolean (a boolean released on first resolve reopens the race while a second fight is still live). Records key attacker by colony only, not dot id, so this is "can happen" established empirically rather than reasoned away.

### What shipped (commit 4319c3e, main.gd only, 68 insertions / 4 deletions)

	Topmost-removal: the block-win branch in `_tick_combat_clusters` now selects the highest-stack_index live same-colony block in the cell (not the targeted bottom node), with a per-resolution `block_defeated` tracker preserving "one layer per fight" semantics. Single-block behavior is byte-identical (traced: victim falls through to defender, same deletion, same advance, same claim).
	Count-based per-exact-cell lock: new `combat_locked_cells` dict, incremented once per new block-defender cluster in `_initiate_combat` (storing `locked_cell` on the cluster), decremented once per cluster teardown via the idempotent `_release_cell_lock` helper wired into both erase loops (`_tick_combat_clusters` resolution + `_remove_dot`). `_execute_build` skips locked cells at both create sites (banner-build + founder). Leak-integrity traced: every cluster is destroyed via exactly one of the two erase sites (grep-confirmed the only two), each releasing first; resolution erases the cluster before `_remove_dot` runs so no double-decrement; decay routes through `_age_dots -> _remove_dot`, also covered; marker-erase + n<=0->erase backstops prevent leaks and negatives. A cell always returns to 0.

### Verified

`validate_script` clean (exit 0). Live playtest (arbiter): towers visibly shrank 1-by-1 from the TOP. Telemetry corroboration (run 1783525138): snapshots carry a `combat_locked` field, non-zero in play (32 locked / 16 active at last snapshot) — the lock engages live and tracks with active combat, no runaway climb. Total COLONY0 blocks still grew (ended 2839) but that is off-cell building under banners on the side away from the aggression, NOT contested-cell growth — Dustan confirmed this visually. Design caveat holding as expected: sieges stay serialized (~1 layer per combat cycle per cell), so tall towers grind down slowly rather than collapsing.

### Committed, not pushed

HEAD 4319c3e, one commit ahead of origin/main, zero behind. `main.gd` only, message verbatim via `git commit -F` (no -m, no Co-Authored-By trailer), temp file deleted. Push not yet approved.

### Environment issue flagged (unresolved)

A fresh Code session could not read OR write `res://code_report.md` — "Operation not permitted" via both the Read tool and plain shell, while a sibling file wrote fine and the file itself shows normal perms/no ACLs. `.claude/settings.local.json` is denied identically. Reads as a deliberate tool-level deny rule scoped to Code's session (my MCP `read_script`/`execute_editor_script` access to both paths is unaffected — I can still read code_report.md). Code correctly refused to force-overwrite the unreadable existing report and wrote its output to `scratchpad/code_report.md` instead. UNRESOLVED: determine whether the deny rule is intentional (then permanently route Code reports to scratchpad) or accidental (fix the config). To be chased with a small prompt next.

### Next

	1. Resolve the code_report.md deny-rule question (intentional vs accidental).
	2. Max build height: towers got obscenely tall in play. Halve the max build height — needs a short inspection first to locate the cap (explicit constant? currently unbounded?) and its value before changing. Fresh Code session; orient off this DEVNOTES + independent git baseline.
	3. Waller roadmap resumes at stage (c) (oriented half-thickness block + mesh) when picked up. Stage (d)'s waller lock can now safely depend on wall-death — topmost-removal makes "the wall dies" actually work.


---

## 2026-07-11 — Monument height bounded (committed 7f6b640); code_report deny-rule closed as artifact; workflow moved to Claude Code desktop app

Goal was "halve the max build height." Inspection refuted the premise: there was no max build height to halve. This became a four-step arc, all now committed in 7f6b640 (main.gd, 83 insertions / 20 deletions), on top of 4319c3e.

### The premise was wrong — no cap existed

`_create_block` always creates, unbounded. The only height-aware code was `STACK_HEIGHT_SOFTCAP = 10`, a probabilistic stack-vs-lateral bias, and it was decorative: the ternary at ~717 collapsed to `banner_cell` for on-cell builders (`my_cell == banner_cell`), so the height roll did nothing and they stacked forever. That was the unbounded-growth source. Halving 10->5 would have done nothing to the spires (they route around the gate), so the halve-a-constant task was discarded.

### What shipped (option B — soft bound, not a hard cap; Dustan's explicit choice)

	1. On-cell height-gated lateral shed: on a failed height roll the on-cell builder sheds to a weighted-lowest ring neighbour via the revived `_pick_lateral_cell` (was intentionally-retained dead code; revival sanctioned, seam-wrap idiom preserved).
	2. Off-cell receiving-cell gate: off-cell builders now roll against `my_cell`'s own height (not the banner's) and shed to a weighted-lowest neighbour on failure, constrained to the banner footprint. This closed the dominant tall-cell route.
	3. Removed the ungated footprint fallback: `_pick_lateral_cell` now pre-filters candidates to eligible cells before the weighted draw; empty set -> Vector2i(-1,-1) sentinel -> skip the build (never place ungated). The fallback was the actual spire route (a cell reached height 23 via ungated `reason=self` builds above the softcap).
	4. Floored the height factor: `clamp(1 - h/SOFTCAP, STACK_HEIGHT_FACTOR_FLOOR, 1)` with floor 0.05. The softcap is now a strong-discouragement point, not a hard wall — exceedance is rare, not impossible. There is deliberately NO ceiling; what bounds a monument is the ~90-block banner budget, not height.

### Four named tunables now in the constants block

	STACK_HEIGHT_SOFTCAP = 10 (height where stacking bottoms out), STACK_HEIGHT_FACTOR_FLOOR = 0.05 (soft-bound creep rate above softcap), SHED_CONTAINMENT_DIST_SQ = 5 (shed target radius from banner, tighter than the 8 participation radius), SHED_ESCAPE_CHANCE = 0.15 (per-shed chance to skip containment and fray the edge). Tunable without code changes.

### Verified across live runs

Decisive, run-length-independent evidence in run after the final change: `reason=self` placements cut off sharply near the softcap (37/37/37 at h0-2 decaying to singletons at h10-11, nothing above) — structural proof the ungated fallback is gone, since no run length produces that cutoff by chance. `reason=shed` carries the rare above-softcap traffic. Max height 15 (a `stack` placement via the 4% floor). CAVEAT logged: cross-run max-height numbers (45->23->15) are partly confounded by run length (146->121->103 ticks); the self-cutoff is the real proof, not the max trend.

### Still boxy — deferred, not fixed

Footprint is still a 5x5 box, NOT rounded. Reason: `SHED_CONTAINMENT_DIST_SQ` only governs sheds, but `self` is the majority of placements and lands wherever the dot stands, i.e. anywhere in the 5x5 participation radius (`BUILD_FOOTPRINT_DIST_SQ = 8`). The base outline is set by participation, which was non-goaled. Rounding the base means touching the participation radius (affects who can build at all) — its own pass, deferred. `SHED_ESCAPE_CHANCE` fray is also weak (only rim builders' escapes leave the footprint). Dustan is satisfied with current look for now.

### code_report.md deny-rule — CLOSED as a session artifact (corrects the 2026-07-10 open item)

The 2026-07-10 entry left this open and leaned toward "deliberate deny rule." Resolved: it was session-scoped, not a real rule. A fresh Code session read the path fine; the earlier failure did not recur. My MCP access to the path was never affected. Do NOT chase this as a config problem — it was a transient session-state artifact. Reports route to `res://code_report.md` as normal.

### Workflow change — now driving Code via the Claude Code DESKTOP APP (was CLI)

Same engine, same account, same CLAUDE.md / .mcp.json / .claude config / MCP servers / permission rules — only the surface changed. First desktop commit (7f6b640) verified the two things that could have broken our discipline, both OK: (1) NO worktree divergence — the app commits to the same working tree `/Users/.../Dots/dots` that my Godot-editor MCP inspects (independently confirmed HEAD 7f6b640 matches on both sides); (2) `code_report.md` writes succeed under the app (deny artifact did not recur). One drift to watch: the app APPENDED its report to code_report.md rather than overwriting per convention — restate "overwrite" in future prompts. Standing rules unchanged: per-action git approval (do NOT accept blanket/always-allow in the app's permission UI), Code never runs the game, planner reads reports not source.

### Git / next

HEAD 7f6b640, 2 ahead of origin/main, 0 behind. NOT pushed (awaiting Dustan). DEVNOTES.md modified/unstaged (this entry) — its own commit per convention, separate from feature commits.
	1. Decide push (2 commits: 4319c3e stack-destruction, 7f6b640 monument-height).
	2. Optional: round monument base (needs a participation-radius pass — structural, affects build eligibility).
	3. Waller roadmap resumes at stage (c) (oriented half-thickness block + mesh). Stage (d)'s waller lock can depend on wall-death — now reliable.


---

## 2026-07-21 — Pushed 7f6b640; waller stage (c) shipped (uncommitted); build-vs-wall banner priority gap found, unconditional-priority decided; handoff to Fable

### Pushed

Both queued commits (4319c3e stack-destruction, 7f6b640 monument-height) pushed to origin/main, explicit per-action approval from Dustan. `github.com:dkentbrown/dots.git main` now at 7f6b640, 0 ahead / 0 behind.

### Shipped: waller stage (c) — oriented half-thickness wall block (not yet committed)

Per the staged roadmap. Orientation contradiction in the original design spec (DEVNOTES 2026-05-13: line ~868 said long-axis-toward-enemy under "Locked"; line ~884 said long-axis-perpendicular-to-threat under "Open questions") — **resolved: perpendicular to threat**, matching how other wallers later extend the wall line (stage e) so a lone waller's block and the eventual multi-waller line are geometrically consistent.

New `WALL_MESH_SIZE` constant (half-thickness on the facing axis vs `BLOCK_MESH_SIZE`, long axis kept at full cell spacing to tile with future wall-line segments). New `_create_wall_block(cell, colony, threat_dir, builder_id)`, deliberately separate from `_create_block` (different mesh size, orientation source, and no monument stack-index scan) but still `is_block`/`BLOCK_DEFEND_VALUE`/decay so it fights and decays like any block. Reuses `_create_block`'s exact cross-product frame pattern with the reference vector swapped from a fixed world axis to the live threat bearing (`target.position.normalized()`); includes the same degenerate-case (near-parallel-to-normal) fallback `_create_block` uses, to avoid a NaN basis. Wired into the existing Shape D success branch in `_execute_primitive`'s `"defend"` arm, alongside the existing wall-banner drop. `validate_script` clean. Untested in-engine as of writing this note — Dustan was going to test in the Godot editor.

### Live-test finding: build-vs-wall banner priority gap (confirms open question #4, not a tuning problem)

Dustan observed in play: once a waller drops its block, the rest of the population responds to the *build* banner system and piles into a normal monument, ignoring the threat entirely — no wall-line extension happens (stage e isn't built yet) and nothing redirects builders away from ordinary monument behavior. Traced in code, not inferred: `wall_banners` and `build_banners` are two fully separate lists; `_find_eligible_build_banner` (main.gd:854) only ever reads `build_banners`, and nothing anywhere reads `wall_banners` for build-routing purposes. There is no arbitration code at all between the two banner types — this is exactly open question #4 from the original 2026-05-13 spec ("Wall banner vs build banner priority... Lean: wall banner. Not finalized."), now confirmed as the live-observed cause rather than a CCE-tuning issue.

**Decided:** priority is unconditional, not CCE-gated. Any dot in range of an active wall banner drops ordinary build-banner response entirely in favor of the wall response — "dots should ignore monument building in the face of an existential threat," Dustan's words. Simpler to spec than a defend/build-weighted gate, and avoids the awkward case of a low-defend dot standing next to a dying wall doing nothing useful. Not yet implemented — this is a decision, not code.

### Handoff

Session moving to Fable for the priority-arbitration design + stage (e) (other wallers extend the wall line perpendicular to threat bearing) with this note as context. Not scoped or touched by Code this session.

### Git / next

`main.gd` carries stage (c)'s ~60-line uncommitted diff; `DEVNOTES.md` carries this entry, also uncommitted. HEAD still 7f6b640 (0 ahead/0 behind origin, post-push).
	1. In-engine test of stage (c)'s wall-block orientation/geometry (Dustan, pending).
	2. Fable: design + implement wall-banner-vs-build-banner unconditional priority, then stage (e) (wall-line extension).
	3. Commit stage (c) once verified — bundle with the priority/stage-(e) work if Fable's changes land in the same session, per the established bundling convention, or flag if a split is wanted.


---

## 2026-07-21 (cont.) — Waller stages (c)+(d)+(e) shipped & verified; wall-banner priority; role expanded to planning+implementation

Fable was on usage credits, so this ran on Opus (same Claude Code desktop app, same config). Stage (c) (uncommitted from the prior Code session) plus stages (d)/(e) and the priority arbitration were all implemented, verified live by Dustan ("works pretty well"), and are being committed together as one coherent waller-consumption unit — per the bundling convention noted in the prior entry.

### Role change — Code is now the planning AND implementation layer

Dustan: "you are now the planning and implementation layer." Reversed the prior implementation-only split (planning/review no longer routed elsewhere) — the project "has been drowning in inspections, time to get things knocked out." Acted on immediately: this session did its own scoping (read the roadmap + code) and carried the implementation through in one pass rather than stopping at an inspection. CLAUDE.md line 1 was reconciled to match ("You are the planning and implementation layer for this project. Scope the work, carry it through, and report accurately." — was "You are the implementation layer... Planning and review happen elsewhere."). The INSPECTION/IMPLEMENTATION/TRIVIAL prompt-type framework and all standing rules (no commit/push unless asked, minimal safe change, report format) are unchanged. Also: appending DEVNOTES is now part of Code's job, not just the planner's.

### What shipped (main.gd)

- **Wall-banner priority (unconditional arbitration).** `_execute_build` now consults `_find_nearest_wall_banner` before any monument logic; an in-range same-colony wall banner (`WALL_BANNER_RADIUS = 15`) fully overrides monument building for that roll and routes to `_respond_to_wall_banner`. Because only build rolls reach `_execute_build`, build-heavy populations naturally swarm the fence while attackers/defenders keep doing their own thing — this is the mechanism behind "a build-heavy population builds a fence." Even a full fence idles the dot rather than letting it fall back to a monument (the "existential threat" framing).
- **Stage (e) — fence extension.** Wall banners now carry `threat_dir` (threaded through `_drop_wall_banner`, refreshed on re-drop). `_wall_line_target_cell` walks outward from the banner seed along the tangent perpendicular to the threat (exact great-circle steps via `seed_dir*cos + along*sin`), alternating sides, returning the first empty, non-combat-locked cell within `WALL_MAX_HALF_LENGTH = 4` (fence ≤ 9 cells). A responder marches there, then places an oriented segment and fires a `wall_extend` telemetry event. Fence full → `(-1,-1)` → idle.
- **Stage (d) — perch + lock.** New `wall_perch` dict (waller_dot -> wall_block) with an inverse `perched_by` ref on the block. `_perch_waller` sits the builder one `BLOCK_HEIGHT_STEP` above its segment; `_tick_all_dots` skips perched dots entirely (no rolls, not even observe). Teardown lives in `_remove_dot`, covering both directions: a dying segment (combat OR decay — both route through `_remove_dot`) releases its builder back to the surface via `_place_dot_on_sphere`; a builder that dies first clears the segment's back-ref so no stale reference remains. The original stage-(c) waller in the defend arm now also perches + returns early (skipping its colony-center march) on Shape D success, guarded so it only founds a segment on an empty, non-locked cell.

### Design notes / caveats

- **Build-tendency is the throttle, by design.** Only dots that roll "build" extend the fence, so a low-build colony walls slowly/sparsely. Faithful to the unconditional-priority decision + "build-heavy population." If we later want ANY nearby dot (non-builders too) to drop everything and wall, that's a bigger hook (intercept before the primitive roll) — flagged, not done.
- **Perched wallers are still valid combat targets** (normal dots sitting on the block). An enemy can kill the builder directly; the segment then stands builderless until it decays or is destroyed. Consistent with "the wall persists independent of its builder."
- **Fence geometry is a single-file line, seed-outward.** `WALL_MAX_HALF_LENGTH` and the perpendicular tangent are the knobs. Great-circle step is exact; cell quantization could drift a cell near the ends only if the cap is raised well beyond 4.

### Verified

`validate_script` clean throughout. Live in-engine test by Dustan: fence-building behavior "works pretty well." No telemetry deep-dive this pass — the visual confirmation was the bar.

### Git

Committing three focused units this session (main.gd feature / DEVNOTES log / CLAUDE.md role line) and pushing, at Dustan's request. This is the first time Code commits DEVNOTES + CLAUDE.md itself under the expanded role.


---

## 2026-07-21 (cont. 2) — Waller stage (f) verified via telemetry; fence color + defender_was_wall tag; combat-walls arc CLOSED

Stage (f) ("block-attackability — not real work, a live-run verification") is done, and the whole waller roadmap (a)–(f) is now complete and verified. Two small polish changes shipped alongside, then the arc was closed.

### Shipped (main.gd polish)

- **Fence color.** Monument and wall blocks were visually identical because both share the block CCE (`NEUTRAL` + `defend=0.5`) and `_update_dot_color` recomputes colour from the CCE mix — the `Color.CYAN` set in `_create_wall_block`'s constructor was always overridden. Fix: an explicit `is_wall` marker in the wall block's `dot_data`, a new `WALL_COLOR = Color(0.0, 0.95, 0.8)` (bright teal — not a CCE hue, so no semantic clash), and a branch in `_update_dot_color` that renders `is_wall` blocks in `WALL_COLOR`. Placed AFTER the fog-of-war check so hidden colonies still fog, and it survives colour refreshes (e.g. on reveal). Monument blocks untouched (pale defend-blue).
- **`defender_was_wall` telemetry.** `combat_resolve` now tags whether the defender was a fence segment (reads the same `is_wall` marker), so "attackers hitting the wall" is separable from monument combat without cross-referencing cells against `wall_extend`.

### Verified live (telemetry parse, run isolated from the last run_start; 206 ticks)

Dustan ran the game; Code parsed `telemetry.jsonl`. Note the file is cumulative across runs (11 run_starts now) — always slice from the final `run_start`. Findings for the waller loop:

- **Builds:** 312 `wall_banner_dropped` + 112 `wall_extend`, ALL colony 0 (the outnumbered side), none from the enemy — as designed.
- **Intercepts:** first fence-combat at t135 (enemy arrival); **56 `combat_resolve` with `defender_was_wall: true`**, plus 36 vs monument blocks — **92 of 262 total combats (35%) spent on structures, not colony-0 dots.**
- **Dies + regenerates:** all 56 fence fights won by the attacker (a_power ≥ d_power, ties-to-attacker; the fence is a speed-bump, not impenetrable), each firing the "wall dies → waller unlocks" path. The banner kept re-dropping (312×) and wallers kept rebuilding (112 extensions), so the line regenerates — a living defensive wall.
- **Held up:** colony 0 was outnumbered the whole back half (enemy pinned at its 1000 cap from ~t143) yet never collapsed — grew straight through the assault (419 dots at t135 → 648 at t206) while the fence absorbed ~a third of enemy combat throughput.

### Honest caveats (recorded, not blocking)

- Not a controlled A/B: this proves the *mechanic* (build → intercept → die → release → regenerate), NOT that colony 0's survival was *caused* by the fence vs. its own reproduction. A fenced-vs-unfenced comparison run would be needed to quantify the survival delta — deferred, not required to call the mechanic done.
- Perched-waller count is NOT directly visible in telemetry: snapshot `combat_locked` is the active-combat dict, not `wall_perch` (which isn't snapshotted). Perching was inferred from the build→die→rebuild cycle working. A one-line perch/unlock telemetry event would make it directly visible if ever wanted.

### Waller roadmap — FINAL STATUS

(a) defend+Shape D ✅ · (b) wall banner ✅ · (c) oriented segment ✅ · (d) perch+lock ✅ · (e) fence extension ✅ · (f) verification ✅. **Combat-walls arc closed.**

### Git

Bundling this polish as one `main.gd` commit + this DEVNOTES entry (its own commit), pushed at Dustan's request. Enemy colony spawn is live (`main.gd` `_ready`), so this all exercises in normal play.

### Next (backlog, per the "where to" survey this session)

Two genuinely large threads remain, both needing a design pass before code: (1) **North Star behavioral model** — 8 of 9 P(r) score terms (M/T/S_am/S_at/S_mt/C/E/H) are dormant zeroed stubs; lighting them up is the sim's core behavioral depth. (2) **Combat-effectiveness / tiered-balance** — defend banner + roll-twice-take-highest luck modifier, never scoped. Plus tech-debt (uniform detection radius / equirectangular distortion) and UX (gather verb unreachable — no chant alias). None urgent; combat-walls no longer blocks any of them.
