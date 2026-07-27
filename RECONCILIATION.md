# NOEMA — Bible ↔ Code Reconciliation

**Status:** draft for review · created 2026-07-21 · restructured 2026-07-21 around the three-tier spine · updated 2026-07-24 (Tier 1 recipes; first canon call — S.c soul) · updated 2026-07-25 (T2.c RESOLVED — linear selection; T1.e canon call + shipped — Tier-1 move-mode collapse; three-tier build roadmap) · all merged to `main` via PR #1 (2026-07-26) · author: Claude Code (planning+implementation layer)
**Sources:** `Noema_Design_Bible_v0.4.docx` (design canon) vs. `main.gd` (current code) + `DEVNOTES.md` (tactical log).

## Why this document exists

The bible (v0.4) and the code drifted apart — a lot of built machinery isn't in the doc, while the doc's core is only partly built, and with no declared source of truth "what next?" had no anchor. This is the gap analysis the roadmap is built on. For each divergence, make a **canon call**; the roadmap falls out of the calls.

**Canon-call legend** (write into each `DECISION:` field): **BIBLE** = doc wins, pull code toward it · **CODE** = code wins, update bible to v0.5 · **MIX** = partial (say which) · **DEFER** = real but not sequenced now.
**Cost key:** **S** = hours · **M** = a few sessions · **L** = major undertaking.

---

## The spine: the three-tier model

The organizing frame (from DEVNOTES 2026-05-28) is a **three-tier civ model**, and it maps cleanly onto the bible — it's the bridge between the two:

| Tier | Model term | What it is | Bible equivalent |
|------|-----------|------------|------------------|
| **1** | **Verbs** | atomic per-dot primitives, one fired per tick from CCE | motion + action **primitive layers** |
| **2** | **Modes** | emergent colony-scale behaviors from weighted primitive combos (fortify, swarm, patrol) | **ECBs** (Emergent Culture Behavior) |
| **3** | **Motifs** | named persistent structures/states from sustained modes | monuments, wall lines |

Everything below is organized by tier, plus a **substrate** section for the foundations that cut across all three (dilution, blending, the server spine, the selection model).

**The one deep question underneath it all** lives at **Tier 2**: should colony-scale modes *emerge* from Tier 1 combinations (the bible's model — "none of these are scripted"), or be produced by *bespoke coordination machinery* (the code's banners)? That single call drives most of the rows.

---

# TIER 1 — Verbs (the primitive vocabulary)

**Status: essentially complete against the bible (as of 2026-07-21).**

The bible's fixed vocabulary is motion = wander, cluster, spread, face_target, spiral_path · action = mark_surface, build_upward, gather, defend, attack, reproduce. All are now wired:

- Previously live: `move` (wander), `defend`, `attack`, `reproduce`, `build` (build_upward).
- **Just added** (this session): `cluster`, `spread`, `spiral_path`, `face_target`, `mark_surface` — executors + CCE slots (at weight 0.0) + helpers. Compiles clean; dormant until recipes/test-weights raise them.

### T1.a — `gather` reachability — ✅ NOT A GAP (this row was wrong)
**Correction (2026-07-24):** `gather` was already reachable. `CHANT_RECIPES` has carried `gather`/`collect`/`forage`/`harvest` since commit `209e057` ("feat: add gather chant trigger co-raising gather and observe"), each raising `gather` **and** `observe` by `CHANT_WEIGHT` — the co-raise is deliberate, because the composite needs a live speck observation to consume. The original claim here was drawn from a stale comment in `main.gd` (since corrected) that said "Dead primitives (gather/build/mark) intentionally absent".
**The verb that is actually unreachable is `build`** — it has an executor (`_execute_build`) and COLONY0 starts it at 0.40, but no chant alias exists, so a player cannot raise it. Flagged, not fixed; not yet approved as work.
`DECISION: n/a — no divergence. Successor gap: `build` alias, unsequenced.`

