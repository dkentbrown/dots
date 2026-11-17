extends Node

# Headless world server (separation stage 6): ticks world_sim.gd with no rendering, camera or UI;
# the simulation writes telemetry exactly as it does under the client. The seed of the
# multiplayer server. Run it without a window:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> res://server.tscn -- [--ticks N] [--fast] [--listen PORT] [--tick-seconds S]
#     --ticks N          stop at world tick N (default: run until killed); a resumed world counts
#                        from its saved tick
#     --fast             tick every frame instead of every TICK_SECONDS — pure simulation speed
#     --listen PORT      accept WebSocket clients on 127.0.0.1:PORT (a Cloudflare Tunnel or a
#                        local client connects there) and stream the world to them
#     --tick-seconds S   seconds per world tick (default TICK_SECONDS)
#     --idle-tick-seconds S   seconds per world tick while no client is connected (default: same
#                        as --tick-seconds). The world slows to a crawl when nobody is watching
#                        (bible §11.2's passive ticks, world-wide), so a small burstable host
#                        banks CPU while idle and spends it while someone plays.
#     --save PATH        keep the world in PATH: resume from it on start (or from PATH.prev if
#                        PATH is unreadable), and save it every --save-seconds. To stop with a
#                        last save, create PATH.stop: the server saves and quits within a second
#                        (a signal can't do it; see _check_stop_request). A save this build can't
#                        read is moved aside to PATH.rejected-<time>, and a fresh world starts.
#                        Without --save nothing is saved, as before.
#     --save-seconds S   seconds between saves (default SAVE_SECONDS)
#     --fresh            ignore the save and start a fresh world (the old save is overwritten at
#                        the first save, after being kept as PATH.prev)
# Each tick prints one line: tick, live dots, blocks, specks, clients, and that tick's cost in ms.
# Chants can be injected while it runs through res://chant.json, as with the client.
#
# Networking (world_stream.gd): a client that connects gets a full snapshot, then each tick's
# changes. Clients send {"chant": text} (applied to LOCAL_COLONY — one player for now) and
# {"active": bool} (window focus); LOCAL_COLONY is on the active clock while any connected
# client is active, and passive when none is.

const WorldSim = preload("res://world_sim.gd")
const WorldStream = preload("res://world_stream.gd")
const TICK_SECONDS = 1.0   # the client's TICK_SPEED: one world tick per second
const OUTBOUND_BUFFER_BYTES = 32 * 1024 * 1024   # a slow client can fall a few snapshots behind
const INBOUND_BUFFER_BYTES = 64 * 1024

var sim
var _max_ticks = -1
var _fast = false
var _tick_seconds = TICK_SECONDS
var _idle_tick_seconds = -1.0   # < 0: no idle slow-down
const SAVE_SECONDS = 60.0
var _save_path = ""   # empty: no saving
var _save_seconds = SAVE_SECONDS
var _last_save_ms = 0
var _last_stop_check_ms = 0
var _ticks_run = 0   # ticks run since this process started (a resumed world starts past 0)
var _timer = 0.0
var _total_ms = 0.0
var _tcp: TCPServer = null
var _peers = []   # { "ws": WebSocketPeer, "open": bool, "active": bool }
var _msg_id = 0

