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
var cluster_by_defender = {}  # defender dot -> cluster reference (O(1) lookup)

# Spatial grid
const GRID_RES = 200
const CELL_STEP = TAU / float(GRID_RES)  # one grid cell width in radians
var spatial_grid = {}  # cell_key (Vector2i) -> array of dots
var dot_cell = {}      # dot -> current cell_key, for incremental grid updates

# Attack
const ATTACK_DETECT_RADIUS = 10  # in grid cells

# Rally banners (dropped on combat contact, friendly-only pull)
const RALLY_RADIUS = 30  # cells; how far a banner pulls reinforcements
const BANNER_TTL = 6     # ticks a banner persists after contact
var rally_banners = []  # [{cell: Vector2i, colony: int, ticks_remaining: int}]

# Per-colony population cap (testing aid)
const MAX_POPULATION_PER_COLONY = 1000
var colony_counts = {}  # colony_id -> current dot count

# Walls / blocks (separate from population)
# Note: "block" is the user-facing term. The is_wall flag and wall_* names are
# load-bearing across the codebase \u2014 will rename later.
const WALL_DEFEND_VALUE = 0.5
const WALL_DECAY_TICKS = 300
const WALL_MESH_SIZE = Vector3(0.031, 0.003, 0.031)  # match cell spacing so adjacent cells tile cleanly (TAU/GRID_RES \u2248 0.0314 at the equator)
const WALL_HEIGHT_STEP = 0.003  # vertical spacing between stacked blocks (== mesh y-size)
var wall_counts = {}  # colony_id -> current wall count
var soul_pool = {}   # colony_id -> accumulated soul units

# Build banners (anchored at a placed block, attracting nearby builders)
const BUILD_BANNER_RADIUS = 15
const BUILD_BANNER_TTL = 6
const BUILD_START_CHANCE = 0.05  # chance a build roll starts a new monument when no banner is in range
const BUILD_AT_BANNER_STACK_PREF = 0.8  # base prob. of stacking when building at a banner (at height 0)
const STACK_HEIGHT_SOFTCAP = 10  # stack pref scales linearly to ~0 at this height
const BUILD_FOOTPRINT_DIST_SQ = 8  # squared torus-cell dist within which a builder counts as at/adjacent to a banner
# Monument size cap. cap = BUILD_MONUMENT_BASE + BUILD_MONUMENT_SCALE * colony_avg_build_cce.
# Snapshotted at founder placement and stored on the banner. Independent of population \u2014
# big colonies just hit the cap faster, small ones may never reach it (banner times out).
const BUILD_MONUMENT_BASE = 10.0
const BUILD_MONUMENT_SCALE = 200.0
var build_banners = []  # [{id, cell, colony, ticks_remaining, wall_cap, wall_count}]
var _next_build_banner_id = 1

# Test mode \u2014 fixed population (suppresses reproduction, seeds 15 dots)
const TEST_MODE = false
const TEST_POPULATION = 15
# Logging \u2014 independent of TEST_MODE so we can log organic runs too
const LOG_ENABLED = true
const LOG_FILE = "res://build_log.txt"
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
# Wall-record variant (see _create_wall): "age", "cce", "colony", plus
#   "is_wall": true, "decay_ticks_remaining": int, "stack_index": int. Its cce is a
#   NEUTRAL copy with action.defend = WALL_DEFEND_VALUE. Walls carry none of
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
		"defend": 0.0,
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
		"defend": 0.0,
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
		_tick_combat_clusters()
		_tick_specks()
		_tick_all_dots()
		_update_hud()

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
		if dot_data[dot].get("is_wall", false):
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
	var p0_walls = wall_counts.get(LOCAL_COLONY, 0)
	var p0_soul = soul_pool.get(LOCAL_COLONY, 0)
	var lines = ["p0: %d (walls: %d, soul: %d)   p1: %d" % [count, p0_walls, p0_soul, p1_count]]
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
		if dot_data[dot].get("is_wall", false):
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
	var target = _find_nearest_foreign_in_radius(my_dir, my_colony, ATTACK_DETECT_RADIUS)
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
	# Drop rally banners for both sides at the contact cell
	var contact_cell = _cell_key(defender.position.normalized())
	_drop_rally_banner(contact_cell, dot_data[attacker]["colony"])
	_drop_rally_banner(contact_cell, dot_data[defender]["colony"])

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

# --- Build (walls) ---