### T1.b — `observe` (in code, not in bible)
**Code:** a full action primitive (enemy/speck/ally/banner sensing → `pending_observe`). **Bible:** no `observe`. But the 2026-05-28 Tier 1 list *did* include it, so it has an internal claim to being a legit verb.
**Rec: CODE (bless into v0.5) — it's load-bearing for detection and predates the bible drift; document it as a Tier 1 verb. Cost: S (doc only).**
`DECISION: ______`

### T1.c — recipes: making the new verbs reachable — ✅ SHIPPED 2026-07-24
20 aliases added to `CHANT_RECIPES`, four per verb:

| Verb | Chant words | Dial nudge |
|---|---|---|
| `cluster` | cluster · huddle · together · flock | `range −0.05` (tighter cohesion) |
| `spread` | spread · scatter · disperse · apart | `range +0.05` |
| `spiral_path` | spiral · coil · twist · whirl | `spiral +0.1 / +0.05` |
| `face_target` | face · turn · confront · stare | `range +0.05` (wider scan) |
| `mark_surface` | mark · paint · stain · trace | `intensity +0.05` (deeper, longer-lived) |

`spiral` deliberately raises **both** the `spiral_path` primitive and the legacy `spiral` dial — they coexist until T1.d rules on retiring the dial. Payload shape is the bible's `/chant` contract (`{motion, action, dials}`), so S.b's contract alignment is satisfied: flipping `USE_SERVER` swaps where the dictionaries come from without touching `_apply_recipe`.

**Not done:** multi-word chants. `_process_chant_locally` still does an exact whole-string lookup, so the bible's own §5.3 examples (`'wander far'`, `'build tall toward the moon'`) **do not parse**. Tokenizing on whitespace is ~5 lines. Unsequenced.
`DECISION: BIBLE — done. Residual gap: multi-word chant parsing.`

### T1.d — dials (range, intensity built; frequency, affinity, spiral unresolved)
**Bible dials:** range, intensity, frequency, affinity. **Code dials:** range, intensity, **spiral**, with frequency/affinity reserved-unbuilt.
- `frequency`, `affinity` unbuilt. Superseded by T1.e below — the cluster/spread/face_target work `affinity` was meant to carry is now the **move-mode layer**, not a single scalar dial.
- `spiral` is a **dial** in code but `spiral_path` is a **primitive** in the bible. Retires under T1.e (spiral becomes a move-mode).
**Rec: folded into T1.e. Build `frequency` (cheap) separately if/when needed.**
`DECISION: → see T1.e`

### T1.e — Tier 1 collapse: cluster/spread/face_target/spiral → move-modes; mark → build/move motif ⚑ CANON CALL 2026-07-25
**Decision (Dustan):** `cluster`, `spread`, `face_target`, `spiral_path` are **not verbs** — they are **modes of `move`** (cohesion / dispersion / confrontation / spiral: *how* a dot moves). `mark_surface` is **not a verb** — it is a **motif of two parents**: ornamentation on `build` (decorated monuments) and paths/roads from `move`. A mark is a trace those verbs leave, never a chosen per-tick action.

**Resulting Tier 1 (7 verbs):** `move, gather, build, defend, attack, reproduce, observe`. The motion layer collapses to a single verb (`move`). This **supersedes the bible's §5.1 motion list** (wander/cluster/spread/face_target/spiral_path) → v0.5.

**Why it's right:** each demoted item was a "secret move-mode" or a persistent trace, never an atomic distinct action; the affinity dial (T1.d) was already defined to carry exactly the cluster/spread bias. Collapsing also sharpens top-level selection (fewer pool competitors — compounds the linear-selection win) and is the concrete form of roadmap **step 2 (modes)** + **step 3 (motifs)**.

