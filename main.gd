extends Node3D

# The CLIENT (separation stage 4): camera, input, sun, HUD, debug UI, word cloud and all mesh
# drawing. The world itself — every dot, block, speck, mark, colony and rule — lives in
# world_sim.gd (`sim`), a node-free script a headless server can run unchanged. The client
# ticks it on a timer and draws what it flags (_sync_views).
const WorldSim = preload("res://world_sim.gd")
var sim

const ZOOM_MIN = WorldSim.SPHERE_RADIUS + 0.12 / WorldSim.WORLD_SCALE
const ZOOM_MAX = 6.0
const ZOOM_SPEED = 0.08
const PINCH_SPEED = 0.004
const ZOOM_SMOOTH = 8.0
const ROTATE_SPEED = 0.005

# Sun: the DirectionalLight3D orbits the globe on WALL-CLOCK time, so the day/night phase carries
# across sessions (and, later, players) instead of resetting at launch. One revolution per
# SUN_DAY_SECONDS; SUN_FAST_DAY swaps in a SUN_TEST_DAY_SECONDS day for testing. The sun rides
# SUN_DECLINATION_DEG above the equator (Earth's tilt — a solstice day). That also puts it just
# clear of the globe's limb (asin(1/3) ≈ 19.5° at the default zoom of 3.0) when you look at the
# night side, so it can be seen behind the planet. Purely visual — the simulation ignores it.
const SUN_DAY_SECONDS = 86400.0
const SUN_TEST_DAY_SECONDS = 20.0
const SUN_FAST_DAY = true
const SUN_DECLINATION_DEG = 23.4

const TICK_SPEED = 1.0
var tick_timer = 0.0

const USE_SERVER = false
const WordCloud = preload("res://word_cloud.gd")
# entity id -> its MeshInstance3D (dots, blocks, specks, marks). Only the view section touches meshes;
# the simulation addresses everything by id.
var views = {}
var word_cloud = null

@onready var camera = $Camera3D
@onready var sun = $DirectionalLight3D
@onready var dev_bar = $UI/DevBar
@onready var hud = $UI/HUD
@onready var zoom_slider = $UI/ZoomSlider

# Debug overlay: the stats HUD, dev chant bar and zoom slider. Hidden by default so the
# player-facing UI is just the word cloud (bible §4); backtick (`) toggles it at runtime.
const DEBUG_UI_DEFAULT = false
var _debug_ui = DEBUG_UI_DEFAULT

var zoom_target = 3.0
var zoom_distance = 3.0
# Free (trackball) orbit: the camera's orientation, rotated about its OWN axes by drag. No
# pitch limit and no world-up — the view rolls straight over the poles. The camera sits on
# this basis's +z at zoom_distance, looking at the origin. Identity = the old yaw 0 / pitch 0.
var orbit_basis = Basis.IDENTITY
var is_orbiting = false
var touch_positions = {}
var pinch_last_distance = 0.0
var single_touch_active = false
var single_touch_index = -1

func _ready():
	sim = WorldSim.new()
	sim.setup()
	_focus_on_colony()
	_update_camera()
	_update_hud()
	dev_bar.placeholder_text = "dev chant..."
	dev_bar.text_submitted.connect(_on_dev_chant)
	zoom_slider.value = zoom_target
	zoom_slider.value_changed.connect(_on_zoom_slider_changed)
	_set_debug_ui(_debug_ui)
	word_cloud = WordCloud.new()
	word_cloud.pick_word = sim._pick_cloud_word
	word_cloud.cast_target = _colony_screen_point
	word_cloud.chant_cast.connect(_process_input)
	$UI.add_child(word_cloud)

func _set_debug_ui(on: bool) -> void:
	_debug_ui = on
	hud.visible = on
	dev_bar.visible = on
	zoom_slider.visible = on

func _on_dev_chant(text: String):
	_process_input(text)
	dev_bar.clear()

