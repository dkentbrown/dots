extends Control

# The player's chant input (replaces the old Chant button + text box): rows of slowly drifting
# words across the bottom of the screen, with the chant line just above them.
#   tap a word         -> it floats up into the line
#   double-tap         -> the word just added becomes "very <word>"
#   swipe down a word  -> it joins the line as "never <word>"
#   tap a word in line -> it goes back
# The line casts CAST_DELAY seconds after its last change, brightening as the moment nears, then
# flies into your colony. Rows pause while a finger is down. main.gd supplies the words
# (pick_word) and the colony's screen point (cast_target) and receives the cast (chant_cast);
# this script knows nothing about CCE.

signal chant_cast(text: String)

const BOTTOM_MARGIN = 28.0                # clear of the home indicator
const LINE_HEIGHT = 44.0
const ROW_HEIGHT = 46.0
const ROW_SPEEDS = [14.0, -20.0, 17.0]    # px/s in base units; the sign is the drift direction
const WORD_GAP = 30.0
const EDGE_FADE = 48.0
const WORD_FONT_SIZE = 17
const LINE_FONT_SIZE = 19
const LINE_GAP = 10.0
const LINE_MAX_WORDS = 5
const LINE_DIM = 0.55                     # line alpha right after a change; reaches 1.0 at the cast
const CAST_DELAY = 4.0
const CAST_SECONDS = 0.9
const DOUBLE_TAP_SECONDS = 0.3
const DOUBLE_TAP_SLOP = 24.0
const SWIPE_DOWN_MIN = 28.0
const TAP_SLOP = 12.0
const HIT_PAD = 6.0

var pick_word: Callable     # (excluded: Dictionary) -> { "word": String, "meaning": int } or {}
var cast_target: Callable   # () -> your colony's screen point (Vector2), or null when hidden

var _rows = []              # per row: Array of { "label", "word", "meaning", "width" }
var _line = []              # Array of { "label", "word", "meaning", "mod", "tween" }
var _prefilled = false
var _held = false
var _press_pos = Vector2.ZERO
var _last_add_time = -1.0
var _last_add_pos = Vector2.ZERO
var _cast_timer = 0.0

func _ready() -> void:
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -(BOTTOM_MARGIN + LINE_HEIGHT + ROW_HEIGHT * ROW_SPEEDS.size())
	offset_bottom = -BOTTOM_MARGIN
	mouse_filter = MOUSE_FILTER_STOP
	for i in range(ROW_SPEEDS.size()):
		_rows.append([])

func _process(delta: float) -> void:
	if not _prefilled and size.x > 0.0:
		_prefill()
	if not _held:
		for i in range(_rows.size()):
			_drift_row(i, delta)
	_tick_line(delta)

# --- Cloud rows ---

func _row_y(i: int) -> float:
	return LINE_HEIGHT + i * ROW_HEIGHT

