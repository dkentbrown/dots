extends Node3D

const SPHERE_RADIUS = 1.0
const ZOOM_MIN = 1.12
const ZOOM_MAX = 6.0
const ZOOM_SPEED = 0.08
const PINCH_SPEED = 0.004
const ZOOM_SMOOTH = 8.0
const ROTATE_SPEED = 0.005

const TICK_SPEED = 1.0
var tick_timer = 0.0

const USE_SERVER = false
const DOT_LIFETIME = 100
# Children inherit this fraction of parent CCE at birth (between generations only,
# never applied within a dot's lifetime). Currently inert: _spawn_dot_near passes
# full_inheritance=true (testing posture, DEVNOTES 2026-05-12 "flip when ready").
const CCE_DILUTION = 0.7
const CHANT_WEIGHT = 0.08
const CHANT_FILE = "res://chant.json"

# Combat
const COMBAT_TICKS = 3
const COMBAT_INTENSITY_THRESHOLD = 0.7  # above this intensity, combat resolves one tick faster
var combat_clusters = []  # [{"pairs": [{"attacker": dot, "defender": dot}], "ticks_remaining": int}]
var combat_locked = {}    # dot -> true, skips primitive roll while in combat
# Per-exact-cell combat lock, COUNT-based (not boolean): cell (Vector2i) -> int of live
# block-defender fights targeting that cell. Two fights can hit one stack cell in one tick,
# so a boolean released on the first resolve would reopen the build race while the second is
# still live. Incremented once per new block-defender cluster (_initiate_combat), decremented
# once per cluster teardown (_release_cell_lock). Builds skip a cell while its count > 0.
var combat_locked_cells = {}  # Vector2i -> int
var cluster_by_defender = {}  # defender dot -> cluster reference (O(1) lookup)

# Waller (Shape D) — stage (a) diagnostic
# Shape D success probability = (this dot's defend weight) * (colony avg build CCE) * SHAPE_D_SCALE.
# The "colony avg build CCE" factor is the same value monument cap-sizing reads
# (_compute_colony_avg_build_cce, action key "build"). PLACEHOLDER value — an initial guess only,
# meant to be tuned from this stage's own "shape_d_roll" telemetry, NOT a final number.
const SHAPE_D_SCALE = 2.0

# Spatial grid
const GRID_RES = 200
const CELL_STEP = TAU / float(GRID_RES)  # one grid cell width in radians
var spatial_grid = {}  # cell_key (Vector2i) -> array of dots
var dot_cell = {}      # dot -> current cell_key, for incremental grid updates

# Rally banners (dropped on combat contact, friendly-only pull)
const RALLY_RADIUS = 30  # cells; how far a banner pulls reinforcements
const BANNER_TTL = 6     # ticks a banner persists after contact
var rally_banners = []  # [{cell: Vector2i, colony: int, ticks_remaining: int}]

# Wall banners (stage (b): dropped on Shape D success; consumed by stages (d)/(e) below)
const WALL_BANNER_RADIUS = 15  # cells; how far a wall banner pulls build-inclined dots to extend the fence
const WALL_BANNER_TTL = 6      # ticks a wall banner persists; pure-TTL expiry
const WALL_MAX_HALF_LENGTH = 4  # stage (e): max cells the fence extends on each side of the banner seed (line length <= 2*this + 1)
var wall_banners = []  # [{cell: Vector2i, colony: int, ticks_remaining: int, threat_dir: Vector3}]
# Stage (d) waller perch: waller_dot -> wall_block it is perched on. A perched dot skips all
# rolls until its block dies (combat or decay), then drops back to the surface. The block
# carries the inverse ref in dot_data as "perched_by".
var wall_perch = {}

# Per-colony population cap (testing aid)
const MAX_POPULATION_PER_COLONY = 1000
var colony_counts = {}  # colony_id -> current dot count

# Blocks (separate from population)
const BLOCK_DEFEND_VALUE = 0.5
const BLOCK_DECAY_TICKS = 300
const BLOCK_MESH_SIZE = Vector3(0.031, 0.003, 0.031)  # match cell spacing so adjacent cells tile cleanly (TAU/GRID_RES \u2248 0.0314 at the equator)
const BLOCK_HEIGHT_STEP = 0.003  # vertical spacing between stacked blocks (== mesh y-size)
const WALL_MESH_SIZE = Vector3(0.031, 0.003, 0.0155)  # stage (c): half-thickness vs BLOCK_MESH_SIZE; long axis (x, perpendicular to threat) kept at full cell spacing to tile with future wall-line segments (stage e)
const WALL_COLOR = Color(0.0, 0.95, 0.8)  # bright teal — distinguishes fence segments from the pale defend-blue of monument blocks; not a CCE hue, so no semantic clash
var block_counts = {}  # colony_id -> current block count
var soul_pool = {}   # colony_id -> accumulated soul units

# Build banners (anchored at a placed block, attracting nearby builders)
const BUILD_BANNER_RADIUS = 15
const BUILD_BANNER_TTL = 6
const BUILD_START_CHANCE = 0.05  # chance a build roll starts a new monument when no banner is in range
const BUILD_AT_BANNER_STACK_PREF = 0.8  # base prob. of stacking when building at a banner (at height 0)
const STACK_HEIGHT_SOFTCAP = 10  # height at which the stack/self factor bottoms out (strongly discouraged, not zero)
const STACK_HEIGHT_FACTOR_FLOOR = 0.05  # floor under the height factor, so building past the softcap is rare not impossible
const SHED_CONTAINMENT_DIST_SQ = 5  # sq torus-cell dist from the banner a shed target must stay within (rounded, tighter than the 8 footprint)
const SHED_ESCAPE_CHANCE = 0.15  # per-shed chance to skip containment and draw from the full 8-ring, fraying the monument edge
const BUILD_FOOTPRINT_DIST_SQ = 8  # squared torus-cell dist within which a builder counts as at/adjacent to a banner
# Monument size cap. cap = BUILD_MONUMENT_BASE + BUILD_MONUMENT_SCALE * colony_avg_build_cce.
# Snapshotted at founder placement and stored on the banner. Independent of population \u2014
# big colonies just hit the cap faster, small ones may never reach it (banner times out).
const BUILD_MONUMENT_BASE = 10.0
const BUILD_MONUMENT_SCALE = 200.0
var build_banners = []  # [{id, cell, colony, ticks_remaining, block_cap, block_count}]
var _next_build_banner_id = 1

# Test mode \u2014 fixed population (suppresses reproduction, seeds 15 dots)
const TEST_MODE = false
const TEST_POPULATION = 15
# Logging \u2014 independent of TEST_MODE so we can log organic runs too
const LOG_ENABLED = true
const LOG_FILE = "res://build_log.txt"
# Telemetry — persistent JSONL dev instrumentation, separate gate from LOG_ENABLED.
# NOT truncated at launch (runs accumulate; a run_start record segments them).
const TELEMETRY_ENABLED = true
const TELEMETRY_FILE = "res://telemetry.jsonl"
const TELEMETRY_SNAPSHOT_INTERVAL = 1   # snapshot every N ticks; 1 = every tick
var _next_dot_id = 1
var _tick_num = 0

# Tuning constants (formerly magic numbers)
const SPAWN_NUDGE = 0.018
const DEFEND_STEP = 0.01
const DOT_SURFACE_OFFSET = 0.0075
const PARALLEL_EPSILON = 0.0001
const MAX_CCE_FOR_SATURATION = 1.5
const SPECK_SPAWN_CHANCE = 0.5         # per-tick probability a speck spawns
const REPRODUCE_CHANCE_MIN = 0.1       # reproduce probability at intensity 0
const REPRODUCE_CHANCE_MAX = 0.9       # reproduce probability at intensity 1
const MOVE_NUDGE_MIN = 0.01            # undirected-drift nudge at range_val 0
const MOVE_NUDGE_MAX = 0.08            # undirected-drift nudge at range_val 1

const OBSERVE_BASE_RADIUS := 3
const OBSERVE_SCALE := 20

# pending_observe key -> cce.action verb that consumes it via directed move.
# One pair today (speck -> gather, the first composite recipe); add a line to extend.
const OBSERVE_MOVE_MAP = { "speck": "gather" }

const NEUTRAL_CCE = {
	"motion": {
		"move": 0.0,
		# "face_target": reserved \u2014 not yet wired
	},
	"action": {
		# Reserved primitives \u2014 not yet wired, kept for forward compatibility
		"mark_surface": 0.0,
		"build": 0.0,
		"gather": 0.0,
		# Active primitives
		"defend": 0.0,
		"attack": 0.0,
		"reproduce": 0.0,
		"observe": 0.0
	},
	"dials": {
		"range": 0.5,
		"intensity": 0.5,
		# "frequency", "affinity": reserved \u2014 not yet read by any primitive
		"spiral": 0.0
	}
}

const CCE_COLORS = {
	"move": Color(1.0, 0.75, 0.1),
	"reproduce": Color(0.3, 0.9, 0.3),
	"defend": Color(0.2, 0.5, 1.0),
	"attack": Color(1.0, 0.2, 0.2),
	"build": Color(0.6, 0.6, 0.7),
	"observe": Color(0.7, 0.3, 0.9),
}
const CCE_NEUTRAL_COLOR = Color(1.0, 1.0, 1.0)

# Active chant aliases. Dead primitives (gather/build/mark) intentionally absent
# until their execution paths exist.
const CHANT_RECIPES = {
	"wander":    { "motion": { "move": CHANT_WEIGHT }, "dials": { "range": 0.05 } },
	"explore":   { "motion": { "move": CHANT_WEIGHT }, "dials": { "range": 0.05 } },
	"roam":      { "motion": { "move": CHANT_WEIGHT }, "dials": { "range": 0.05 } },
	"spiral":    { "dials": { "spiral": 0.1 } },
	"reproduce": { "action": { "reproduce": CHANT_WEIGHT } },
	"multiply":  { "action": { "reproduce": CHANT_WEIGHT } },
	"sex":       { "action": { "reproduce": CHANT_WEIGHT } },
	"breed":     { "action": { "reproduce": CHANT_WEIGHT } },
	"attack":    { "action": { "attack": CHANT_WEIGHT }, "dials": { "intensity": 0.05 } },
	"fight":     { "action": { "attack": CHANT_WEIGHT }, "dials": { "intensity": 0.05 } },
	"war":       { "action": { "attack": CHANT_WEIGHT }, "dials": { "intensity": 0.05 } },
	"defend":    { "action": { "defend": CHANT_WEIGHT } },
	"protect":   { "action": { "defend": CHANT_WEIGHT } },
	"guard":     { "action": { "defend": CHANT_WEIGHT } },
	"observe":   { "action": { "observe": CHANT_WEIGHT } },
	"watch":     { "action": { "observe": CHANT_WEIGHT } },
	"see":       { "action": { "observe": CHANT_WEIGHT } },
	"gather":    { "action": { "gather": CHANT_WEIGHT, "observe": CHANT_WEIGHT } },
	"collect":   { "action": { "gather": CHANT_WEIGHT, "observe": CHANT_WEIGHT } },
	"forage":    { "action": { "gather": CHANT_WEIGHT, "observe": CHANT_WEIGHT } },
	"harvest":   { "action": { "gather": CHANT_WEIGHT, "observe": CHANT_WEIGHT } },
	"far":       { "dials": { "range": 0.1 } },
	"farther":   { "dials": { "range": 0.1 } },
	"distant":   { "dials": { "range": 0.1 } },
	"close":     { "dials": { "range": -0.1 } },
	"near":      { "dials": { "range": -0.1 } },
	"tight":     { "dials": { "range": -0.1 } },
	"fierce":    { "dials": { "intensity": 0.1 } },
	"sharp":     { "dials": { "intensity": 0.1 } },
	"strong":    { "dials": { "intensity": 0.1 } },
	"gentle":    { "dials": { "intensity": -0.1 } },
	"soft":      { "dials": { "intensity": -0.1 } },
	"slow":      { "dials": { "intensity": -0.1 } }
}

