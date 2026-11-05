extends Node

# Headless world server (separation stage 6): ticks world_sim.gd with no rendering, camera or UI;
# the simulation writes telemetry exactly as it does under the client. The seed of the
# multiplayer server. Run it without a window:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> res://server.tscn -- [--ticks N] [--fast] [--listen PORT] [--tick-seconds S]
#     --ticks N          stop after N ticks (default: run until killed)
#     --fast             tick every frame instead of every TICK_SECONDS — pure simulation speed
#     --listen PORT      accept WebSocket clients on 127.0.0.1:PORT (a Cloudflare Tunnel or a
#                        local client connects there) and stream the world to them
#     --tick-seconds S   seconds per world tick (default TICK_SECONDS)
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
var _timer = 0.0
var _total_ms = 0.0
var _tcp: TCPServer = null
var _peers = []   # { "ws": WebSocketPeer, "open": bool, "active": bool }
var _msg_id = 0

func _ready() -> void:
	var port = 0
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
	sim = WorldSim.new()
	sim.setup()
	# Mark the run as headless in telemetry, right after its run_start record.
	sim._telemetry({ "type": "headless", "max_ticks": _max_ticks, "fast": _fast, "listen": port, "tick_seconds": _tick_seconds })
	if port > 0:
		_tcp = TCPServer.new()
		var err = _tcp.listen(port, "127.0.0.1")
		if err != OK:
			push_error("[server] could not listen on port %d (error %d)" % [port, err])
			_tcp = null
		else:
			# Nobody is watching until a client connects.
			sim.set_colony_active(WorldSim.LOCAL_COLONY, false)
	print("[server] world ready: %d colonies, %d entities, %s%s" % [sim.known_colonies.size(), sim.dots.size(), "fast" if _fast else "%.1f s ticks" % _tick_seconds, (", listening on 127.0.0.1:%d" % port) if _tcp else ""])

func _process(delta: float) -> void:
	_poll_clients()
	_timer += delta
	if not _fast and _timer < _tick_seconds:
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
	var live = 0
	for c in sim.colony_counts:
		live += sim.colony_counts[c]
	var blocks = 0
	for c in sim.block_counts:
		blocks += sim.block_counts[c]
	print("[server] t%d  live %d  blocks %d  specks %d  clients %d  tick %.1f ms" % [sim._tick_num, live, blocks, sim.specks.size(), _open_count(), ms])
	if _max_ticks > 0 and sim._tick_num >= _max_ticks:
		print("[server] done: %d ticks, mean %.1f ms/tick" % [sim._tick_num, _total_ms / sim._tick_num])
		get_tree().quit()

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