**The design question the collapse hinges on — how modes attach:** a single scalar `affinity` dial CANNOT encode the four modes (toward-allies vs toward-enemies vs tangential are not one axis). So modes need a small **move-internal layer** — a named-mode weight set (cohesion / dispersion / spiral / confront) consulted *when move fires*, fed by CCE, NOT competing in the top-level verb pool. This is the first concrete instance of the NS recipe `r = action + mode` (move + mode), i.e. the beginning of the capstone architecture, arriving bottom-up.

**Build order (no behaviour lost at any step):**
1. ✅ **SHIPPED 2026-07-25.** Move-mode layer (`cce["modes"]` = cohesion/dispersion/confront) + `move` reads it: per-fire linear roulette (`_pick_move_mode`) over the modes + a `MOVE_DRIFT_BASE` drift baseline; mode bodies reuse `_local_ally_center` (cohesion toward / dispersion away) and `_find_nearest_foreign_in_radius` + `_face_dir` (confront = advance on nearest enemy, a semantic upgrade from the old orientation-only face_target). Modes are NOT in the top-level selection pool.
2. ✅ **SHIPPED 2026-07-25.** `cluster/spread/face_target` removed from Tier 1 (NEUTRAL_CCE, both presets, TEST_FIELD_BASE, selection); their chant words (`cluster/huddle/…`, `spread/scatter/…`, `face/turn/confront/…`) repointed to raise move-mode weights (+ a little `move`). Modes wired through `_apply_recipe`, dilution, `_make_field_cce`. New per-colony `move_modes` telemetry. Field harness updated (clusterers→**cohesive**, spreaders→**dispersive**, facers→**confront**).
   - **`spiral` KEPT as a verb** (Dustan): a spiral is a self-contained path, not a relational bias — genuinely verb-like. The `spiral` dial stays too (amplifies spiral_path); not retired.
3. ⏳ **PENDING (Tier 3, later).** `mark` → motif: `mark_surface` still a verb for now; re-express as build-ornamentation + move-road traces once the motif feedback layer exists.
`DECISION: BIBLE-superseding (v0.5). Representation = move-internal mode layer (recipe = move + mode), signed off. Steps 1-2 shipped; step 3 (mark motif) deferred to Tier 3.`

---

# TIER 2 — Modes (emergent colony behavior) ← the live design fork

**Status: this is the real open question. Modes are currently produced by bespoke banner machinery; the bible wants them to emerge.**

### T2.a — coordination architecture: bespoke banners vs. emergence
**Code:** colony-scale coordination runs on **banners** — a dot drops a shared marker (rally / build / wall), other dots respond to it. This is uniform across attack, build, and wall — a foundational, deliberate pattern that predates wallers.
**Bible:** coordination-free — each dot acts on its own CCE + local environment; the *only* inter-dot channel is passive CCE blending. Modes/ECBs *emerge* from aggregation; nothing is stored or scripted.

**What we clarified this session (corrections to the first draft):**
- Banners are **not player-controlled** — they fire off CCE the player built organically. That earlier claim was wrong and is struck.
- The design intent is that a mode/banner is a **late-game, heavily-specialized, higher-tier emergent behavior** — a dot having *enough* CCE to build/attack/wall should NOT trigger a banner; only *deeply accumulated, specialized* CCE should. That's a **two-tier emergence**: shallow CCE → individual verb (Tier 1); deep specialized CCE → coordinated mode (Tier 2). This is squarely in the bible's spirit ("emergence when *enough* dots share *enough* CCE"), just at a higher threshold — the bible simply never formalized it.

**So the honest state:** banners aren't a violation, they're an *undocumented higher tier* — BUT the current gating doesn't match the intent (see T2.b). The purity question (bespoke banner vs. `mark_surface`+`affinity` emergence) is real but **not urgent** — a banner is a working implementation of CCE-gated coordination.

**Rec: CODE-leaning MIX.** Bless banners into bible v0.5 as the "cultural crystallization / mode" mechanism (formalize the two-tier emergence). Keep the option open to later re-express banners as `mark_surface` + `affinity` for purity, but don't force it. **Cost: M (bible v0.5 section) / L (optional later re-derivation).**
`DECISION: ______`