var dots = []
var dot_data = {}
var specks = []
# Live-dot record (see _create_dot):
# dot_data[dot] = {
#   "age": int,                 # ticks lived, dies at DOT_LIFETIME
#   "cce": { "motion": {...}, "action": {...}, "dials": {...} },
#   "colony": int,              # colony ID
#   "build_banners_used": {},   # dormant: never written (see _find_eligible_build_banner)
#   "dot_id": int,              # stable id for logging
#   "pending_observe": null,    # set by _execute_observe; consumed by move via OBSERVE_MOVE_MAP
#   "collect_lock": null,       # set on speck-cell collision; resolved in _tick_all_dots
# }
# Block-record variant (see _create_block): "age", "cce", "colony", plus
#   "is_block": true, "decay_ticks_remaining": int, "stack_index": int. Its cce is a
#   NEUTRAL copy with action.defend = BLOCK_DEFEND_VALUE. Blocks carry none of
#   dot_id / pending_observe / collect_lock / build_banners_used.

var player_dot = null
const LOCAL_COLONY = 0
const ENEMY_COLONY = 1

var revealed_colonies = {LOCAL_COLONY: true}
var known_colonies = {LOCAL_COLONY: true}  # tracks all spawned colony IDs for fog early-exit
const FOG_COLOR = Color(0.25, 0.25, 0.25)
const FOG_EMISSION = Color(0.1, 0.1, 0.1)

const COLONY1_CCE = {
	"motion": {
		"move": 0.40,
	},
	"action": {
		"mark_surface": 0.0,
		"build": 0.0,
		"gather": 0.0,
		"defend": 0.10,  # verification tuning pass for Shape D diagnostic — not a final balance decision
		"attack": 0.40,
		"reproduce": 0.32,
		"observe": 0.1
	},
	"dials": {
		"range": 0.5,
		"intensity": 0.5,
		"spiral": 0.0
	}
}

const COLONY0_CCE = {
	"motion": {
		"move": 0.40,
	},
	"action": {
		"mark_surface": 0.0,
		"build": 0.40,
		"gather": 0.0,
		"defend": 0.10,  # verification tuning pass for Shape D diagnostic — not a final balance decision
		"attack": 0.0,
		"reproduce": 0.40,
		"observe": 0.1
	},
	"dials": {
		"range": 0.5,
		"intensity": 0.5,
		"spiral": 0.0
	}
}

@onready var camera = $Camera3D
@onready var chant_button = $UI/ChantButton
@onready var chant_modal = $UI/ChantModal
@onready var chant_input = $UI/ChantModal/VBox/ChantInput
@onready var confirm_button = $UI/ChantModal/VBox/ButtonRow/ConfirmButton
@onready var cancel_button = $UI/ChantModal/VBox/ButtonRow/CancelButton
@onready var dev_bar = $UI/DevBar
@onready var hud = $UI/HUD
@onready var zoom_slider = $UI/ZoomSlider

var zoom_target = 3.0
var zoom_distance = 3.0
var orbit_yaw = 0.0
var orbit_pitch = 0.0
var is_orbiting = false
var touch_positions = {}
var pinch_last_distance = 0.0
var single_touch_active = false
var single_touch_index = -1

# Cached per-tick colony center (colony 0 only)
var _cached_colony_center = Vector3.ZERO

func _ready():
	if LOG_ENABLED:
		# Wipe log at session start
		var f = FileAccess.open(LOG_FILE, FileAccess.WRITE)
		if f:
			f.store_string("")
			f.close()
	# Telemetry is persistent (not wiped); a run_start record segments accumulated runs.
	_telemetry({ "type": "run_start", "run_id": int(Time.get_unix_time_from_system()), "grid_res": GRID_RES })
	_spawn_player_dot()
	if TEST_MODE:
		_spawn_test_population()
	_spawn_enemy_colony()
	_update_camera()
	_update_hud()
	chant_button.pressed.connect(_open_chant)
	confirm_button.pressed.connect(_confirm_chant)
	cancel_button.pressed.connect(_close_chant)
	chant_input.text_submitted.connect(_on_chant_submitted)
	dev_bar.placeholder_text = "dev chant..."
	dev_bar.text_submitted.connect(_on_dev_chant)
	zoom_slider.value = zoom_target
	zoom_slider.value_changed.connect(_on_zoom_slider_changed)

func _open_chant():
	chant_modal.visible = true
	chant_input.clear()
	chant_input.grab_focus()

func _close_chant():
	chant_modal.visible = false
	chant_input.clear()

func _confirm_chant():
	_process_input(chant_input.text)
	_close_chant()

func _on_chant_submitted(text: String):
	_process_input(text)
	_close_chant()

func _on_dev_chant(text: String):
	_process_input(text)
	dev_bar.clear()

func _process(delta):
	zoom_distance = lerp(zoom_distance, zoom_target, ZOOM_SMOOTH * delta)
	zoom_distance = max(zoom_distance, ZOOM_MIN)
	_update_camera()
	tick_timer += delta
	if tick_timer >= TICK_SPEED:
		tick_timer = 0.0
		_tick_num += 1
		# Tick order is load-bearing:
		#  - _age_dots before _compute_colony_center: dead dots are excluded from the center.
		#  - _tick_combat_clusters before _tick_all_dots: combat resolves and sets
		#    combat_locked before dots roll, so locked dots skip their primitive this tick.
		#  - _tick_specks before _tick_all_dots: specks spawned this tick are collidable
		#    in the same tick (same-tick collectability).
		_check_chant_file()
		_age_dots()
		# Spatial grid is now incrementally maintained \u2014 no rebuild needed
		_cached_colony_center = _compute_colony_center(LOCAL_COLONY)
		_check_fog_of_war()
		_tick_rally_banners()
		_tick_build_banners()
		_tick_wall_banners()
		_tick_combat_clusters()
		_tick_specks()
		_tick_all_dots()
		_update_hud()
		# Post-tick state snapshot (after all mutations resolve). Captures ALL colonies.
		if _tick_num % TELEMETRY_SNAPSHOT_INTERVAL == 0:
			_telemetry({
				"type": "snapshot",
				"tick": _tick_num,
				"pop": colony_counts.duplicate(),
				"soul": soul_pool.duplicate(),
				"blocks": block_counts.duplicate(),
				"combat_active": combat_clusters.size(),
				"combat_locked": combat_locked.size(),
				"revealed": revealed_colonies.keys(),
				"specks": specks.size()
			})

# --- Chant file ---

func _check_chant_file():
	if not FileAccess.file_exists(CHANT_FILE):
		return
	var file = FileAccess.open(CHANT_FILE, FileAccess.READ)
	if file == null:
		return
	var content = file.get_as_text().strip_edges()
	file.close()
	if content == "" or content == "{}":
		return
	var json = JSON.new()
	var err = json.parse(content)
	if err != OK:
		print("chant.json parse error")
		return
	var recipe = json.get_data()
	_apply_recipe(recipe)
	var clear = FileAccess.open(CHANT_FILE, FileAccess.WRITE)
	if clear:
		clear.store_string("{}")
		clear.close()

func _apply_recipe(recipe: Dictionary):
	print("Applying recipe: ", recipe)
	for dot in dots:
		if dot_data[dot]["colony"] != LOCAL_COLONY:
			continue
		var cce = dot_data[dot]["cce"]
		if recipe.has("motion"):
			for key in recipe["motion"]:
				if cce["motion"].has(key):
					cce["motion"][key] = clamp(cce["motion"][key] + recipe["motion"][key], 0.0, 1.0)
		if recipe.has("action"):
			for key in recipe["action"]:
				if cce["action"].has(key):
					cce["action"][key] = clamp(cce["action"][key] + recipe["action"][key], 0.0, 1.0)
		if recipe.has("dials"):
			for key in recipe["dials"]:
				if cce["dials"].has(key):
					cce["dials"][key] = clamp(cce["dials"][key] + recipe["dials"][key], 0.0, 1.0)
		_update_dot_color(dot)
	_update_hud()

func _update_hud():
	if dots.is_empty():
		hud.text = "dots: 0"
		return
	var totals = {}
	var count = 0
	for dot in dots:
		if dot_data[dot]["colony"] != LOCAL_COLONY:
			continue
		if dot_data[dot].get("is_block", false):
			continue
		count += 1
		var cce = dot_data[dot]["cce"]
		for key in cce["motion"]:
			totals[key] = totals.get(key, 0.0) + cce["motion"][key]
		for key in cce["action"]:
			totals[key] = totals.get(key, 0.0) + cce["action"][key]
	if count == 0:
		hud.text = "p0: 0 (wiped out)"
		return
	var sorted_keys = totals.keys()
	sorted_keys.sort_custom(func(a, b): return totals[a] > totals[b])
	var p1_count = colony_counts.get(ENEMY_COLONY, 0)
	var p0_blocks = block_counts.get(LOCAL_COLONY, 0)
	var p0_soul = soul_pool.get(LOCAL_COLONY, 0)
	var lines = ["p0: %d (blocks: %d, soul: %d)   p1: %d" % [count, p0_blocks, p0_soul, p1_count]]
	var shown = 0
	for key in sorted_keys:
		var avg = totals[key] / count
		if avg > 0.001:
			lines.append("%s  %.2f" % [key, avg])
			shown += 1
			if shown >= 3:
				break
	hud.text = "\n".join(lines)

# --- Chant input ---

func _process_input(text: String):
	if USE_SERVER:
		push_warning("USE_SERVER enabled but server is not implemented")
		_send_chant_to_server(text)
	else:
		_process_chant_locally(text)

func _send_chant_to_server(_text: String):
	pass

func _process_chant_locally(text: String):
	var lower = text.to_lower().strip_edges()
	if not CHANT_RECIPES.has(lower):
		print("No local recipe for: ", text)
		return
	_apply_recipe(CHANT_RECIPES[lower])

# --- Per-dot CCE tick ---