func _process(delta):
	zoom_distance = lerp(zoom_distance, zoom_target, ZOOM_SMOOTH * delta)
	zoom_distance = max(zoom_distance, ZOOM_MIN)
	_update_camera()
	_update_sun()
	tick_timer += delta
	if tick_timer >= TICK_SPEED:
		tick_timer = 0.0
		sim.tick()
		_update_hud()
	_sync_views()

func _update_hud():
	if sim.dots.is_empty():
		hud.text = "dots: 0"
		return
	if WorldSim.TEST_FIELD:
		var field_lines = ["t%d   (combat lean @ t%d)" % [sim._tick_num, WorldSim.AUTOCHANT_COMBAT_TICK]]
		for i in range(sim._field_specs.size()):
			var spec = sim._field_specs[i]
			var color_name = sim._field_colors[i]["name"] if i < sim._field_colors.size() else "?"
			# Tag the generalists with their combat role; uppercase once it's actually active.
			var tag = ""
			var role = spec.get("combat_role", "")
			if role != "":
				tag = ("[%s]" % role.to_upper()) if sim._tick_num >= WorldSim.AUTOCHANT_COMBAT_TICK else ("[%s@%d]" % [role, WorldSim.AUTOCHANT_COMBAT_TICK])
			field_lines.append("c%d %-11s %-7s pop %4d blk %4d soul %4d %s" % [
				i, spec["name"], color_name,
				sim.colony_counts.get(i, 0), sim.block_counts.get(i, 0), sim.soul_pool.get(i, 0), tag
			])
		hud.text = "\n".join(field_lines)
		return
	var totals = {}
	var count = 0
	for dot in sim.dots:
		if sim.dot_data[dot]["colony"] != WorldSim.LOCAL_COLONY:
			continue
		if sim.dot_data[dot].get("is_block", false):
			continue
		count += 1
		var cce = sim.dot_data[dot]["cce"]
		for key in cce["motion"]:
			totals[key] = totals.get(key, 0.0) + cce["motion"][key]
		for key in cce["action"]:
			totals[key] = totals.get(key, 0.0) + cce["action"][key]
	if count == 0:
		hud.text = "p0: 0 (wiped out)"
		return
	var sorted_keys = totals.keys()
	sorted_keys.sort_custom(func(a, b): return totals[a] > totals[b])
	var p1_count = sim.colony_counts.get(WorldSim.ENEMY_COLONY, 0)
	var p0_blocks = sim.block_counts.get(WorldSim.LOCAL_COLONY, 0)
	var p0_soul = sim.soul_pool.get(WorldSim.LOCAL_COLONY, 0)
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
		sim._process_chant_locally(text)
	_update_hud()

func _send_chant_to_server(_text: String):
	pass

func _colony_screen_point():
	# Where a cast chant flies: your colony's centre on screen, or null when it's on the far side
	# of the globe (or gone), in which case the words just rise and fade.
	if sim.colony_counts.get(WorldSim.LOCAL_COLONY, 0) <= 0 or not sim._cached_colony_centers.has(WorldSim.LOCAL_COLONY):
		return null
	var p = sim._cached_colony_centers[WorldSim.LOCAL_COLONY] * WorldSim.SPHERE_RADIUS
	if p.dot(camera.global_position) <= WorldSim.SPHERE_RADIUS * WorldSim.SPHERE_RADIUS:
		return null
	return camera.unproject_position(p)

# --- View: meshes follow the simulation's data (separation stages 3-4) ---

func _sync_views() -> void:
	# Apply what the simulation flagged since last frame: free the removed, build the new, then
	# move / recolour the flagged. Cheap when nothing changed.
	var changes = sim.take_view_changes()
	var dirty = changes[0]
	var gone = changes[1]
	for id in gone:
		if views.has(id):
			views[id].queue_free()
			views.erase(id)
	for id in dirty:
		var what = dirty[id]
		if not views.has(id):
			var mesh = _view_build(id)
			if mesh == null:
				continue
			views[id] = mesh
			what = WorldSim.VIEW_PLACE | WorldSim.VIEW_COLOR
		if what & WorldSim.VIEW_PLACE:
			_view_place(id)
		if what & WorldSim.VIEW_COLOR:
			_view_color(id)