### T2.b — banner gating doesn't match the "heavily-spec'd" intent
Audited against the intent above:
- **Rally (attack) banners** — drop on *combat contact*, no CCE-accumulation gate at all. Most out of line.
- **Build banners** — founded on a flat `BUILD_START_CHANCE = 0.05` roll; monument *size* scales with `avg_build` but *activation* doesn't require heavy spec. Out of line.
- **Wall banners** — gated on Shape D = `defend × avg_build × scale` (multiplicative → needs both stats high → genuinely rare). **This is the template the others should match.**
**Rec: BIBLE/CODE (whichever way T2.a lands) — retune activation gating so banners require heavy, specialized CCE, using wall's Shape-D as the model; concentrate on rally + build. Cost: M.**
`DECISION: ______`

### T2.c — the selection model: NS softmax vs. bible linear ✅ RESOLVED 2026-07-25
**The full story (corrected after reading the NS source, `procedural_civ_primitives_report`):**
- **NS §11:** `P(r) = softmax(A_action + M_mode + T_motif + S_am + S_at + S_mt + C_chant + E_env + H_history)` where **`r = action + mode + motif`** — a composite RECIPE, not a bare verb. Softmax is correct *there*: nine live terms, a wide signed score range, negative synergies. It operates one tier ABOVE primitive selection.
- **Bible §5.1 (supersedes):** "chosen probabilistically from the combined motion and action weight pool" — plain **linear** weighted pick over Tier 1 primitives. The bible deliberately collapsed the NS's recipe-softmax into a simple pool roulette.
- **Code (the bug):** grafted the NS softmax onto the bible's simplified space — `exp(score/T)` over bare Tier 1 weights in `[0,1]` with only `A` live. Faithful to NEITHER doc. Softmax on a tiny non-negative range with 8 dead terms does nothing but **compress**.

**The compression, measured:** saturated specialist (primary 1.0, ten others at 0.06 baseline) fires its primary **20.4% under softmax vs 62.5% under linear**; a verb at weight 0.10 fires **19.8% under softmax vs 7.7% linear** (softmax over-represents low weights, so "a bit of everything" floods behaviour). A chant doubling a weight (0.4→0.8) buys **1.5× under softmax, 2× linear**. This is the root of BOTH the muddy-specialists problem and the weak soul-pivot (S.c is throttled by this curve, not by the multiplier).

**The 8 dormant terms are NOT junk scaffolding** (my earlier "non-core" call was half-wrong). They are the **Tier 2/3 model** (modes, motifs, environment, history) waiting for inputs that do not exist yet. They read zero because modes/motifs aren't built — not because they're wrong. When Tier 2 exists, the NS softmax returns *above* primitive selection, exactly where §11 puts it.

**DECISION (Dustan, 2026-07-25): BIBLE — linear Tier 1 selection now; NS softmax reserved for the eventual recipe (mode/motif) tier.** Implemented as a `SELECTION_SOFTMAX` flag (`false` = linear pool, the bible model; `true` = the NS softmax path, kept for the capstone). Linear is valid precisely because we're in the Tier-1-only regime where `score == a non-negative weight`; the softmax path returns when the score terms can go signed. This realigns the code to canon and fixes specialization + the soul pivot in one flag.
`DECISION: BIBLE (linear now) + NS softmax deferred to Tier 2/3 capstone. RESOLVED.`

### The three-tier build roadmap (2026-07-25) — how the NS actually gets built
**The reframe that unblocked this:** the NS is not a formula to implement; it is three tiers to enrich, and crude versions of all three already exist. The softmax is the *capstone* that ties them together once each is worth combining — you build it last, not first. Earlier attempts stalled because we started at the 9-term formula (which needs modes/motifs/environment/history all at once) instead of the tiers.