func _tick_all_dots():
	# Load-bearing: reproduce appends newborns to `dots` mid-iteration, and those newborns
	# are intended to tick in this same pass. Dot removal never happens inside this loop
	# (deaths are collected by _age_dots / combat resolution), so append-during-for-in is
	# safe here, not a hazard.
	for dot in dots:
		if combat_locked.has(dot):
			continue
		# Stage (d): a perched waller is frozen on its wall segment — no primitive rolls,
		# not even observe — until the segment dies and _remove_dot releases it.
		if wall_perch.has(dot):
			continue
		if dot_data[dot].get("is_block", false):
			continue
		var lock = dot_data[dot].get("collect_lock", null)
		if lock != null:
			if lock["until_tick"] <= _tick_num:
				if lock["until_tick"] == _tick_num:
					# On-time resolution: pay out.
					if lock["speck"] in specks:
						lock["speck"].queue_free()
						specks.erase(lock["speck"])
					# The soul credit sits OUTSIDE the speck-in-specks check on purpose.
					# "The lock is the receipt": every resolved lock credits the pool whether
					# or not the speck node survived, so simultaneous arrivers each credit.
					var collector_colony = dot_data[dot]["colony"]
					soul_pool[collector_colony] = soul_pool.get(collector_colony, 0) + 1
				# F1 late clear: the resolution tick was missed (combat preempted it), so
				# until_tick < _tick_num now. Clear the lock without payout — no speck freed,
				# no soul credited — so the dot resumes normal ticking instead of stalling.
				if lock["until_tick"] < _tick_num:
					_telemetry({ "type": "f1_fired", "tick": _tick_num, "colony": dot_data[dot]["colony"], "until_tick": lock["until_tick"], "dot_id": dot_data[dot].get("dot_id", -1) })
				dot_data[dot]["collect_lock"] = null
			continue
		_tick_dot(dot)

func _tick_dot(dot: Node3D):
	var cce = dot_data[dot]["cce"]
	var pool = {}
	for key in cce["motion"]:
		if cce["motion"][key] > 0.0:
			pool[key] = cce["motion"][key]
	for key in cce["action"]:
		if cce["action"][key] > 0.0:
			pool[key] = cce["action"][key]
	if pool.is_empty():
		return
	# North Star selection: P(r) = softmax(A + M + T + S_am + S_at + S_mt + C + E + H).
	# Only A is live (binds to the current CCE weight, chant already folded in via
	# _apply_recipe). The other eight terms are present-but-zero so each can be filled
	# in later as a one-line change.
	var weights = {}  # key -> exp(score)
	var total = 0.0
	for key in pool:
		var A = pool[key]   # action tendency (current CCE weight)
		var M = 0.0         # motif
		var T = 0.0         # target
		var S_am = 0.0      # synergy: action × motif
		var S_at = 0.0      # synergy: action × target
		var S_mt = 0.0      # synergy: motif × target
		var C = 0.0         # chant pressure (currently folded into A)
		var E = 0.0         # environment
		var H = 0.0         # history
		var score = A + M + T + S_am + S_at + S_mt + C + E + H
		var w = exp(score)
		weights[key] = w
		total += w
	var roll = randf() * total
	var chosen = ""
	var cumulative = 0.0
	for key in pool:
		cumulative += weights[key]
		if roll <= cumulative:
			chosen = key
			break
	if chosen == "":
		return
	if LOG_ENABLED and dot_data[dot]["colony"] == LOCAL_COLONY:
		var cell = _cell_key(dot.position.normalized())
		_log("[t%d] dot %d at (%d,%d) roll: %s" % [_tick_num, dot_data[dot]["dot_id"], cell.x, cell.y, chosen])
	_execute_primitive(dot, chosen, cce["dials"])
	var my_cell = _cell_key(dot.position.normalized())
	for speck in specks:
		if _cell_key(speck.position.normalized()) == my_cell:
			dot_data[dot]["collect_lock"] = { "until_tick": _tick_num + 1, "speck": speck }
			break

func _execute_primitive(dot: Node3D, primitive: String, dials: Dictionary):
	var range_val = dials.get("range", 0.5)
	var intensity = dials.get("intensity", 0.5)
	var spiral = dials.get("spiral", 0.0)

	match primitive:
		"move":
			# Consume a pending observation: if one matches a CCE verb (highest weight wins),
			# move becomes a directed step toward the observed position and is consumed.
			var pending = dot_data[dot]["pending_observe"]
			if pending != null:
				var best_key = ""
				var best_weight = 0.0
				for obs_key in OBSERVE_MOVE_MAP:
					if pending[obs_key] == null:
						continue
					var verb_weight = dot_data[dot]["cce"]["action"][OBSERVE_MOVE_MAP[obs_key]]
					if verb_weight > 0.0 and verb_weight > best_weight:
						best_weight = verb_weight
						best_key = obs_key
				if best_key != "":
					_march_toward_dir(dot, dot.position.normalized(), pending[best_key]["pos"], dot_data[dot]["colony"])
					dot_data[dot]["pending_observe"] = null
					return
			var nudge_amount = lerp(MOVE_NUDGE_MIN, MOVE_NUDGE_MAX, range_val)
			var dir = dot.position.normalized()
			var tangent: Vector3
			if spiral > 0.1:
				var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
				tangent = dir.cross(up).normalized()
				nudge_amount *= (1.0 + spiral)
			else:
				tangent = dir.cross(Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1))).normalized()
			var new_dir = (dir + tangent * nudge_amount).normalized()
			_place_dot_on_sphere(dot, new_dir, true)
		"reproduce":
			var chance = lerp(REPRODUCE_CHANCE_MIN, REPRODUCE_CHANCE_MAX, intensity)
			if randf() < chance:
				_spawn_dot_near(dot, dot_data[dot]["colony"])
		"attack":
			_execute_attack(dot, intensity)
		"defend":
			# On a normal defend roll with a live pending enemy observation, roll Shape D
			# (defend × colony-avg build × SHAPE_D_SCALE). On success the dot founds a wall
			# segment and perches (stages b–d) and returns early — skipping the colony-center
			# march. On failure (or no pending enemy) the colony-center march below runs as before.
			# Guard mirrors _execute_attack's shipped pattern exactly (Option A: read-only).
			var pending = dot_data[dot]["pending_observe"]
			var enemy_entry = pending["enemy"] if pending != null else null
			var target = enemy_entry["dot"] if enemy_entry != null else null
			if target != null and not dot_data.has(target):
				target = null
			if target != null:
				var d_colony = dot_data[dot]["colony"]
				var defend_weight = dot_data[dot]["cce"]["action"].get("defend", 0.0)
				var avg_build = _compute_colony_avg_build_cce(d_colony)
				var shape_d_prob = defend_weight * avg_build * SHAPE_D_SCALE
				var shape_d_success = randf() < shape_d_prob
				_telemetry({ "type": "shape_d_roll", "tick": _tick_num, "colony": d_colony, "prob": shape_d_prob, "success": shape_d_success })
				if shape_d_success:
					# Stage (b): a Shape D success drops (or refreshes) a wall banner (now carrying
					# the threat bearing) at the defender's current cell. Stage (c): builds an
					# oriented half-thickness wall block, long axis perpendicular to the threat.
					# Stage (d): the waller then perches on its own segment and locks. Stage (e)
					# extenders respond to the banner via _execute_build.
					var my_cell = _cell_key(dot.position.normalized())
					var threat_dir = target.position.normalized()
					_drop_wall_banner(my_cell, d_colony, threat_dir)
					# Only found a segment on a cell free of a prior same-colony block and not
					# mid-fight; otherwise leave the banner for extenders and march normally.
					if _count_blocks_in_cell(my_cell, d_colony) == 0 and combat_locked_cells.get(my_cell, 0) == 0:
						var seed_block = _create_wall_block(my_cell, d_colony, threat_dir, dot_data[dot]["dot_id"])
						_perch_waller(dot, seed_block)
						return  # perched + locked this tick: skip the colony-center march below
			var dir = dot.position.normalized()
			var toward = (_cached_colony_center - dir).normalized()
			var new_dir = (dir + toward * DEFEND_STEP).normalized()
			_place_dot_on_sphere(dot, new_dir, true)
		"build":
			_execute_build(dot)
		"observe":
			_execute_observe(dot)
		# mark_surface, face_target: reserved no-op (no executor here).
		# gather also has no match-case executor, but its CCE weight is NOT inert: it
		# gates directed move via OBSERVE_MOVE_MAP (speck -> gather).

func _execute_attack(dot: Node3D, intensity: float):
	var my_colony = dot_data[dot]["colony"]
	var my_dir = dot.position.normalized()
	# Observe-gated detection: read the enemy slot written by _execute_observe on a prior
	# tick instead of self-scanning. Option A clear-on-consume — attack never writes to
	# pending_observe; the slot is only ever refreshed by the dot's next observe roll.
	var pending = dot_data[dot]["pending_observe"]
	var enemy_entry = pending["enemy"] if pending != null else null
	var target = enemy_entry["dot"] if enemy_entry != null else null
	# Liveness guard (mandatory): a stored node reference can be stale — the target may have
	# been removed via _remove_dot since the observe roll. Treat a freed target as no target.
	if target != null and not dot_data.has(target):
		target = null
	if target == null:
		# No enemy in detect range \u2014 check for a friendly rally banner to march toward
		_march_toward_rally_banner(dot, my_dir, my_colony)
		return
	if combat_locked.has(dot) or combat_locked.has(target):
		return
	var foreign_nearby = _get_foreign_dots_near(my_dir, my_colony)
	if target in foreign_nearby:
		_initiate_combat(dot, target, intensity)
	else:
		_march_toward(dot, my_dir, target, my_colony)

func _initiate_combat(attacker: Node3D, defender: Node3D, intensity: float):
	combat_locked[attacker] = true
	combat_locked[defender] = true
	var ticks = COMBAT_TICKS - (1 if intensity > COMBAT_INTENSITY_THRESHOLD else 0)
	# O(1) lookup: does this defender already have a cluster?
	if cluster_by_defender.has(defender):
		var cluster = cluster_by_defender[defender]
		cluster["pairs"].append({"attacker": attacker, "defender": defender})
	else:
		var cluster = {"pairs": [{"attacker": attacker, "defender": defender}], "ticks_remaining": ticks}
		combat_clusters.append(cluster)
		cluster_by_defender[defender] = cluster
		# Count-based per-cell lock: a NEW block-defender fight locks the defender's exact cell.
		# Stored on the cluster so teardown (either path) decrements exactly once. Appended pairs
		# (same defender, more attackers) reuse this cluster and do NOT re-increment.
		if dot_data[defender].get("is_block", false):
			var locked_cell = dot_cell.get(defender)
			if locked_cell != null:
				cluster["locked_cell"] = locked_cell
				combat_locked_cells[locked_cell] = combat_locked_cells.get(locked_cell, 0) + 1
	# Drop rally banners for both sides at the contact cell
	var contact_cell = _cell_key(defender.position.normalized())
	_drop_rally_banner(contact_cell, dot_data[attacker]["colony"])
	_drop_rally_banner(contact_cell, dot_data[defender]["colony"])
	# Observation-age diagnostic: how stale was the attacker's enemy observation when combat
	# fired? Defensive read — sentinel -1 for "unknown" if the stamp is missing (impossible via
	# the current guarded call path, but _initiate_combat is standalone).
	var observe_age = -1
	var attacker_pending = dot_data[attacker]["pending_observe"]
	if attacker_pending != null and attacker_pending["enemy"] != null and attacker_pending["enemy"].has("observed_tick"):
		observe_age = _tick_num - attacker_pending["enemy"]["observed_tick"]
	_telemetry({ "type": "combat_init", "tick": _tick_num, "attacker_colony": dot_data[attacker]["colony"], "defender_colony": dot_data[defender]["colony"], "cell": [contact_cell.x, contact_cell.y], "intensity": intensity, "observe_age": observe_age })