func _view_build(id: int):
	# A mesh for whatever kind of entity `id` is, or null if it no longer exists. Colour and
	# placement are applied separately (_view_color, _view_place).
	var size: Vector3
	var energy: float
	if sim.dot_data.has(id):
		if sim.dot_data[id].get("is_wall", false):
			size = WorldSim.WALL_MESH_SIZE
			energy = 0.6
		elif sim.dot_data[id].get("is_block", false):
			size = WorldSim.BLOCK_MESH_SIZE
			energy = 0.6
		else:
			size = Vector3(0.015, 0.006, 0.015) / WorldSim.WORLD_SCALE
			energy = 0.8
	elif sim.speck_data.has(id):
		size = Vector3(0.008, 0.003, 0.008) / WorldSim.WORLD_SCALE
		energy = 1.2
	elif sim.mark_data.has(id):
		var s = sim.mark_data[id]["size"]
		size = Vector3(s, 0.001 / WorldSim.WORLD_SCALE, s)
		energy = 0.4
	else:
		return null
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission_energy_multiplier = energy
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)
	return mesh

func _view_place(id: int) -> void:
	var mesh = views[id]
	if sim.dot_data.has(id):
		var d = sim.dot_data[id]
		var dir = d["dir"]
		if d.get("is_wall", false):
			mesh.position = dir * (WorldSim.SPHERE_RADIUS + WorldSim.DOT_SURFACE_OFFSET)
			mesh.transform.basis = _wall_basis(dir, d["threat_dir"])
		elif d.get("is_block", false):
			# Stacked along the surface normal, stack_index steps above the surface.
			mesh.position = dir * (WorldSim.SPHERE_RADIUS + WorldSim.DOT_SURFACE_OFFSET + d["stack_index"] * WorldSim.BLOCK_HEIGHT_STEP)
			mesh.transform.basis = _surface_basis(dir)
		else:
			# A perched waller sits one block-height up, on top of its wall segment.
			var lift = WorldSim.BLOCK_HEIGHT_STEP if sim.wall_perch.has(id) else 0.0
			mesh.position = dir * (WorldSim.SPHERE_RADIUS + WorldSim.DOT_SURFACE_OFFSET + lift)
			mesh.transform.basis = _surface_basis(dir) if d.get("facing") == null else _facing_basis(dir, d["facing"])
	elif sim.speck_data.has(id):
		mesh.position = sim.speck_data[id]["dir"] * (WorldSim.SPHERE_RADIUS + WorldSim.DOT_SURFACE_OFFSET)
	elif sim.mark_data.has(id):
		var dir = sim.mark_data[id]["dir"]
		# Straddle the surface rather than float above it: centred exactly ON the sphere, so the
		# tile is half embedded and sits 0.0005 proud — it reads as paint, not as a tile hovering
		# over the ground. (It previously sat at +0.00375, over 3x its own 0.001 thickness above
		# the surface.) Marks are the one thing that must be IN the sphere, not on top of it, so
		# they deliberately do not use DOT_SURFACE_OFFSET the way dots and blocks do.
		# Curvature is negligible at this size: a 0.014 tile's corners rise ~5e-5 off the tangent
		# plane, a tenth of the protrusion, so the whole quad stays seated.
		mesh.position = dir * WorldSim.SPHERE_RADIUS
		mesh.transform.basis = _surface_basis(dir)