| Tier | NS term | Plain meaning | What exists today |
|---|---|---|---|
| 1 | Verbs | *what* a dot does | ✅ move/attack/gather/build/defend… selected each tick |
| 2 | Modes | *how / in what style* | 🟡 the **dials** (range/intensity/frequency/affinity) are the raw material for named modes |
| 3 | Motifs | *the lasting anchor* the culture orients around | 🟡 **monuments + walls** are physical proto-motifs, not yet "remembered" or fed back |

**Staged path (each step small, shippable, understandable on its own):**
1. **Finish solid Tier 1 ground — linear selection.** ← *this step, shipping now.* A dot does one clear thing; specialists specialize; behaviour becomes legible; soul pivot works. The floor everything stands on.
2. **Give Tier 2 a name.** A "mode" = a named bundle of dial settings + a verb lean (e.g. "fierce" = high intensity, low range, attack-leaning). Wrap a memorable name around a dial pattern. Start with ONE mode, watch it, add more.
3. **Let Tier 3 remember.** A monument already exists physically; the step is letting it feed back into behaviour (a colony that built a great monument keeps valuing building near it). One motif, one feedback loop.
4. **Capstone — the NS softmax returns.** With verbs + a few modes + a motif all live, "which recipe fires" becomes a real question over `action+mode+motif`, and the softmax (flip `SELECTION_SOFTMAX = true`, activate the score terms) earns its place — read as obvious, not abstract, because each piece was watched first.

**Discipline:** never build the capstone directly. Build the three understandable things; the confusing part becomes the easy last step.

---

# TIER 3 — Motifs (persistent structures)

**Status: partially built — monuments (build system) and wall lines (waller system) already exist.**

### T3.a — monuments & wall lines follow the Tier 2 call
**Code:** monuments (build banners → block clusters, height caps, shedding) and wall lines (waller segments) are the Tier 3 structures. They work. **Bible:** the equivalents ("Moon Spiral Monument", wall-as-Quiet-Fortress) are meant to be emergent Tier-2/3 consequences, not orchestrated.
**Assessment:** same fork as T2.a — these structures are produced by the bespoke banner machinery. Whichever way T2.a is decided applies here for consistency. Near-term they're harmless and working; the only guidance is *don't invest more in banner-orchestration* until T2.a is called.
**Rec: MIX / follow T2.a. Cost: — (leave) / M (re-derive emergent).**
`DECISION: ______`

---

# SUBSTRATE (cross-tier foundations)

### S.a — dilution & CCE blending (bible core; disabled/unbuilt) ⚠️ identity
**Bible:** generational dilution (0.7) is *"the most important tuning variable"* — silence → drift → cultural death. CCE blending (passive contamination by proximity) is a central theme. **Code:** dilution is **disabled** (`full_inheritance = true`, testing posture); blending is **unbuilt**.
**Assessment:** these two *are* the bible's thematic heart, and the game currently runs with neither. Re-enabling dilution is a near-instant flag flip that transforms how the sim feels; blending is medium work.
**Rec: BIBLE — re-enable dilution once Tier 1 vocabulary is reachable enough for drift to be visible; build blending after. Cost: S (dilution) / M (blending).**
`DECISION: ______`

### S.b — the server / LLM / multiplayer spine (bible identity; unbuilt) ⚠️ launch milestone
**Bible:** persistent MP, ~10k colonies, chants interpreted server-side by an LLM (Ollama), DB persistence, active/passive ticks, `/chant` `/sync` `/session`. **Code:** local-only prototype; `USE_SERVER = false`, "server not implemented"; chants from a local dictionary; no LLM/DB/MP/passive ticks.
**Assessment:** the largest gap and the game's identity, but also the biggest lift. No reason to build it before the sim itself is worth persisting.
**Rec: BIBLE (canon) + DEFER (sequencing). Cheap alignment now: shape the local recipe path (T1.c) to the `/chant` response contract so flipping `USE_SERVER` later is a one-line change. Cost: L (full spine) / S (contract alignment now).**
`DECISION: ______` *(contract-alignment half is done — see T1.c)*