func _march_toward(dot: Node3D, my_dir: Vector3, target: Node3D, my_colony: int):
	var target_dir = target.position.normalized()
	_march_toward_dir(dot, my_dir, target_dir, my_colony)

func _march_toward_dir(dot: Node3D, my_dir: Vector3, target_dir: Vector3, my_colony: int):
	var toward = target_dir - my_dir
	if toward.length_squared() < PARALLEL_EPSILON:
		return
	toward = toward.normalized()
	var tangent = my_dir.cross(toward)
	if tangent.length_squared() < PARALLEL_EPSILON:
		return
	tangent = tangent.cross(my_dir).normalized()
	var new_dir = (my_dir + tangent * CELL_STEP).normalized()
	if not _is_foreign_in_exact_cell(new_dir, my_colony):
		_place_dot_on_sphere(dot, new_dir)

# --- Build (blocks) ---

func _execute_build(dot: Node3D):
	var my_colony = dot_data[dot]["colony"]
	var my_dir = dot.position.normalized()
	var my_cell = _cell_key(my_dir)
	# Wall-banner priority (stages d/e): an active same-colony wall banner in range overrides
	# ordinary monument building entirely — an existential-threat response. A build-inclined
	# dot marches to the fence line and extends it, then perches and locks. This is
	# unconditional: while a wall banner is in range, no monument work happens on this roll.
	var wall_banner = _find_nearest_wall_banner(my_cell, my_colony)
	if wall_banner != null:
		_respond_to_wall_banner(dot, my_dir, my_cell, my_colony, wall_banner)
		return
	# Look for an active, unused build banner within range
	var nearest_banner = _find_eligible_build_banner(dot, my_cell, my_colony)
	if nearest_banner != null:
		var banner_cell = nearest_banner["cell"]
		if _is_at_or_adjacent(my_cell, banner_cell):
			# At the monument \u2014 stack pref decays with current tower height, floored at STACK_HEIGHT_FACTOR_FLOOR by STACK_HEIGHT_SOFTCAP
			var current_height = _count_blocks_in_cell(banner_cell, my_colony)
			var height_factor = clamp(1.0 - float(current_height) / float(STACK_HEIGHT_SOFTCAP), STACK_HEIGHT_FACTOR_FLOOR, 1.0)
			var stack_pref = BUILD_AT_BANNER_STACK_PREF * height_factor
			var stacking = randf() < stack_pref
			# Every build path gates on the height of the cell that RECEIVES the block. On a
			# stack the block lands on banner_cell (gated by the height roll above). An on-cell
			# builder (my_cell == banner_cell) must NOT collapse back onto banner_cell on a
			# non-stack roll -- that decorative roll was the unbounded-tower bug. Shed it to a
			# weighted-lowest ring neighbour so tall centres dome outward and each receiving
			# ring cell is height-discouraged by its own stack count. An off-cell builder
			# (my_cell != banner_cell) gates on my_cell's OWN same-colony height (same floored
			# factor as the banner's); on a failed roll it sheds to a weighted-lowest neighbour
			# of my_cell, contained near the banner or, with SHED_ESCAPE_CHANCE, escaping that
			# containment to fray the edge. There is no ungated self fallback: the shed target
			# is height-weighted in every case, and an empty contained ring skips the build.
			var build_cell
			var reason_str
			if stacking:
				build_cell = banner_cell
				reason_str = "stack"
			elif my_cell == banner_cell:
				build_cell = _pick_lateral_cell(banner_cell, my_colony)
				reason_str = "lateral"
			else:
				var my_height = _count_blocks_in_cell(my_cell, my_colony)
				var my_height_factor = clamp(1.0 - float(my_height) / float(STACK_HEIGHT_SOFTCAP), STACK_HEIGHT_FACTOR_FLOOR, 1.0)
				if randf() < my_height_factor:
					build_cell = my_cell
					reason_str = "self"
				else:
					# Shed to a weighted-lowest neighbour. Normally constrained to SHED_CONTAINMENT_DIST_SQ
					# of the banner (rounded base); with SHED_ESCAPE_CHANCE we drop that constraint and draw
					# from the full 8-ring, letting a block land past the participation radius to fray the
					# edge. The candidate set is pre-filtered, so the picked cell's height is always consulted
					# (weight = 1/(1+height)); there is no ungated my_cell fallback. If containment leaves no
					# candidate (degenerate geometry only), skip the build rather than place ungated.
					var contained = randf() >= SHED_ESCAPE_CHANCE
					var shed_cell = _pick_lateral_cell(my_cell, my_colony, banner_cell, contained)
					if shed_cell.x < 0:
						return
					build_cell = shed_cell
					reason_str = "shed"
			# Stack combat-lock: don't add a block to a cell with a live block-defender fight.
			# Skip this build tick (no-op) rather than racing the topmost-removal on that cell.
			if combat_locked_cells.get(build_cell, 0) > 0:
				return
			_create_block(build_cell, my_colony, dot_data[dot]["dot_id"], reason_str)
			nearest_banner["block_count"] += 1
			if nearest_banner["block_count"] >= nearest_banner["block_cap"]:
				if LOG_ENABLED:
					_log("[t%d] banner: id=%d completed at %d/%d blocks \u2014 expiring" % [_tick_num, nearest_banner["id"], nearest_banner["block_count"], nearest_banner["block_cap"]])
				nearest_banner["ticks_remaining"] = 0
			else:
				_refresh_build_banner(nearest_banner["id"])
		else:
			# March toward the banner; do not build this tick
			var banner_dir = _cell_to_dir(banner_cell)
			_march_toward_dir(dot, my_dir, banner_dir, my_colony)
		return
	# No eligible banner in range \u2014 rare chance to start a new monument
	if randf() >= BUILD_START_CHANCE:
		return
	# Stack combat-lock: don't found a monument on a cell with a live block-defender fight.
	if combat_locked_cells.get(my_cell, 0) > 0:
		return
	# Don't re-found on a cell already at/above the softcap height. A completed monument
	# re-founded with a fresh block budget is the remaining route to an unbounded cell;
	# guard it with the same receiving-cell height notion used by the stack gate.
	if _count_blocks_in_cell(my_cell, my_colony) >= STACK_HEIGHT_SOFTCAP:
		return
	_create_block(my_cell, my_colony, dot_data[dot]["dot_id"], "founder")
	_drop_build_banner(my_cell, my_colony)
	# Founder may now return to refresh this banner on subsequent build rolls.

func _execute_observe(dot: Node3D) -> void:
	var observe_weight = dot_data[dot]["cce"]["action"].get("observe", 0.0)
	var radius = int(OBSERVE_BASE_RADIUS + OBSERVE_SCALE * observe_weight)
	var radius_sq = radius * radius
	var my_dir = dot.position.normalized()
	var my_cell = _cell_key(my_dir)
	var my_colony = dot_data[dot]["colony"]

	# Enemy: nearest foreign dot
	var enemy_entry = null
	var enemy = _find_nearest_foreign_in_radius(my_dir, my_colony, radius)
	if enemy != null:
		enemy_entry = { "pos": enemy.position.normalized(), "dot": enemy, "observed_tick": _tick_num }

	# Speck: nearest speck within radius (linear scan — specks aren't grid-indexed)
	var speck_entry = null
	var best_speck_dist = radius_sq + 1
	for speck in specks:
		var d = _torus_cell_dist_sq(my_cell, _cell_key(speck.position.normalized()))
		if d <= radius_sq and d < best_speck_dist:
			best_speck_dist = d
			speck_entry = { "pos": speck.position.normalized(), "node": speck }

	# Ally: nearest same-colony dot (excluding self and blocks)
	var ally_entry = null
	var ally = _find_nearest_ally_in_radius(my_dir, my_colony, radius, dot)
	if ally != null:
		ally_entry = { "pos": ally.position.normalized(), "dot": ally }

	# Banner: nearest active same-colony build banner within radius
	# (no build_banners_used filter — observe is sensing, not committing)
	var banner_entry = null
	var best_banner_dist = radius_sq + 1
	for banner in build_banners:
		if banner["colony"] != my_colony:
			continue
		if banner["ticks_remaining"] <= 0:
			continue
		var d = _torus_cell_dist_sq(my_cell, banner["cell"])
		if d <= radius_sq and d < best_banner_dist:
			best_banner_dist = d
			banner_entry = { "pos": _cell_to_dir(banner["cell"]), "cell": banner["cell"] }

	# Only entries mapped in OBSERVE_MOVE_MAP are consumed today (speck -> gather).
	# enemy / ally / banner are sensed and stored but dormant; no consumer yet
	# (combat-walls design pending, see DEVNOTES 2026-05-13).
	dot_data[dot]["pending_observe"] = {
		"enemy": enemy_entry,
		"speck": speck_entry,
		"ally": ally_entry,
		"banner": banner_entry,
	}

func _is_at_or_adjacent(a: Vector2i, b: Vector2i) -> bool:
	# Wider than literal adjacency \u2014 lets builders within a ~5x5 area of the banner
	# participate, so the lateral footprint reflects the cloud's natural shape
	# instead of being clamped to the 8-neighbor ring.
	return _torus_cell_dist_sq(a, b) <= BUILD_FOOTPRINT_DIST_SQ

func _find_eligible_build_banner(dot: Node3D, my_cell: Vector2i, my_colony: int):
	if build_banners.is_empty():
		return null
	# build_banners_used is never written anywhere, so used.has(...) below is always
	# false. Dormant plumbing retained deliberately (easy to re-enable a per-dot banner
	# cooldown); see DEVNOTES 2026-05-12.
	var used = dot_data[dot].get("build_banners_used", {})
	var best = null
	var best_dist = BUILD_BANNER_RADIUS * BUILD_BANNER_RADIUS + 1
	for banner in build_banners:
		if banner["colony"] != my_colony:
			continue
		# Load-bearing (not routine filtering): a banner marked expired mid-tick because
		# its block_cap was hit must be invisible to lookup for the rest of the tick, or
		# remaining builders overshoot the cap. TTL cleanup removes it next tick.
		if banner["ticks_remaining"] <= 0:
			continue
		if used.has(banner["id"]):
			continue
		var d = _torus_cell_dist_sq(my_cell, banner["cell"])
		if d < best_dist:
			best_dist = d
			best = banner
	return best