func _make_label(text: String, font_size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	label.size = label.get_combined_minimum_size()
	label.pivot_offset = label.size * 0.5
	return label

func _on_screen_meanings() -> Dictionary:
	# One word per meaning on screen at a time — rows and line both count.
	var out = {}
	for row in _rows:
		for e in row:
			out[e["meaning"]] = true
	for item in _line:
		out[item["meaning"]] = true
	return out

func _spawn_word(i: int):
	# A new word in row i, positioned at x = 0; the caller places it. null if none is available.
	if not pick_word.is_valid():
		return null
	var pick = pick_word.call(_on_screen_meanings())
	if pick.is_empty():
		return null
	var label = _make_label(pick["word"], WORD_FONT_SIZE)
	label.position = Vector2(0.0, _row_y(i) + (ROW_HEIGHT - label.size.y) * 0.5)
	label.modulate.a = 0.0
	var entry = { "label": label, "word": pick["word"], "meaning": pick["meaning"], "width": label.size.x }
	_rows[i].append(entry)
	return entry

func _prefill() -> void:
	# Fill every row edge to edge on the first frame the band has a size, so the cloud doesn't
	# start empty and trickle in.
	_prefilled = true
	for i in range(_rows.size()):
		var x = randf_range(-40.0, 0.0)
		while x < size.x:
			var e = _spawn_word(i)
			if e == null:
				break
			e["label"].position.x = x
			x += e["width"] + WORD_GAP

func _entering_word(i: int):
	# The word nearest the edge new words enter from, or null for an empty row.
	var best = null
	for e in _rows[i]:
		if best == null:
			best = e
		elif ROW_SPEEDS[i] > 0.0 and e["label"].position.x < best["label"].position.x:
			best = e
		elif ROW_SPEEDS[i] < 0.0 and e["label"].position.x + e["width"] > best["label"].position.x + best["width"]:
			best = e
	return best

func _feed_row(i: int) -> void:
	# Spawn just outside the entering edge whenever a gap of WORD_GAP has opened up there.
	for _guard in range(8):
		var edge = _entering_word(i)
		if ROW_SPEEDS[i] > 0.0:
			var free_left = edge["label"].position.x if edge != null else size.x
			if free_left < WORD_GAP:
				return
			var e = _spawn_word(i)
			if e == null:
				return
			e["label"].position.x = (free_left - WORD_GAP - e["width"]) if edge != null else -e["width"]
		else:
			var free_right = (edge["label"].position.x + edge["width"]) if edge != null else 0.0
			if size.x - free_right < WORD_GAP:
				return
			var e = _spawn_word(i)
			if e == null:
				return
			e["label"].position.x = (free_right + WORD_GAP) if edge != null else size.x

func _drift_row(i: int, delta: float) -> void:
	var speed = ROW_SPEEDS[i]
	var row = _rows[i]
	for e in row:
		e["label"].position.x += speed * delta
	for e in row.duplicate():
		var x = e["label"].position.x
		if (speed > 0.0 and x > size.x) or (speed < 0.0 and x + e["width"] < 0.0):
			e["label"].queue_free()
			row.erase(e)
	_feed_row(i)
	for e in row:
		var cx = e["label"].position.x + e["width"] * 0.5
		e["label"].modulate.a = clamp(min(cx, size.x - cx) / EDGE_FADE, 0.0, 1.0)

func _cloud_entry_at(p: Vector2):
	for i in range(_rows.size()):
		if p.y < _row_y(i) or p.y >= _row_y(i) + ROW_HEIGHT:
			continue
		for e in _rows[i]:
			var x = e["label"].position.x
			if p.x >= x - HIT_PAD and p.x <= x + e["width"] + HIT_PAD:
				return e
	return null

# --- Input ---

func _gui_input(event: InputEvent) -> void:
	# Mouse events cover touch too (Godot emulates the mouse from touch by default).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_held = true
			_press_pos = event.position
		else:
			_held = false
			_on_release(_press_pos, event.position)
		accept_event()

func _on_release(start: Vector2, end: Vector2) -> void:
	var moved = end - start
	var line_hit = _line_entry_at(start)
	if line_hit != null:
		if moved.length() <= TAP_SLOP:
			_return_from_line(line_hit)
		return
	if moved.length() <= TAP_SLOP:
		var now = Time.get_ticks_msec() / 1000.0
		# A quick second tap where a word was just added makes it "very". The first word has
		# already floated up, so the second tap would otherwise land on whatever drifted in.
		if now - _last_add_time <= DOUBLE_TAP_SECONDS and start.distance_to(_last_add_pos) <= DOUBLE_TAP_SLOP and not _line.is_empty():
			_intensify(_line[_line.size() - 1])
			_last_add_time = -1.0
			return
		var hit = _cloud_entry_at(start)
		if hit != null and _add_to_line(hit, ""):
			_last_add_time = now
			_last_add_pos = start
	elif moved.y >= SWIPE_DOWN_MIN and abs(moved.y) > abs(moved.x):
		var hit = _cloud_entry_at(start)
		if hit != null:
			_add_to_line(hit, "never")

# --- Chant line ---

func _line_entry_at(p: Vector2):
	if p.y < 0.0 or p.y >= LINE_HEIGHT:
		return null
	for item in _line:
		var r = Rect2(item["label"].position, item["label"].size).grow(HIT_PAD)
		if r.has_point(p):
			return item
	return null

func _add_to_line(entry: Dictionary, mod: String) -> bool:
	if _line.size() >= LINE_MAX_WORDS:
		return false
	for row in _rows:
		row.erase(entry)
	var label = entry["label"]
	label.add_theme_font_size_override("font_size", LINE_FONT_SIZE)
	var item = { "label": label, "word": entry["word"], "meaning": entry["meaning"], "mod": mod, "tween": null }
	_line.append(item)
	_set_line_text(item)
	_layout_line()
	_cast_timer = CAST_DELAY
	return true

func _intensify(item: Dictionary) -> void:
	if item["mod"] != "":
		return
	item["mod"] = "very"
	_set_line_text(item)
	_layout_line()
	_cast_timer = CAST_DELAY

func _set_line_text(item: Dictionary) -> void:
	var label = item["label"]
	label.text = item["word"] if item["mod"] == "" else item["mod"] + " " + item["word"]
	label.size = label.get_combined_minimum_size()
	label.pivot_offset = label.size * 0.5

func _kill_tween(item: Dictionary) -> void:
	if item["tween"] != null and item["tween"].is_valid():
		item["tween"].kill()
	item["tween"] = null

func _layout_line() -> void:
	# Centre the line's words and glide each one to its slot.
	var total = 0.0
	for item in _line:
		total += item["label"].size.x
	total += LINE_GAP * max(_line.size() - 1, 0)
	var x = (size.x - total) * 0.5
	for item in _line:
		var label = item["label"]
		var target = Vector2(x, (LINE_HEIGHT - label.size.y) * 0.5)
		_kill_tween(item)
		var tw = create_tween()
		tw.tween_property(label, "position", target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		item["tween"] = tw
		x += label.size.x + LINE_GAP

func _return_from_line(item: Dictionary) -> void:
	_line.erase(item)
	_kill_tween(item)
	var label = item["label"]
	var tw = create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y + 30.0, 0.3)
	tw.tween_property(label, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(label.queue_free)
	_layout_line()
	_cast_timer = CAST_DELAY

func _tick_line(delta: float) -> void:
	if _line.is_empty():
		return
	if not _held:
		_cast_timer -= delta
	var t = clamp(1.0 - _cast_timer / CAST_DELAY, 0.0, 1.0)
	for item in _line:
		item["label"].modulate.a = lerp(LINE_DIM, 1.0, t)
	if _cast_timer <= 0.0:
		_cast()

func _cast() -> void:
	var parts = []
	for item in _line:
		parts.append(item["label"].text)
	var target = cast_target.call() if cast_target.is_valid() else null
	for item in _line:
		var label = item["label"]
		_kill_tween(item)
		var tw = create_tween().set_parallel(true)
		if target != null:
			var local = target - global_position - label.size * 0.5
			tw.tween_property(label, "position", local, CAST_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw.tween_property(label, "scale", Vector2(0.4, 0.4), CAST_SECONDS)
		else:
			tw.tween_property(label, "position:y", label.position.y - 80.0, CAST_SECONDS)
		tw.tween_property(label, "modulate:a", 0.0, CAST_SECONDS)
		tw.chain().tween_callback(label.queue_free)
	_line.clear()
	chant_cast.emit(" ".join(parts))