func _execute_build(dot: Node3D):
	var my_colony = dot_data[dot]["colony"]
	var my_dir = dot.position.normalized()
	var my_cell = _cell_key(my_dir)
	# Look for an active, unused build banner within range
	var nearest_banner = _find_eligible_build_banner(dot, my_cell, my_colony)
	if nearest_banner != null:
		var banner_cell = nearest_banner["cell"]
		if _is_at_or_adjacent(my_cell, banner_cell):
			# At the monument \u2014 stack pref decays with current tower height; near-zero by STACK_HEIGHT_SOFTCAP
			var current_height = _count_walls_in_cell(banner_cell, my_colony)
			var height_factor = clamp(1.0 - float(current_height) / float(STACK_HEIGHT_SOFTCAP), 0.0, 1.0)
			var stack_pref = BUILD_AT_BANNER_STACK_PREF * height_factor
			var build_cell = banner_cell if randf() < stack_pref else my_cell
			var reason_str = "stack" if build_cell == banner_cell else "lateral"
			_create_wall(build_cell, my_colony, dot_data[dot]["dot_id"], reason_str)
			nearest_banner["wall_count"] += 1
			if nearest_banner["wall_count"] >= nearest_banner["wall_cap"]:
				if LOG_ENABLED:
					_log("[t%d] banner: id=%d completed at %d/%d walls \u2014 expiring" % [_tick_num, nearest_banner["id"], nearest_banner["wall_count"], nearest_banner["wall_cap"]])
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
	_create_wall(my_cell, my_colony, dot_data[dot]["dot_id"], "founder")
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
		enemy_entry = { "pos": enemy.position.normalized(), "dot": enemy }

	# Speck: nearest speck within radius (linear scan — specks aren't grid-indexed)
	var speck_entry = null
	var best_speck_dist = radius_sq + 1
	for speck in specks:
		var d = _torus_cell_dist_sq(my_cell, _cell_key(speck.position.normalized()))
		if d <= radius_sq and d < best_speck_dist:
			best_speck_dist = d
			speck_entry = { "pos": speck.position.normalized(), "node": speck }

	# Ally: nearest same-colony dot (excluding self and walls)
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
		# its wall_cap was hit must be invisible to lookup for the rest of the tick, or
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

# Intentionally retained dead code (no caller; see DEVNOTES 2026-05-12). Also the only
# place in this file that wraps grid neighbors correctly with (+ GRID_RES) before the
# modulo, so it doubles as the reference seam-wrap idiom.
func _pick_lateral_cell(banner_cell: Vector2i, colony: int) -> Vector2i:
	# Returns a neighbor of banner_cell preferring empty (no same-colony wall) cells.
	# Falls back to a random neighbor if all 8 contain same-colony walls.
	var empty = []
	var all_neighbors = []
	for du in [-1, 0, 1]:
		for dv in [-1, 0, 1]:
			if du == 0 and dv == 0:
				continue
			var nb = Vector2i((banner_cell.x + du + GRID_RES) % GRID_RES, (banner_cell.y + dv + GRID_RES) % GRID_RES)
			all_neighbors.append(nb)
			if _count_walls_in_cell(nb, colony) == 0:
				empty.append(nb)
	if not empty.is_empty():
		return empty[randi() % empty.size()]
	return all_neighbors[randi() % all_neighbors.size()]

func _count_walls_in_cell(cell: Vector2i, colony: int) -> int:
	var n = 0
	if spatial_grid.has(cell):
		for occupant in spatial_grid[cell]:
			if dot_data.has(occupant) and dot_data[occupant].get("is_wall", false) and dot_data[occupant]["colony"] == colony:
				n += 1
	return n