# Now live: the height-gated lateral redirect for tall monuments calls this (was retained
# dead code, DEVNOTES 2026-05-12). Still the only place in this file that wraps grid
# neighbors correctly with (+ GRID_RES) before the modulo -- keep that seam-wrap idiom.
func _pick_lateral_cell(center_cell: Vector2i, colony: int, banner_cell: Vector2i = Vector2i(-1, -1), contained: bool = false) -> Vector2i:
	# Returns one of center_cell's 8 ring neighbours, weighted toward LOWER same-colony
	# stacks so the footprint domes up together. Weight = 1 / (1 + height): a bare cell
	# (height 0) weighs 1.0 and taller cells weigh progressively less but never zero, so a
	# taller cell is occasionally still chosen and the tops stay organic rather than a
	# perfectly smooth dome. Scope stays the 8-ring (footprint is not widened).
	# When contained, candidates are pre-filtered to within SHED_CONTAINMENT_DIST_SQ of
	# banner_cell before the weighted draw (never picked-then-rejected). The height-weighted
	# draw is what gates the receiving cell, so every returned cell has had its height
	# consulted. Returns Vector2i(-1, -1) if the filter leaves the ring empty; the caller
	# must skip rather than place ungated. On-cell callers pass no banner_cell/contained and
	# get the full unfiltered ring, unchanged.
	var neighbors = []
	var weights = []
	var total = 0.0
	for du in [-1, 0, 1]:
		for dv in [-1, 0, 1]:
			if du == 0 and dv == 0:
				continue
			var nb = Vector2i((center_cell.x + du + GRID_RES) % GRID_RES, (center_cell.y + dv + GRID_RES) % GRID_RES)
			if contained and _torus_cell_dist_sq(nb, banner_cell) > SHED_CONTAINMENT_DIST_SQ:
				continue
			var w = 1.0 / (1.0 + float(_count_blocks_in_cell(nb, colony)))
			neighbors.append(nb)
			weights.append(w)
			total += w
	if neighbors.is_empty():
		return Vector2i(-1, -1)  # containment left no candidate (degenerate geometry); caller skips
	var r = randf() * total
	for i in range(neighbors.size()):
		r -= weights[i]
		if r <= 0.0:
			return neighbors[i]
	return neighbors[neighbors.size() - 1]  # float-rounding fallback; ring is non-empty here

func _count_blocks_in_cell(cell: Vector2i, colony: int) -> int:
	var n = 0
	if spatial_grid.has(cell):
		for occupant in spatial_grid[cell]:
			if dot_data.has(occupant) and dot_data[occupant].get("is_block", false) and dot_data[occupant]["colony"] == colony:
				n += 1
	return n