func _view_color(id: int) -> void:
	var albedo: Color
	var emission: Color
	if sim.dot_data.has(id):
		var c = sim._dot_colors(id)
		albedo = c[0]
		emission = c[1]
	elif sim.speck_data.has(id):
		albedo = Color(1.0, 0.85, 0.2)
		emission = albedo
	elif sim.mark_data.has(id):
		albedo = sim.mark_data[id]["color"]
		emission = albedo
	else:
		return
	var mat = views[id].material_override as StandardMaterial3D
	mat.albedo_color = albedo
	mat.emission = emission

func _surface_basis(dir: Vector3) -> Basis:
	# y = the surface normal; x/z span the tangent plane against a fixed world reference axis.
	var b = Basis()
	b.y = dir
	b.x = b.y.cross(Vector3.FORWARD if abs(dir.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	b.z = b.x.cross(b.y).normalized()
	return b

func _facing_basis(dir: Vector3, target_dir: Vector3) -> Basis:
	# Surface frame turned so z points along the surface toward target_dir (_face_dir).
	var toward = target_dir - dir
	if toward.length_squared() < WorldSim.PARALLEL_EPSILON:
		return _surface_basis(dir)
	var tangent = dir.cross(toward)
	if tangent.length_squared() < WorldSim.PARALLEL_EPSILON:
		return _surface_basis(dir)
	tangent = tangent.cross(dir).normalized()  # tangent aimed at the target along the surface
	var b = Basis()
	b.y = dir
	b.z = tangent
	b.x = b.y.cross(b.z).normalized()
	b.z = b.x.cross(b.y).normalized()
	return b

func _wall_basis(dir: Vector3, threat_dir: Vector3) -> Basis:
	# Same frame construction as _surface_basis, but the reference vector is the threat
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
	return new_basis


func _focus_on_colony():
	var center = sim._compute_colony_center(WorldSim.LOCAL_COLONY)
	if center.length_squared() < WorldSim.PARALLEL_EPSILON:
		return
	var dir = center.normalized()
	# Face the colony with world-up as the starting "up" (same framing as before); after this,
	# drag is free to roll the view anywhere.
	var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	orbit_basis = Basis.looking_at(-dir, up)

func _orbit(relative: Vector2) -> void:
	# Drag rotates about the camera's local up (horizontal drag) and local right (vertical
	# drag). Same drag directions as the old yaw/pitch orbit; orthonormalized against drift.
	var yaw = Basis(Vector3.UP, -relative.x * ROTATE_SPEED)
	var pitch = Basis(Vector3.RIGHT, -relative.y * ROTATE_SPEED)
	orbit_basis = (orbit_basis * yaw * pitch).orthonormalized()

func _update_camera():
	camera.transform.basis = orbit_basis
	camera.position = orbit_basis.z * zoom_distance

func _update_sun() -> void:
	var day = SUN_TEST_DAY_SECONDS if SUN_FAST_DAY else SUN_DAY_SECONDS
	var phase = fmod(Time.get_unix_time_from_system(), day) / day * TAU
	var decl = deg_to_rad(SUN_DECLINATION_DEG)
	var to_sun = Vector3(cos(decl) * sin(phase), sin(decl), cos(decl) * cos(phase))
	# A DirectionalLight3D shines along its -Z, so aim -Z from the sun toward the globe.
	sun.transform.basis = Basis.looking_at(-to_sun, Vector3.UP)

# --- Input ---

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var typing = get_viewport().gui_get_focus_owner() is LineEdit
		if event.keycode == KEY_QUOTELEFT and not typing:
			_set_debug_ui(not _debug_ui)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_orbiting = event.pressed
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(-ZOOM_SPEED)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(ZOOM_SPEED)

	if event is InputEventMouseMotion and is_orbiting:
		_orbit(event.relative)

	if event is InputEventScreenTouch:
		if event.pressed:
			touch_positions[event.index] = event.position
			# A finger that lands on the word cloud is choosing words, not rotating the globe.
			if touch_positions.size() == 1 and not (word_cloud and word_cloud.get_global_rect().has_point(event.position)):
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
			_orbit(event.relative)
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