func _create_wall(cell: Vector2i, colony: int, builder_id: int = -1, reason: String = "") -> Node3D:
	# Determine stack index by counting same-colony walls already in this cell
	var stack_index = 0
	if spatial_grid.has(cell):
		for occupant in spatial_grid[cell]:
			if dot_data.has(occupant) and dot_data[occupant].get("is_wall", false):
				stack_index += 1
	if LOG_ENABLED and builder_id >= 0:
		_log("[t%d] wall: builder=%d cell=(%d,%d) reason=%s height=%d" % [_tick_num, builder_id, cell.x, cell.y, reason, stack_index])
	# Refresh decay on existing walls in this cell so active monuments don't crumble
	if spatial_grid.has(cell):
		for occupant in spatial_grid[cell]:
			if dot_data.has(occupant) and dot_data[occupant].get("is_wall", false):
				dot_data[occupant]["decay_ticks_remaining"] = WALL_DECAY_TICKS
	var wall = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = WALL_MESH_SIZE
	wall.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.CYAN
	mat.emission_enabled = true
	mat.emission = Color.CYAN
	mat.emission_energy_multiplier = 0.6
	wall.material_override = mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(wall)
	dots.append(wall)
	var dir = _cell_to_dir(cell)
	dot_data[wall] = {
		"age": 0,
		"cce": _deep_copy_cce(NEUTRAL_CCE),
		"colony": colony,
		"is_wall": true,
		"decay_ticks_remaining": WALL_DECAY_TICKS,
		"stack_index": stack_index,
	}
	# Walls have defend = WALL_DEFEND_VALUE so they fight back via the standard combat formula
	dot_data[wall]["cce"]["action"]["defend"] = WALL_DEFEND_VALUE
	known_colonies[colony] = true
	wall_counts[colony] = wall_counts.get(colony, 0) + 1
	# Place the wall along the surface normal at stack_index * step above the surface
	wall.position = dir * (SPHERE_RADIUS + DOT_SURFACE_OFFSET + stack_index * WALL_HEIGHT_STEP)
	var new_basis = Basis()
	new_basis.y = dir
	new_basis.x = new_basis.y.cross(Vector3.FORWARD if abs(dir.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	new_basis.z = new_basis.x.cross(new_basis.y).normalized()
	wall.transform.basis = new_basis
	_grid_insert(wall, cell)
	_update_dot_color(wall)
	return wall

# --- Build banners ---

func _drop_build_banner(cell: Vector2i, colony: int) -> int:
	var id = _next_build_banner_id
	_next_build_banner_id += 1
	var avg_build = _compute_colony_avg_build_cce(colony)
	var wall_cap = int(round(BUILD_MONUMENT_BASE + BUILD_MONUMENT_SCALE * avg_build))
	build_banners.append({
		"id": id,
		"cell": cell,
		"colony": colony,
		"ticks_remaining": BUILD_BANNER_TTL,
		"wall_cap": wall_cap,
		"wall_count": 0,
	})
	if LOG_ENABLED:
		_log("[t%d] banner: id=%d cell=(%d,%d) cap=%d (avg_build=%.3f)" % [_tick_num, id, cell.x, cell.y, wall_cap, avg_build])
	return id

func _compute_colony_avg_build_cce(colony: int) -> float:
	var total = 0.0
	var count = 0
	for dot in dots:
		if dot_data[dot]["colony"] != colony:
			continue
		if dot_data[dot].get("is_wall", false):
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

func _tick_combat_clusters():
	var to_remove_clusters = []
	var to_delete = {}
	var to_advance = []
	for cluster in combat_clusters:
		cluster["ticks_remaining"] -= 1
		if cluster["ticks_remaining"] <= 0:
			# Track which defenders already have a winning attacker claiming their cell
			var cell_claimed_by = {}
			for pair in cluster["pairs"]:
				var attacker = pair["attacker"]
				var defender = pair["defender"]
				# dot_data.has() is sufficient \u2014 _remove_dot erases it before queue_free
				if not dot_data.has(attacker) or not dot_data.has(defender):
					continue
				if to_delete.has(attacker) or to_delete.has(defender):
					continue
				var a_power = dot_data[attacker]["cce"]["action"].get("attack", 0.0) + dot_data[attacker]["cce"]["action"].get("defend", 0.0)
				var d_power = dot_data[defender]["cce"]["action"].get("attack", 0.0) + dot_data[defender]["cce"]["action"].get("defend", 0.0)
				var defender_is_wall = dot_data[defender].get("is_wall", false)
				if a_power >= d_power:
					to_delete[defender] = true
					if defender_is_wall:
						# Attacker advances only if the cell will be empty after this wall is removed
						var wall_cell = dot_cell.get(defender)
						var cell_will_be_empty = true
						if wall_cell != null and spatial_grid.has(wall_cell):
							for occupant in spatial_grid[wall_cell]:
								if occupant != defender and not to_delete.has(occupant):
									cell_will_be_empty = false
									break
						if cell_will_be_empty and not cell_claimed_by.has(defender):
							cell_claimed_by[defender] = attacker
							to_advance.append({"winner": attacker, "target_dir": defender.position.normalized()})
					else:
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
		combat_clusters.erase(cluster)
	dots.erase(dot)
	var removed_colony = dot_data[dot]["colony"]
	if dot_data[dot].get("is_wall", false):
		wall_counts[removed_colony] = max(0, wall_counts.get(removed_colony, 0) - 1)
	else:
		colony_counts[removed_colony] = max(0, colony_counts.get(removed_colony, 0) - 1)
	dot_data.erase(dot)
	combat_locked.erase(dot)
	if dot == player_dot:
		# Fallback may resolve to a wall or an enemy-colony dot. Harmless today because
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
					if dot_data[occupant].get("is_wall", false):
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
		if dot_data[dot].get("is_wall", false):
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