func _ready() -> void:
	var port = 0
	var fresh = false
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--ticks" and i + 1 < args.size():
			_max_ticks = int(args[i + 1])
		elif args[i] == "--fast":
			_fast = true
		elif args[i] == "--listen" and i + 1 < args.size():
			port = int(args[i + 1])
		elif args[i] == "--tick-seconds" and i + 1 < args.size():
			_tick_seconds = float(args[i + 1])
		elif args[i] == "--idle-tick-seconds" and i + 1 < args.size():
			_idle_tick_seconds = float(args[i + 1])
		elif args[i] == "--save" and i + 1 < args.size():
			_save_path = args[i + 1]
		elif args[i] == "--save-seconds" and i + 1 < args.size():
			_save_seconds = float(args[i + 1])
		elif args[i] == "--fresh":
			fresh = true
	sim = WorldSim.new()
	var resumed = false
	if _save_path != "" and FileAccess.file_exists(_save_path + ".stop"):
		DirAccess.remove_absolute(_save_path + ".stop")   # left over from a stop that never finished
	if _save_path != "" and not fresh:
		resumed = _resume()
	if not resumed:
		sim = WorldSim.new()   # a refused save leaves no trace, but start from a clean object anyway
		sim.setup()
	_last_save_ms = Time.get_ticks_msec()
	# Mark the run as headless in telemetry, right after its run_start record.
	sim._telemetry({ "type": "headless", "max_ticks": _max_ticks, "fast": _fast, "listen": port, "tick_seconds": _tick_seconds, "idle_tick_seconds": _idle_tick_seconds })
	if port > 0:
		_tcp = TCPServer.new()
		var err = _tcp.listen(port, "127.0.0.1")
		if err != OK:
			push_error("[server] could not listen on port %d (error %d)" % [port, err])
			_tcp = null
		else:
			# Nobody is watching until a client connects.
			sim.set_colony_active(WorldSim.LOCAL_COLONY, false)
	var idle_note = (" (%.0f s with nobody connected)" % _idle_tick_seconds) if _idle_tick_seconds > 0 else ""
	var origin = ("resumed at t%d" % sim._tick_num) if resumed else "fresh"
	var save_note = (", saving to %s every %.0f s" % [_save_path, _save_seconds]) if _save_path != "" else ""
	print("[server] world ready (%s): %d colonies, %d entities, %s%s%s%s" % [origin, sim.known_colonies.size(), sim.dots.size(), "fast" if _fast else "%.1f s ticks" % _tick_seconds, idle_note, (", listening on 127.0.0.1:%d" % port) if _tcp else "", save_note])

func _process(delta: float) -> void:
	_check_stop_request()
	_poll_clients()
	_timer += delta
	# With nobody connected, wait the idle interval instead. A client joining mid-wait makes
	# the shorter interval apply at once, so the world wakes on the next frame.
	var interval = _tick_seconds
	if _idle_tick_seconds > 0 and _open_count() == 0:
		interval = _idle_tick_seconds
	if not _fast and _timer < interval:
		return
	_timer = 0.0
	var t0 = Time.get_ticks_usec()
	sim.tick()
	# Hand this tick's view changes to the clients; with none connected, just drop them so they
	# don't pile up.
	var changes = sim.take_view_changes()
	if _open_count() > 0:
		_broadcast(WorldStream.tick_message(sim, changes))
	var ms = (Time.get_ticks_usec() - t0) / 1000.0
	_total_ms += ms
	_ticks_run += 1
	var live = 0
	for c in sim.colony_counts:
		live += sim.colony_counts[c]
	var blocks = 0
	for c in sim.block_counts:
		blocks += sim.block_counts[c]
	print("[server] t%d  live %d  blocks %d  specks %d  clients %d  tick %.1f ms" % [sim._tick_num, live, blocks, sim.specks.size(), _open_count(), ms])
	if _save_path != "" and Time.get_ticks_msec() - _last_save_ms >= _save_seconds * 1000.0:
		_save()
	if _max_ticks > 0 and sim._tick_num >= _max_ticks:
		print("[server] done: t%d, %d ticks run, mean %.1f ms/tick" % [sim._tick_num, _ticks_run, _total_ms / max(_ticks_run, 1)])
		if _save_path != "":
			_save()
		get_tree().quit()

# --- Saving ---

func _check_stop_request() -> void:
	# Godot dies on SIGTERM / SIGINT without running any script, so a signal can't trigger the last
	# save. Instead whoever stops the server (the systemd unit's ExecStop) creates PATH.stop; the
	# server saves, removes it and quits. Checked once a second.
	if _save_path == "" or Time.get_ticks_msec() - _last_stop_check_ms < 1000:
		return
	_last_stop_check_ms = Time.get_ticks_msec()
	if FileAccess.file_exists(_save_path + ".stop"):
		print("[server] asked to stop: saving the world")
		_save()
		DirAccess.remove_absolute(_save_path + ".stop")
		get_tree().quit()