func _create_block(cell: Vector2i, colony: int, builder_id: int = -1, reason: String = "") -> Node3D:
	# Determine stack index by counting same-colony blocks already in this cell
	var stack_index = 0
	if spatial_grid.has(cell):
		for occupant in spatial_grid[cell]:
			if dot_data.has(occupant) and dot_data[occupant].get("is_block", false):
				stack_index += 1
	if LOG_ENABLED and builder_id >= 0:
		_log("[t%d] block: builder=%d cell=(%d,%d) reason=%s height=%d" % [_tick_num, builder_id, cell.x, cell.y, reason, stack_index])
	# Refresh decay on existing blocks in this cell so active monuments don't crumble
	if spatial_grid.has(cell):
		for occupant in spatial_grid[cell]:
			if dot_data.has(occupant) and dot_data[occupant].get("is_block", false):
				dot_data[occupant]["decay_ticks_remaining"] = BLOCK_DECAY_TICKS
	var block = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = BLOCK_MESH_SIZE
	block.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.CYAN
	mat.emission_enabled = true
	mat.emission = Color.CYAN
	mat.emission_energy_multiplier = 0.6
	block.material_override = mat
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(block)
	dots.append(block)
	var dir = _cell_to_dir(cell)
	dot_data[block] = {
		"age": 0,
		"cce": _deep_copy_cce(NEUTRAL_CCE),
		"colony": colony,
		"is_block": true,
		"decay_ticks_remaining": BLOCK_DECAY_TICKS,
		"stack_index": stack_index,
	}
	# Blocks have defend = BLOCK_DEFEND_VALUE so they fight back via the standard combat formula
	dot_data[block]["cce"]["action"]["defend"] = BLOCK_DEFEND_VALUE
	known_colonies[colony] = true
	block_counts[colony] = block_counts.get(colony, 0) + 1
	# Place the block along the surface normal at stack_index * step above the surface
	block.position = dir * (SPHERE_RADIUS + DOT_SURFACE_OFFSET + stack_index * BLOCK_HEIGHT_STEP)
	var new_basis = Basis()
	new_basis.y = dir
	new_basis.x = new_basis.y.cross(Vector3.FORWARD if abs(dir.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	new_basis.z = new_basis.x.cross(new_basis.y).normalized()
	block.transform.basis = new_basis
	_grid_insert(block, cell)
	_update_dot_color(block)
	return block

# Stage (c): a lone waller's wall block. Separate from _create_block rather than a shared
# parameterization — mesh size and orientation source both differ (threat bearing, not a
# fixed reference), and this deliberately skips monument stacking (no stack_index scan). It
# still uses BLOCK_DEFEND_VALUE / decay / is_block so it fights and decays like any other
# block (per the "blocks are already full combat participants" inspection finding).
func _create_wall_block(cell: Vector2i, colony: int, threat_dir: Vector3, builder_id: int = -1) -> Node3D:
	if LOG_ENABLED and builder_id >= 0:
		_log("[t%d] block: builder=%d cell=(%d,%d) reason=waller height=0" % [_tick_num, builder_id, cell.x, cell.y])
	var block = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = WALL_MESH_SIZE
	block.mesh = box
	var mat = StandardMaterial3D.new()
	# Initial colour; _update_dot_color below is the authority (fog / is_wall branch).
	mat.albedo_color = WALL_COLOR
	mat.emission_enabled = true
	mat.emission = WALL_COLOR
	mat.emission_energy_multiplier = 0.6
	block.material_override = mat
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(block)
	dots.append(block)
	var dir = _cell_to_dir(cell)
	dot_data[block] = {
		"age": 0,
		"cce": _deep_copy_cce(NEUTRAL_CCE),
		"colony": colony,
		"is_block": true,
		"is_wall": true,  # fence segment (vs monument block); drives the distinct colour in _update_dot_color
		"decay_ticks_remaining": BLOCK_DECAY_TICKS,
		"stack_index": 0,
	}
	dot_data[block]["cce"]["action"]["defend"] = BLOCK_DEFEND_VALUE
	known_colonies[colony] = true
	block_counts[colony] = block_counts.get(colony, 0) + 1
	block.position = dir * (SPHERE_RADIUS + DOT_SURFACE_OFFSET)
	# Same frame construction as _create_block, but the reference vector is the threat
	# bearing instead of a fixed world axis. y.cross(v) is always already perpendicular to y
	# regardless of v's own tilt, so threat_dir need not be pre-projected onto the tangent
	# plane. Chosen orientation (per design decision): x = tangent PERPENDICULAR to the
	# threat (the wall's long axis, forming a barrier across the enemy's path); z = tangent
	# TOWARD/away the threat (the thin axis, the wall's thickness facing the enemy).
	var new_basis = Basis()
	new_basis.y = dir
	var ref_dir = threat_dir
	if abs(dir.dot(threat_dir.normalized())) > 0.999:
		# Degenerate: enemy direction ~parallel to the surface normal here. Fall back to the
		# same reference _create_block uses so the mesh still gets a valid orthonormal frame
		# instead of a NaN basis from a near-zero cross product.
		ref_dir = Vector3.FORWARD if abs(dir.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	new_basis.x = new_basis.y.cross(ref_dir).normalized()
	new_basis.z = new_basis.x.cross(new_basis.y).normalized()
	block.transform.basis = new_basis
	_grid_insert(block, cell)
	_update_dot_color(block)
	return block

# --- Build banners ---

func _drop_build_banner(cell: Vector2i, colony: int) -> int:
	var id = _next_build_banner_id
	_next_build_banner_id += 1
	var avg_build = _compute_colony_avg_build_cce(colony)
	var block_cap = int(round(BUILD_MONUMENT_BASE + BUILD_MONUMENT_SCALE * avg_build))
	build_banners.append({
		"id": id,
		"cell": cell,
		"colony": colony,
		"ticks_remaining": BUILD_BANNER_TTL,
		"block_cap": block_cap,
		"block_count": 0,
	})
	if LOG_ENABLED:
		_log("[t%d] banner: id=%d cell=(%d,%d) cap=%d (avg_build=%.3f)" % [_tick_num, id, cell.x, cell.y, block_cap, avg_build])
	return id

func _compute_colony_avg_build_cce(colony: int) -> float:
	var total = 0.0
	var count = 0
	for dot in dots:
		if dot_data[dot]["colony"] != colony:
			continue
		if dot_data[dot].get("is_block", false):
			continue
		total += dot_data[dot]["cce"]["action"].get("build", 0.0)
		count += 1
	if count == 0:
		return 0.0
	return total / count

func _refresh_build_banner(id: int):
	for banner in build_banners:
		if banner["id"] == id:
			banner["ticks_remaining"] = BUILD_BANNER_TTL
			return

func _tick_build_banners():
	var i = build_banners.size() - 1
	while i >= 0:
		build_banners[i]["ticks_remaining"] -= 1
		if build_banners[i]["ticks_remaining"] <= 0:
			build_banners.remove_at(i)
		i -= 1

# --- Rally banners ---

func _drop_rally_banner(cell: Vector2i, colony: int):
	# Refresh TTL if a banner already exists at this cell for this colony
	for banner in rally_banners:
		if banner["colony"] == colony and banner["cell"] == cell:
			banner["ticks_remaining"] = BANNER_TTL
			return
	rally_banners.append({"cell": cell, "colony": colony, "ticks_remaining": BANNER_TTL})

func _tick_rally_banners():
	var i = rally_banners.size() - 1
	while i >= 0:
		rally_banners[i]["ticks_remaining"] -= 1
		if rally_banners[i]["ticks_remaining"] <= 0:
			rally_banners.remove_at(i)
		i -= 1

# --- Wall banners (stage (b) drop; stages (d)/(e) consumption below) ---

func _drop_wall_banner(cell: Vector2i, colony: int, threat_dir: Vector3):
	# Refresh TTL (and the threat bearing, which may have shifted) if a wall banner already
	# exists at this cell for this colony
	for banner in wall_banners:
		if banner["colony"] == colony and banner["cell"] == cell:
			banner["ticks_remaining"] = WALL_BANNER_TTL
			banner["threat_dir"] = threat_dir
			_telemetry({ "type": "wall_banner_dropped", "tick": _tick_num, "colony": colony, "cell": [cell.x, cell.y] })
			return
	wall_banners.append({"cell": cell, "colony": colony, "ticks_remaining": WALL_BANNER_TTL, "threat_dir": threat_dir})
	_telemetry({ "type": "wall_banner_dropped", "tick": _tick_num, "colony": colony, "cell": [cell.x, cell.y] })

func _tick_wall_banners():
	var i = wall_banners.size() - 1
	while i >= 0:
		wall_banners[i]["ticks_remaining"] -= 1
		if wall_banners[i]["ticks_remaining"] <= 0:
			wall_banners.remove_at(i)
		i -= 1

func _find_nearest_wall_banner(my_cell: Vector2i, my_colony: int):
	if wall_banners.is_empty():
		return null
	var best = null
	var best_dist = WALL_BANNER_RADIUS * WALL_BANNER_RADIUS + 1
	for banner in wall_banners:
		if banner["colony"] != my_colony:
			continue
		if banner["ticks_remaining"] <= 0:
			continue
		var d = _torus_cell_dist_sq(my_cell, banner["cell"])
		if d < best_dist:
			best_dist = d
			best = banner
	return best

# Stage (e): where the next fence segment goes. The fence runs along the tangent perpendicular
# to the threat bearing (same axis the wall block's long side is oriented to). Walk outward from
# the banner seed cell, alternating sides, and return the first empty, non-locked cell within
# WALL_MAX_HALF_LENGTH. Returns (-1,-1) when the fence is full (all line cells occupied).
func _wall_line_target_cell(banner, colony: int) -> Vector2i:
	var seed_cell = banner["cell"]
	var seed_dir = _cell_to_dir(seed_cell)
	var threat_dir = banner.get("threat_dir", null)
	var along: Vector3
	if threat_dir == null or abs(seed_dir.dot(threat_dir.normalized())) > 0.999:
		# Missing or degenerate (threat ~parallel to the surface normal): fall back to any
		# stable tangent so the fence still has a well-defined direction.
		along = seed_dir.cross(Vector3.FORWARD if abs(seed_dir.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	else:
		along = seed_dir.cross(threat_dir.normalized()).normalized()
	for k in range(0, WALL_MAX_HALF_LENGTH + 1):
		var sides = [0] if k == 0 else [1, -1]
		for s in sides:
			var theta = CELL_STEP * k * s
			# Exact great-circle step along the fence tangent (not a chord approximation).
			var probe = (seed_dir * cos(theta) + along * sin(theta)).normalized()
			var cell = _cell_key(probe)
			if _count_blocks_in_cell(cell, colony) == 0 and combat_locked_cells.get(cell, 0) == 0:
				return cell
	return Vector2i(-1, -1)

# Stage (e): a build-inclined dot's response to an in-range wall banner. March to the next open
# fence cell; once standing on it, place an oriented segment there and perch (stage d). While a
# wall banner is in range this fully replaces monument building — even a full fence just idles
# the dot rather than letting it fall back to a monument.
func _respond_to_wall_banner(dot: Node3D, my_dir: Vector3, my_cell: Vector2i, my_colony: int, banner) -> void:
	var target_cell = _wall_line_target_cell(banner, my_colony)
	if target_cell.x < 0:
		return  # fence full (or degenerate) — idle, do NOT build a monument
	if my_cell == target_cell:
		if combat_locked_cells.get(target_cell, 0) > 0:
			return  # don't add a segment to a cell with a live block-defender fight
		var threat_dir = banner.get("threat_dir", my_dir)
		var seg = _create_wall_block(target_cell, my_colony, threat_dir, dot_data[dot]["dot_id"])
		_perch_waller(dot, seg)
		_telemetry({ "type": "wall_extend", "tick": _tick_num, "colony": my_colony, "cell": [target_cell.x, target_cell.y] })
	else:
		_march_toward_dir(dot, my_dir, _cell_to_dir(target_cell), my_colony)

# Stage (d): lock a dot on top of the wall segment it just built. Forward ref in wall_perch,
# inverse ref on the block; both are torn down by _remove_dot when either node dies.
func _perch_waller(dot: Node3D, block: Node3D) -> void:
	wall_perch[dot] = block
	dot_data[block]["perched_by"] = dot
	# Sit the dot one block-height above its segment's centre so it reads as perched on top.
	var perch_dir = block.position.normalized()
	dot.position = perch_dir * (SPHERE_RADIUS + DOT_SURFACE_OFFSET + BLOCK_HEIGHT_STEP)
	if dot_data.has(dot) and dot_cell.has(dot):
		_grid_update_position(dot)

func _cell_to_dir(cell: Vector2i) -> Vector3:
	# Inverse of _cell_key: cell coord -> sphere direction
	var u = (float(cell.x) / GRID_RES - 0.5) * TAU
	var v = (float(cell.y) / GRID_RES - 0.5) * PI
	var y = sin(v)
	var r = cos(v)
	return Vector3(r * sin(u), y, r * cos(u)).normalized()

func _torus_cell_dist_sq(a: Vector2i, b: Vector2i) -> int:
	# Wrap-around distance squared on the GRID_RES x GRID_RES torus
	var dx = abs(a.x - b.x)
	if dx > GRID_RES / 2:
		dx = GRID_RES - dx
	var dy = abs(a.y - b.y)
	if dy > GRID_RES / 2:
		dy = GRID_RES - dy
	return dx * dx + dy * dy

func _march_toward_rally_banner(dot: Node3D, my_dir: Vector3, my_colony: int):
	if rally_banners.is_empty():
		return
	var my_cell = _cell_key(my_dir)
	var best = null
	var best_dist = RALLY_RADIUS * RALLY_RADIUS + 1
	for banner in rally_banners:
		if banner["colony"] != my_colony:
			continue
		var d = _torus_cell_dist_sq(my_cell, banner["cell"])
		if d < best_dist:
			best_dist = d
			best = banner
	if best == null:
		return
	var target_dir = _cell_to_dir(best["cell"])
	_march_toward_dir(dot, my_dir, target_dir, my_colony)

# --- Combat ---

func _release_cell_lock(cluster) -> void:
	# Decrement the per-cell combat lock this cluster holds, once. Idempotent: the "locked_cell"
	# marker is erased after release, so a second call on the same cluster is a no-op (prevents
	# double-decrement). Count going to <= 0 clears the entry, so it can never go negative.
	if not cluster.has("locked_cell"):
		return
	var lc = cluster["locked_cell"]
	var n = combat_locked_cells.get(lc, 0) - 1
	if n <= 0:
		combat_locked_cells.erase(lc)
	else:
		combat_locked_cells[lc] = n
	cluster.erase("locked_cell")

func _tick_combat_clusters():
	var to_remove_clusters = []
	var to_delete = {}
	var to_advance = []
	for cluster in combat_clusters:
		cluster["ticks_remaining"] -= 1
		if cluster["ticks_remaining"] <= 0:
			# Track which defenders already have a winning attacker claiming their cell
			var cell_claimed_by = {}
			# One removed layer per block-defender fight: once this defender loses a layer this
			# resolution, later pairs for the same defender don't remove a second (mirrors the
			# original guard, where the single deleted defender skipped later same-defender pairs).
			var block_defeated = {}
			for pair in cluster["pairs"]:
				var attacker = pair["attacker"]
				var defender = pair["defender"]
				# dot_data.has() is sufficient \u2014 _remove_dot erases it before queue_free
				if not dot_data.has(attacker) or not dot_data.has(defender):
					continue
				if to_delete.has(attacker) or to_delete.has(defender) or block_defeated.has(defender):
					continue
				var a_power = dot_data[attacker]["cce"]["action"].get("attack", 0.0) + dot_data[attacker]["cce"]["action"].get("defend", 0.0)
				var d_power = dot_data[defender]["cce"]["action"].get("attack", 0.0) + dot_data[defender]["cce"]["action"].get("defend", 0.0)
				var defender_is_block = dot_data[defender].get("is_block", false)
				# Distinguish a fence segment from a monument block so verification can tell
				# "attackers hitting the wall" from ordinary monument combat without cross-
				# referencing cells against wall_extend.
				var defender_is_wall = dot_data[defender].get("is_wall", false)
				# Capture colonies BEFORE any _remove_dot (deletions are deferred to to_delete below).
				var _resolve_cell = _cell_key(defender.position.normalized())
				_telemetry({
					"type": "combat_resolve",
					"tick": _tick_num,
					"winner_colony": dot_data[attacker]["colony"] if a_power >= d_power else dot_data[defender]["colony"],
					"loser_colony": dot_data[defender]["colony"] if a_power >= d_power else dot_data[attacker]["colony"],
					"a_power": a_power,
					"d_power": d_power,
					"defender_was_block": defender_is_block,
					"defender_was_wall": defender_is_wall,
					"cell": [_resolve_cell.x, _resolve_cell.y]
				})
				if a_power >= d_power:
					if defender_is_block:
						# Topmost-removal: the fight targets the bottom block (oldest; the tie-break in
						# _find_nearest_foreign_in_radius keeps the first array occupant), but a won
						# defeat removes the TOPMOST live same-colony block of the stack — highest
						# stack_index, not already queued. For a single-block stack the only node IS the
						# defender, so victim == defender and the outcome is byte-identical to before.
						block_defeated[defender] = true
						var block_cell = dot_cell.get(defender)
						var victim = defender
						if block_cell != null and spatial_grid.has(block_cell):
							var best_idx = -1
							for occupant in spatial_grid[block_cell]:
								if not dot_data.has(occupant):
									continue
								if not dot_data[occupant].get("is_block", false):
									continue
								if dot_data[occupant]["colony"] != dot_data[defender]["colony"]:
									continue
								if to_delete.has(occupant):
									continue
								var idx = dot_data[occupant].get("stack_index", 0)
								if idx > best_idx:
									best_idx = idx
									victim = occupant
						to_delete[victim] = true
						# Attacker advances only if the cell will be empty after this block is removed
						var cell_will_be_empty = true
						if block_cell != null and spatial_grid.has(block_cell):
							for occupant in spatial_grid[block_cell]:
								if occupant != victim and not to_delete.has(occupant):
									cell_will_be_empty = false
									break
						if cell_will_be_empty and not cell_claimed_by.has(defender):
							cell_claimed_by[defender] = attacker
							to_advance.append({"winner": attacker, "target_dir": defender.position.normalized()})
					else:
						to_delete[defender] = true
						# First winning attacker against this defender claims the cell
						if not cell_claimed_by.has(defender):
							cell_claimed_by[defender] = attacker
							to_advance.append({"winner": attacker, "target_dir": defender.position.normalized()})
				else:
					to_delete[attacker] = true
			for pair in cluster["pairs"]:
				combat_locked.erase(pair["attacker"])
				combat_locked.erase(pair["defender"])
				cluster_by_defender.erase(pair["defender"])
			to_remove_clusters.append(cluster)
	for cluster in to_remove_clusters:
		_release_cell_lock(cluster)
		combat_clusters.erase(cluster)
	for dot in to_delete:
		_remove_dot(dot)
	# Advance winners into vacated cells
	for adv in to_advance:
		var winner = adv["winner"]
		if dot_data.has(winner):
			_place_dot_on_sphere(winner, adv["target_dir"])

func _remove_dot(dot: Node3D):
	# Synchronous: dot_data is erased here before queue_free, so callers may rely on
	# dot_data.has(dot) alone for liveness (grid lookups do this, no is_instance_valid).
	if not dot_data.has(dot):
		return
	# Stage (d) perch teardown. A dying wall segment releases its perched builder back to the
	# surface (this is the "wall dies -> waller unlocks" path, covering both combat removal and
	# decay). A dying perched builder clears its segment's back-ref so no stale reference remains.
	if dot_data[dot].get("is_block", false) and dot_data[dot].has("perched_by"):
		var perched = dot_data[dot]["perched_by"]
		if wall_perch.get(perched) == dot:
			wall_perch.erase(perched)
			if dot_data.has(perched):
				_place_dot_on_sphere(perched, perched.position.normalized())
	if wall_perch.has(dot):
		var perched_block = wall_perch[dot]
		wall_perch.erase(dot)
		if dot_data.has(perched_block):
			dot_data[perched_block].erase("perched_by")
	# Incrementally remove from spatial grid
	if dot_cell.has(dot):
		var key = dot_cell[dot]
		if spatial_grid.has(key):
			spatial_grid[key].erase(dot)
			if spatial_grid[key].is_empty():
				spatial_grid.erase(key)
		dot_cell.erase(dot)
	# Resolve combat clusters this dot was in
	var to_remove_clusters = []
	for cluster in combat_clusters:
		var involved = false
		for pair in cluster["pairs"]:
			if pair["attacker"] == dot or pair["defender"] == dot:
				involved = true
				var survivor = pair["defender"] if pair["attacker"] == dot else pair["attacker"]
				combat_locked.erase(survivor)
		if involved:
			var still_active = false
			for pair in cluster["pairs"]:
				if pair["attacker"] != dot and pair["defender"] != dot:
					if dot_data.has(pair["attacker"]) and dot_data.has(pair["defender"]):
						still_active = true
						break
			if not still_active:
				# Clean up index for any defenders in this cluster
				for pair in cluster["pairs"]:
					if cluster_by_defender.get(pair["defender"]) == cluster:
						cluster_by_defender.erase(pair["defender"])
				to_remove_clusters.append(cluster)
	for cluster in to_remove_clusters:
		_release_cell_lock(cluster)
		combat_clusters.erase(cluster)
	dots.erase(dot)
	var removed_colony = dot_data[dot]["colony"]
	if dot_data[dot].get("is_block", false):
		block_counts[removed_colony] = max(0, block_counts.get(removed_colony, 0) - 1)
	else:
		colony_counts[removed_colony] = max(0, colony_counts.get(removed_colony, 0) - 1)
	dot_data.erase(dot)
	combat_locked.erase(dot)
	if dot == player_dot:
		# Fallback may resolve to a block or an enemy-colony dot. Harmless today because
		# player_dot is only read at _ready by spawn functions, never at runtime; a trap
		# if anything starts reading it mid-game.
		player_dot = dots[0] if dots.size() > 0 else null
	dot.queue_free()

# --- Color ---

func _update_dot_color(dot: Node3D):
	var colony = dot_data[dot]["colony"]
	var mat = dot.material_override as StandardMaterial3D
	if not mat:
		return
	if not revealed_colonies.get(colony, false):
		mat.albedo_color = FOG_COLOR
		mat.emission = FOG_EMISSION
		return
	# Fence segments render a fixed distinct colour (after fog, so hidden colonies still fog),
	# rather than the CCE mix — otherwise they'd be identical to defend-blue monument blocks.
	if dot_data[dot].get("is_wall", false):
		mat.albedo_color = WALL_COLOR
		mat.emission = WALL_COLOR
		return
	var cce = dot_data[dot]["cce"]
	var total = 0.0
	var weighted = Color(0, 0, 0, 0)
	for key in CCE_COLORS:
		var weight = 0.0
		if cce["motion"].has(key):
			weight = cce["motion"][key]
		elif cce["action"].has(key):
			weight = cce["action"][key]
		if weight > 0.0:
			weighted.r += CCE_COLORS[key].r * weight
			weighted.g += CCE_COLORS[key].g * weight
			weighted.b += CCE_COLORS[key].b * weight
			total += weight
	var saturation = clamp(total / MAX_CCE_FOR_SATURATION, 0.0, 1.0)
	var hue_color = CCE_NEUTRAL_COLOR
	if total > 0.0:
		hue_color = Color(weighted.r / total, weighted.g / total, weighted.b / total)
	var color = CCE_NEUTRAL_COLOR.lerp(hue_color, saturation)
	mat.albedo_color = color
	mat.emission = color

func _update_all_dot_colors():
	for dot in dots:
		_update_dot_color(dot)

func _compute_colony_center(colony: int) -> Vector3:
	var center = Vector3.ZERO
	var count = 0
	for dot in dots:
		if dot_data[dot]["colony"] == colony:
			center += dot.position.normalized()
			count += 1
	if count > 0:
		return (center / count).normalized()
	return Vector3.ZERO

# --- Fog of war ---

func _check_fog_of_war():
	# Cheap early exit: known set size matches revealed set size
	if revealed_colonies.size() >= known_colonies.size():
		return
	for dot in dots:
		var colony = dot_data[dot]["colony"]
		if colony == LOCAL_COLONY or revealed_colonies.get(colony, false):
			continue
		var key = _cell_key(dot.position.normalized())
		for du in [-1, 0, 1]:
			for dv in [-1, 0, 1]:
				# u wraps (longitude); v clamps (latitude — no pole wrap, see F2)
				var ny = key.y + dv
				if ny < 0 or ny > GRID_RES - 1:
					continue
				var neighbor = Vector2i((key.x + du + GRID_RES) % GRID_RES, ny)
				if spatial_grid.has(neighbor):
					for occupant in spatial_grid[neighbor]:
						if dot_data.has(occupant) and dot_data[occupant]["colony"] == LOCAL_COLONY:
							revealed_colonies[colony] = true
							print("Colony %d revealed!" % colony)
							_telemetry({ "type": "reveal", "tick": _tick_num, "colony": colony })
							_update_all_dot_colors()
							return

# --- Spatial grid (incrementally maintained) ---

func _cell_key(dir: Vector3) -> Vector2i:
	var d = dir.normalized()
	var u = int((atan2(d.x, d.z) / TAU + 0.5) * GRID_RES) % GRID_RES
	var v = int((asin(clamp(d.y, -1.0, 1.0)) / PI + 0.5) * GRID_RES) % GRID_RES
	return Vector2i(u, v)

func _grid_insert(dot: Node3D, key: Vector2i):
	if not spatial_grid.has(key):
		spatial_grid[key] = []
	spatial_grid[key].append(dot)
	dot_cell[dot] = key

func _grid_update_position(dot: Node3D):
	# Called after a dot moves \u2014 rehomes it in the grid if its cell changed
	var new_key = _cell_key(dot.position.normalized())
	var old_key = dot_cell.get(dot, null)
	if old_key == new_key:
		return
	if old_key != null and spatial_grid.has(old_key):
		spatial_grid[old_key].erase(dot)
		if spatial_grid[old_key].is_empty():
			spatial_grid.erase(old_key)
	_grid_insert(dot, new_key)

func _is_cell_occupied(dir: Vector3) -> bool:
	var key = _cell_key(dir)
	return spatial_grid.has(key) and spatial_grid[key].size() > 0

# Exact-cell foreign check: used by marches that advance right up to the line.
func _is_foreign_in_exact_cell(dir: Vector3, my_colony: int) -> bool:
	var key = _cell_key(dir)
	if not spatial_grid.has(key):
		return false
	for occupant in spatial_grid[key]:
		if dot_data.has(occupant) and dot_data[occupant]["colony"] != my_colony:
			return true
	return false

# 3x3-neighborhood foreign check: used by wander/spawn for separation from foreigners.
func _is_blocked_by_foreign(dir: Vector3, my_colony: int) -> bool:
	var key = _cell_key(dir)
	for du in [-1, 0, 1]:
		for dv in [-1, 0, 1]:
			# u wraps (longitude); v clamps (latitude — no pole wrap, see F2)
			var ny = key.y + dv
			if ny < 0 or ny > GRID_RES - 1:
				continue
			var neighbor = Vector2i((key.x + du + GRID_RES) % GRID_RES, ny)
			if spatial_grid.has(neighbor):
				for occupant in spatial_grid[neighbor]:
					if dot_data.has(occupant) and dot_data[occupant]["colony"] != my_colony:
						return true
	return false

func _find_nearest_foreign_in_radius(dir: Vector3, my_colony: int, radius: int):
	var key = _cell_key(dir)
	var best = null
	var best_dist = INF
	for du in range(-radius, radius + 1):
		for dv in range(-radius, radius + 1):
			# u wraps (longitude); v clamps (latitude — no pole wrap, see F2)
			var ny = key.y + dv
			if ny < 0 or ny > GRID_RES - 1:
				continue
			var neighbor = Vector2i((key.x + du + GRID_RES) % GRID_RES, ny)
			if spatial_grid.has(neighbor):
				for occupant in spatial_grid[neighbor]:
					if dot_data.has(occupant) and dot_data[occupant]["colony"] != my_colony:
						var occ_key = dot_cell.get(occupant, _cell_key(occupant.position.normalized()))
						# Box (non-wrapping) distance metric, an accepted choice here;
						# torus-wrapped distance is used elsewhere (_torus_cell_dist_sq).
						var d = float((key - occ_key).length_squared())
						if d < best_dist:
							best_dist = d
							best = occupant
	return best

func _find_nearest_ally_in_radius(dir: Vector3, my_colony: int, radius: int, exclude: Node3D):
	var key = _cell_key(dir)
	var best = null
	var best_dist = INF
	for du in range(-radius, radius + 1):
		for dv in range(-radius, radius + 1):
			# u wraps (longitude); v clamps (latitude — no pole wrap, see F2)
			var ny = key.y + dv
			if ny < 0 or ny > GRID_RES - 1:
				continue
			var neighbor = Vector2i((key.x + du + GRID_RES) % GRID_RES, ny)
			if spatial_grid.has(neighbor):
				for occupant in spatial_grid[neighbor]:
					if occupant == exclude:
						continue
					if not dot_data.has(occupant):
						continue
					if dot_data[occupant].get("is_block", false):
						continue
					if dot_data[occupant]["colony"] != my_colony:
						continue
					var occ_key = dot_cell.get(occupant, _cell_key(occupant.position.normalized()))
					# Box (non-wrapping) distance metric, an accepted choice here;
					# torus-wrapped distance is used elsewhere (_torus_cell_dist_sq).
					var d = float((key - occ_key).length_squared())
					if d < best_dist:
						best_dist = d
						best = occupant
	return best

func _get_foreign_dots_near(dir: Vector3, my_colony: int) -> Array:
	var result = []
	var key = _cell_key(dir)
	for du in [-1, 0, 1]:
		for dv in [-1, 0, 1]:
			# u wraps (longitude); v clamps (latitude — no pole wrap, see F2)
			var ny = key.y + dv
			if ny < 0 or ny > GRID_RES - 1:
				continue
			var neighbor = Vector2i((key.x + du + GRID_RES) % GRID_RES, ny)
			if spatial_grid.has(neighbor):
				for occupant in spatial_grid[neighbor]:
					if dot_data.has(occupant) and dot_data[occupant]["colony"] != my_colony:
						result.append(occupant)
	return result

# --- Dot management ---

func _age_dots():
	var to_remove = []
	for dot in dots:
		if dot_data[dot].get("is_block", false):
			dot_data[dot]["decay_ticks_remaining"] -= 1
			if dot_data[dot]["decay_ticks_remaining"] <= 0:
				to_remove.append(dot)
		else:
			dot_data[dot]["age"] += 1
			if dot_data[dot]["age"] >= DOT_LIFETIME:
				to_remove.append(dot)
	for dot in to_remove:
		_remove_dot(dot)

func _spawn_player_dot():
	var angle = randf() * TAU
	player_dot = _create_dot(Vector3(sin(angle), 0.0, cos(angle)), null, LOCAL_COLONY, COLONY0_CCE)
	_focus_on_colony()

func _spawn_enemy_colony():
	var player_dir = player_dot.position.normalized()
	var up = Vector3.UP if abs(player_dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var perp = player_dir.cross(up).normalized()
	var enemy_dir = (player_dir * cos(PI / 4.0) + perp * sin(PI / 4.0)).normalized()
	known_colonies[ENEMY_COLONY] = true
	_create_dot(enemy_dir, null, ENEMY_COLONY, COLONY1_CCE)

func _log(line: String):
	if not LOG_ENABLED:
		return
	var f = FileAccess.open(LOG_FILE, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_FILE, FileAccess.WRITE)
		if f == null:
			return
	f.seek_end()
	f.store_string(line + "\n")
	f.close()

# Persistent JSONL telemetry — dedicated, NOT an extension of _log. One JSON object
# per line, appended as it happens; never truncated (persistence is the point).
func _telemetry(record: Dictionary):
	if not TELEMETRY_ENABLED:
		return
	var f = FileAccess.open(TELEMETRY_FILE, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(TELEMETRY_FILE, FileAccess.WRITE)
		if f == null:
			return
	f.seek_end()
	f.store_string(JSON.stringify(record) + "\n")
	f.close()

func _spawn_test_population():
	# Disable reproduce on the founder so population stays controlled
	if player_dot and dot_data.has(player_dot):
		dot_data[player_dot]["cce"]["action"]["reproduce"] = 0.0
	var founder_dir = player_dot.position.normalized()
	var up = Vector3.UP if abs(founder_dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var tangent = founder_dir.cross(up).normalized()
	var bitangent = founder_dir.cross(tangent).normalized()
	var to_spawn = TEST_POPULATION - 1  # founder already exists
	var spawned = 0
	var attempts = 0
	while spawned < to_spawn and attempts < 200:
		attempts += 1
		var angle = randf() * TAU
		var radius = lerp(SPAWN_NUDGE, SPAWN_NUDGE * 4.0, randf())
		var nudge = (tangent * cos(angle) + bitangent * sin(angle)) * radius
		var dir = (founder_dir + nudge).normalized()
		if _is_cell_occupied(dir):
			continue
		var new_dot = _create_dot(dir, null, LOCAL_COLONY, COLONY0_CCE)
		# Disable reproduce so population is fixed
		dot_data[new_dot]["cce"]["action"]["reproduce"] = 0.0
		spawned += 1
	print("[test] spawned %d test dots (founder + %d), log: %s" % [spawned + 1, spawned, LOG_FILE])

func _spawn_dot_near(parent: Node3D, colony: int = LOCAL_COLONY):
	if parent == null:
		return
	if colony_counts.get(colony, 0) >= MAX_POPULATION_PER_COLONY:
		return
	var dir = parent.position.normalized()
	var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var tangent = dir.cross(up).normalized()
	var bitangent = dir.cross(tangent).normalized()
	var angle = randf() * TAU
	var nudge = (tangent * cos(angle) + bitangent * sin(angle)) * SPAWN_NUDGE
	var new_dir = (dir + nudge).normalized()
	if not _is_cell_occupied(new_dir) and not _is_blocked_by_foreign(new_dir, colony):
		# full_inheritance=true here bypasses CCE_DILUTION (testing posture; see CCE_DILUTION).
		_create_dot(new_dir, parent, colony, {}, true)

func _create_dot(direction: Vector3, parent, colony: int = LOCAL_COLONY, preset_cce: Dictionary = {}, full_inheritance: bool = false) -> Node3D:
	var dot = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.015, 0.006, 0.015)
	dot.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.CYAN
	mat.emission_enabled = true
	mat.emission = Color.CYAN
	mat.emission_energy_multiplier = 0.8
	dot.material_override = mat
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(dot)
	# If this _create_dot came from reproduce during _tick_all_dots, the newborn is
	# appended to `dots` and ticked in the same pass (see the _tick_all_dots loop note).
	dots.append(dot)

	var cce = _deep_copy_cce(NEUTRAL_CCE)
	if not preset_cce.is_empty():
		cce = _deep_copy_cce(preset_cce)
	elif parent != null and dot_data.has(parent):
		var parent_cce = dot_data[parent]["cce"]
		# Birth-time dilution: children get CCE_DILUTION * parent weight, applied once
		# here (between generations), never again during the dot's life. full_inheritance
		# bypasses it, and is currently always true via _spawn_dot_near.
		var dilution = 1.0 if full_inheritance else CCE_DILUTION
		for layer in ["motion", "action"]:
			for key in cce[layer]:
				if parent_cce[layer].has(key):
					cce[layer][key] = parent_cce[layer][key] * dilution
		for key in cce["dials"]:
			if parent_cce["dials"].has(key):
				cce["dials"][key] = parent_cce["dials"][key] * dilution

	dot_data[dot] = { "age": 0, "cce": cce, "colony": colony, "build_banners_used": {}, "dot_id": _next_dot_id, "pending_observe": null, "collect_lock": null }
	_next_dot_id += 1
	known_colonies[colony] = true
	colony_counts[colony] = colony_counts.get(colony, 0) + 1
	_place_dot_on_sphere(dot, direction)
	# Insert into spatial grid (initial placement)
	_grid_insert(dot, _cell_key(dot.position.normalized()))
	_update_dot_color(dot)
	return dot

func _deep_copy_cce(source: Dictionary) -> Dictionary:
	var copy = {}
	for layer in source:
		if source[layer] is Dictionary:
			copy[layer] = {}
			for key in source[layer]:
				copy[layer][key] = source[layer][key]
		else:
			copy[layer] = source[layer]
	return copy

# --- Soul specks ---

func _create_speck(dir: Vector3) -> void:
	var speck = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.008, 0.003, 0.008)
	speck.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 1.2
	speck.material_override = mat
	speck.position = dir.normalized() * (SPHERE_RADIUS + DOT_SURFACE_OFFSET)
	add_child(speck)
	specks.append(speck)

func _tick_specks() -> void:
	if randf() < SPECK_SPAWN_CHANCE:
		_create_speck(_cell_to_dir(Vector2i(randi() % GRID_RES, randi() % GRID_RES)))

# --- Camera ---

func _focus_on_colony():
	var center = _compute_colony_center(LOCAL_COLONY)
	orbit_yaw = atan2(center.x, center.z)
	orbit_pitch = asin(clamp(center.y, -1.0, 1.0))

func _update_camera():
	var pitch_clamped = clamp(orbit_pitch, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
	var x = zoom_distance * cos(pitch_clamped) * sin(orbit_yaw)
	var y = zoom_distance * sin(pitch_clamped)
	var z = zoom_distance * cos(pitch_clamped) * cos(orbit_yaw)
	camera.position = Vector3(x, y, z)
	camera.look_at(Vector3.ZERO, Vector3.UP)

# --- Input ---

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_orbiting = event.pressed
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(-ZOOM_SPEED)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(ZOOM_SPEED)

	if event is InputEventMouseMotion and is_orbiting:
		orbit_yaw -= event.relative.x * ROTATE_SPEED
		orbit_pitch += event.relative.y * ROTATE_SPEED

	if event is InputEventScreenTouch:
		if event.pressed:
			touch_positions[event.index] = event.position
			if touch_positions.size() == 1:
				single_touch_active = true
				single_touch_index = event.index
		else:
			touch_positions.erase(event.index)
			pinch_last_distance = 0.0
			if event.index == single_touch_index:
				single_touch_active = false
				single_touch_index = -1

	if event is InputEventScreenDrag:
		touch_positions[event.index] = event.position
		if touch_positions.size() == 1 and single_touch_active:
			orbit_yaw -= event.relative.x * ROTATE_SPEED
			orbit_pitch += event.relative.y * ROTATE_SPEED
		elif touch_positions.size() >= 2:
			single_touch_active = false
			var keys = touch_positions.keys()
			var t0 = touch_positions[keys[0]]
			var t1 = touch_positions[keys[1]]
			var current_dist = t0.distance_to(t1)
			if pinch_last_distance > 0.0:
				var delta = pinch_last_distance - current_dist
				_zoom(delta * PINCH_SPEED)
			pinch_last_distance = current_dist

func _zoom(delta: float):
	zoom_target = clamp(zoom_target + delta, ZOOM_MIN, ZOOM_MAX)
	if zoom_slider:
		zoom_slider.set_value_no_signal(zoom_target)

func _on_zoom_slider_changed(value: float):
	zoom_target = clamp(value, ZOOM_MIN, ZOOM_MAX)

func _place_dot_on_sphere(dot: Node3D, direction: Vector3, check_foreign: bool = false) -> bool:
	if check_foreign:
		var my_colony = dot_data[dot]["colony"]
		if _is_blocked_by_foreign(direction, my_colony):
			return false
	var dir = direction.normalized()
	dot.position = dir * (SPHERE_RADIUS + DOT_SURFACE_OFFSET)
	var new_basis = Basis()
	new_basis.y = dir
	new_basis.x = new_basis.y.cross(Vector3.FORWARD if abs(dir.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	new_basis.z = new_basis.x.cross(new_basis.y).normalized()
	dot.transform.basis = new_basis
	# Update spatial grid for the new position (only if dot is fully registered)
	if dot_data.has(dot) and dot_cell.has(dot):
		_grid_update_position(dot)
	return true
