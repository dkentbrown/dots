extends RefCounted

# The client's copy of a server-run world (USE_SERVER, or any web build). It carries the same
# member names main.gd's view, HUD, camera and word cloud read from a local WorldSim, so the
# client draws a server world with its drawing code unchanged. It never ticks: the server's
# messages (world_stream.gd) fill it, and apply() flags what changed for _sync_views exactly as
# the sim's own view-change stream does.

const WorldSim = preload("res://world_sim.gd")
const WorldStream = preload("res://world_stream.gd")

var dot_data = {}      # id -> { dir, is_block, is_wall, stack_index, facing, threat_dir, colors }
var speck_data = {}    # id -> { dir }
var mark_data = {}     # id -> { dir, size, color }
var wall_perch = {}
var dots = {}         # = dot_data (set in _init); the HUD only checks it for emptiness
var colony_counts = {}
var block_counts = {}
var soul_pool = {}
var colony_period = {}
var _cached_colony_centers = {}
var _field_colors = []
var _field_specs = []
var _tick_num = 0
var has_world = false  # true once the first snapshot has arrived

var _view_dirty = {}
var _view_gone = []
var _self_profile = {}
var _contact_profiles = []
# A world-less WorldSim used only for its chant tables, so the word cloud picks words the same
# way it does locally (weighted by the server-sent colony profiles).
var _lex

func _init() -> void:
	dots = dot_data
	_lex = WorldSim.new()
	_lex._build_chant_lexicon()
	_lex._build_chant_meanings()

func apply(msg: Dictionary) -> void:
	if msg.get("kind") == "snapshot":
		# A fresh world (first join or a reconnect): drop everything shown so far.
		for table in [dot_data, speck_data, mark_data]:
			for id in table:
				_view_gone.append(id)
			table.clear()
		_view_dirty.clear()
		_field_colors = msg.get("field_colors", [])
		_field_specs = msg.get("field_specs", [])
		has_world = true
	for id in msg.get("gone", PackedInt64Array()):
		dot_data.erase(id)
		speck_data.erase(id)
		mark_data.erase(id)
		_view_dirty.erase(id)
		_view_gone.append(id)
	_apply_state(msg.get("state", {}))
	_apply_entities(msg.get("entities", {}))

func _apply_state(s: Dictionary) -> void:
	if s.is_empty():
		return
	_tick_num = s["tick"]
	colony_counts = s["counts"]
	block_counts = s["blocks"]
	soul_pool = s["soul"]
	_cached_colony_centers = s["centers"]
	colony_period = s["period"]
	wall_perch.clear()
	for id in s["perch"]:
		wall_perch[id] = true
	_self_profile = s["self_profile"]
	_contact_profiles = s["contact_profiles"]

func _apply_entities(e: Dictionary) -> void:
	if e.is_empty():
		return
	var touched = WorldSim.VIEW_PLACE | WorldSim.VIEW_COLOR
	var d = e["dots"]
	var k = 0  # read position in the extra-vector array
	for i in range(d[0].size()):
		var id = d[0][i]
		var flags = d[2][i]
		var rec = {
			"dir": d[1][i],
			"stack_index": d[3][i],
			"facing": null,
			"colors": [_color_at(d[5], i * 8), _color_at(d[5], i * 8 + 4)],
		}
		if flags & WorldStream.FLAG_BLOCK:
			rec["is_block"] = true
		if flags & WorldStream.FLAG_WALL:
			rec["is_wall"] = true
			rec["threat_dir"] = d[4][k]
			k += 1
		if flags & WorldStream.FLAG_FACING:
			rec["facing"] = d[4][k]
			k += 1
		dot_data[id] = rec
		_view_dirty[id] = touched
	var s = e["specks"]
	for i in range(s[0].size()):
		speck_data[s[0][i]] = { "dir": s[1][i] }
		_view_dirty[s[0][i]] = touched
	var m = e["marks"]
	for i in range(m[0].size()):
		mark_data[m[0][i]] = { "dir": m[1][i], "size": m[2][i], "color": _color_at(m[3], i * 4) }
		_view_dirty[m[0][i]] = touched

func _color_at(bytes: PackedByteArray, at: int) -> Color:
	return Color8(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3])

# --- The WorldSim surface the client reads ---

func take_view_changes() -> Array:
	var out = [_view_dirty, _view_gone]
	_view_dirty = {}
	_view_gone = []
	return out

func _dot_colors(id: int) -> Array:
	return dot_data[id]["colors"]

func _compute_colony_center(colony: int) -> Vector3:
	return _cached_colony_centers.get(colony, Vector3.ZERO)

func _pick_cloud_word(excluded: Dictionary) -> Dictionary:
	# WorldSim._pick_cloud_word with the server's profiles in place of the local colonies'.
	var profile = {}
	var roll = randf()
	if roll < WorldSim.CLOUD_MIX_FAMILIAR:
		profile = _self_profile
	elif roll < WorldSim.CLOUD_MIX_FAMILIAR + WorldSim.CLOUD_MIX_CONTACT:
		if not _contact_profiles.is_empty():
			profile = _contact_profiles.pick_random()
	var i = _lex._sample_meaning(profile, excluded)
	if i < 0:
		return {}
	var meaning = _lex._chant_meanings[i]
	var word = meaning["words"][meaning["next"] % meaning["words"].size()]
	meaning["next"] += 1
	return { "word": word, "meaning": i }