### S.c — soul: the resource economy and chant potency ⚠️ FIRST CANON CALL MADE

**The bible does not have a resource system.** §16 asks it as an open question — *"Resource system — does `gather` have a target? What do resources enable?"* — but the code answered it long ago and half-built it. That answer was never written back into the doc, so the bible understates what exists.

**What the code already had (DEVNOTES ~line 935, "New resource subsystem decided: soul"):**
- **Soul** is a colony-level scalar resource; **specks** are its physical form, spawning at random surface cells (`SPECK_SPAWN_CHANCE = 0.5`).
- Two deliberately asymmetric collection paths: **wander = incidental** (any dot ending its tick on a speck cell collects), **gather = directed** (`OBSERVE_MOVE_MAP = {"speck": "gather"}` — `gather`'s CCE weight is not a primitive that fires, it is the *claim ticket* that lets a speck sighting hijack a `move` roll). Luck versus intent: that contrast is the whole reason `gather` exists.
- **Designed but never built:** build consuming soul; combat plundering pool-to-pool on kills; a TBD `exchange` verb equalizing pools between aligned colonies; monuments passively generating soul.
- **Until 2026-07-24 nothing consumed soul at all** — the pool was credited, shown in the HUD, logged, and never spent. A source and a sink with no drain.

**The call (Dustan, 2026-07-24): soul weights the effect of a chant on CCE, and the chant consumes it.**

```
mult = 1.0 + SOUL_CHANT_GAIN * (soul / (soul + SOUL_CHANT_HALF))   # saturating, floor 1.0
delta_applied = base_delta * mult                                   # primitives AND dials
soul -= soul * SOUL_CHANT_DRAW                                      # drawn after applying
```
Shipped values (all placeholders): gain 4.0, half 100, draw 0.25 → 0 soul = 1.0×, 100 = 3.0×, asymptote 5.0×. Applied **client-side** so `/chant` keeps returning a raw recipe and the `USE_SERVER` flip stays one line.

**Why this is the right shape:**
- **It satisfies §4 without a spend control.** The player's only input is the chant, so soul had to be consumed by the simulation, never allocated by the player. Consumption rides the chant itself — no toggle, no budget UI.
- **It makes §13 structural instead of hard-coded.** The bible asserts aggression must be an evolutionary dead end but only proposes a *penalty* ("aggressive dots have lower reproduction probability"). Under S.c an all-attack colony never gathers → its soul dries up → its chants lose bite → it becomes **culturally rigid and cannot pivot when conditions change**. Aggression dies of inflexibility rather than of a designer's thumb. This is the strongest argument for the mechanic and should lead the v0.5 write-up.
- **It rewards long play and passive play** (§11.3) without rewarding combat, and it gives `gather` a strategic reason to exist beyond flavour.
- **Spent, not standing** — deliberately. A standing multiplier would make soul permanent stratification (a year-old colony out-chanting a new one forever, across 10,000 concurrent colonies) *and* would leave soul with no sink. Consumption self-balances and turns hoarding into a real choice: spend the reserve now, or keep it for what comes next.

**⚠️ Divergence to record in v0.5:** §5.4 says *"A single chant is a whisper. Repeated chanting is cultural formation."* A 4× multiplier makes one chant from an established colony a **shout**. That is intended — fast pivoting is the design goal — but it is a genuine departure from the doc's slow-accumulation thesis and must be stated, not slipped in. Defensible on the game's own terms: a culture with deep accumulated meaning absorbs new ideas faster.

**Open, unresolved:**
- **The `[0,1]` clamp saturates high-soul colonies in ~3 chants**, after which further chanting is a no-op. Either raise the clamp or make the multiplier scale *movement toward* 1.0 rather than adding a flat delta. **Most likely thing to bite in tuning.**
- All three constants are first-pass guesses.
- **Throttled by T2.c** — see the softmax-compression finding; the pivot speed S.c promises is capped by the selection curve's flatness, not by the multiplier.
- **Untestable as designed today:** `_apply_recipe` skips every non-`LOCAL_COLONY` dot and there is no chant path for colony 1, so the two-population comparison that motivated the design cannot be run without dev scaffolding.
- This resolves the per-colony vs. per-dot soul fork **in favour of per-colony** (`_apply_recipe` is already colony-wide). Per-dot soul options — death-bed CCE transfer, blending resistance, per-dot lifetime extension — get harder if this stays the primary consumer.
- The other designed consumers (build cost, combat plunder, `exchange`) remain unbuilt and now compete with S.c for the same pool.

`DECISION: CODE — soul + speck economy and soul-weighted chant potency are canon; write both into bible v0.5 (new "Resources and Soul" section) and strike the §16 resource question. Cost: shipped (S) + M (bible v0.5 section).`

---

## Bible's own open questions (§16) — still unresolved in the doc

Carry these into the roadmap: CCE-blending proximity radius & rate · ~~resource system (does `gather` have a target?)~~ **— answered in code, see S.c; strike from v0.5** · visual feedback for CCE drift · win condition vs. pure sandbox · colony colour/identity · new-player starting buffer (**sharpened by S.c** — a soul multiplier widens the gap a newcomer must close) · affinity-dial implementation (see T1.d).

---

## The roadmap that falls out (assuming BIBLE-leaning + emergence)

1. ~~**Recipes for the new Tier 1 verbs** (T1.c) + `gather` alias (T1.a)~~ — ✅ **done 2026-07-24** (gather needed nothing; that row was wrong). Awaiting playtest verification via telemetry.
1b. **Tune S.c** — playtest the soul multiplier, then decide the clamp-saturation fix and whether `SELECTION_TEMPERATURE` drops below 1.0 (T2.c finding). The immediate next work.
2. **Re-enable dilution** (S.a) — S, near-instant identity restoration. *(Parked by Dustan — not a priority.)*
3. **Build the `affinity` dial** (+ frequency) (T1.d) — M. Unlocks expressive Tier 1 behavior (directional bias, target choice, mark colour).
4. **Retune banner gating** to the heavily-spec'd bar (T2.b), using wall's Shape-D as template — M.
5. **Decide T2.a** (mode architecture) and write the bible v0.5 "cultural crystallization / two-tier emergence" section; formalize `observe` (T1.b) and the NS-stub disposition (T2.c) in the same pass.
6. **CCE blending** (S.a) — M, the second half of the thematic core.
7. **Local chant → `/chant` contract alignment** (S.b) — S.
8. **The spine** (server + LLM + DB + MP) (S.b) — L, the launch milestone.
9. Fold in the bible's §16 open questions as design mini-passes along the way.

---

## Decision log

| Ref | Divergence | Call | Notes |
|-----|-----------|------|-------|
| T1.a | `gather` reachability | **n/a — no gap** | row was wrong; `build` is the unreachable verb |
| T1.b | `observe` (code, not bible) | | |
| T1.c | recipes for new verbs | **BIBLE — shipped** | 2026-07-24; multi-word parsing still missing |
| T1.d | dials (affinity/frequency/spiral) | | |
| T2.a | mode architecture (banners vs emergence) | | **the big one** |
| T2.b | banner gating too shallow | | |
| T2.c | selection model (NS softmax vs bible linear) | **BIBLE (linear now)** | RESOLVED 2026-07-25; `SELECTION_SOFTMAX` flag, softmax deferred to Tier 2/3 capstone; three-tier roadmap added |
| T3.a | monuments & wall lines | | follows T2.a |
| S.a | dilution + blending | | identity; parked by Dustan |
| S.b | server / LLM / MP spine | | launch milestone; contract alignment done |
| S.c | soul economy + chant potency | **CODE** | 2026-07-24, **first call made**; shipped, needs tuning |