func _resume() -> bool:
	# Load the save, or the previous one if the save itself is unreadable. A save this build
	# refuses is moved aside, so the fresh world's first save doesn't overwrite it.
	for path in [_save_path, _save_path + ".prev"]:
		if not FileAccess.file_exists(path):
			continue
		var why = sim.load_world(path)
		if why == "":
			print("[server] resumed the world from %s at t%d" % [path, sim._tick_num])
			return true
		var aside = "%s.rejected-%d" % [path, int(Time.get_unix_time_from_system())]
		DirAccess.rename_absolute(path, aside)
		push_warning("[server] could not resume: %s. Moved it to %s" % [why, aside])
		sim = WorldSim.new()
	return false

func _save() -> void:
	var t0 = Time.get_ticks_usec()
	var err = sim.save_world(_save_path)
	_last_save_ms = Time.get_ticks_msec()
	if err != OK:
		push_error("[server] could not save the world to %s (error %d)" % [_save_path, err])
		return
	var size_kb = FileAccess.open(_save_path, FileAccess.READ).get_length() / 1024.0
	print("[server] saved t%d to %s: %.0f KB in %.0f ms" % [sim._tick_num, _save_path, size_kb, (Time.get_ticks_usec() - t0) / 1000.0])

# --- Clients ---

func _poll_clients() -> void:
	if _tcp == null:
		return
	while _tcp.is_connection_available():
		var ws = WebSocketPeer.new()
		ws.outbound_buffer_size = OUTBOUND_BUFFER_BYTES
		ws.inbound_buffer_size = INBOUND_BUFFER_BYTES
		ws.accept_stream(_tcp.take_connection())
		_peers.append({ "ws": ws, "open": false, "active": true })
	var presence_changed = false
	for p in _peers.duplicate():
		var ws: WebSocketPeer = p["ws"]
		ws.poll()
		var state = ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not p["open"]:
				p["open"] = true
				presence_changed = true
				_send(ws, WorldStream.snapshot(sim))
				print("[server] client connected (%d open)" % _open_count())
			while ws.get_available_packet_count() > 0:
				presence_changed = _handle(p, ws.get_packet()) or presence_changed
		elif state == WebSocketPeer.STATE_CLOSED:
			_peers.erase(p)
			presence_changed = true
			print("[server] client left (%d open)" % _open_count())
	if presence_changed:
		var any_active = false
		for p in _peers:
			if p["open"] and p["active"]:
				any_active = true
		sim.set_colony_active(WorldSim.LOCAL_COLONY, any_active)

func _handle(p: Dictionary, packet: PackedByteArray) -> bool:
	# Apply one client message; true if it changed the client's presence.
	var msg = bytes_to_var(packet)
	if not msg is Dictionary:
		return false
	if msg.has("chant") and msg["chant"] is String:
		sim._process_chant_locally(msg["chant"].substr(0, 200))
	if msg.has("active") and msg["active"] is bool:
		p["active"] = msg["active"]
		return true
	return false

func _broadcast(msg: Dictionary) -> void:
	_msg_id += 1
	var packets = WorldStream.pack(msg, _msg_id)
	for p in _peers:
		if p["open"]:
			_send_packets(p["ws"], packets)

func _send(ws: WebSocketPeer, msg: Dictionary) -> void:
	_msg_id += 1
	_send_packets(ws, WorldStream.pack(msg, _msg_id))

func _send_packets(ws: WebSocketPeer, packets: Array) -> void:
	for packet in packets:
		var err = ws.send(packet)
		if err != OK:
			# Its outbound buffer is full: the client can't keep up. Drop it; it reconnects and
			# gets a fresh snapshot.
			push_warning("[server] dropping a client that fell behind (error %d)" % err)
			ws.close()
			return

func _open_count() -> int:
	var n = 0
	for p in _peers:
		if p["open"]:
			n += 1
	return n
