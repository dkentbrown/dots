extends Node

# Headless world server (separation stage 6): ticks world_sim.gd with no rendering, camera or UI;
# the simulation writes telemetry exactly as it does under the client. The seed of the
# multiplayer server. Run it without a window:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path <project> res://server.tscn -- [--ticks N] [--fast]
#     --ticks N  stop after N ticks (default: run until killed)
#     --fast     tick every frame instead of every TICK_SECONDS — pure simulation speed
# Each tick prints one line: tick, live dots, blocks, specks, and that tick's cost in ms.
# Chants can be injected while it runs through res://chant.json, as with the client.

const WorldSim = preload("res://world_sim.gd")
const TICK_SECONDS = 1.0   # the client's TICK_SPEED: one world tick per second

var sim
var _max_ticks = -1
var _fast = false
var _timer = 0.0
var _total_ms = 0.0

func _ready() -> void:
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--ticks" and i + 1 < args.size():
			_max_ticks = int(args[i + 1])
		elif args[i] == "--fast":
			_fast = true
	sim = WorldSim.new()
	sim.setup()
	# Mark the run as headless in telemetry, right after its run_start record.
	sim._telemetry({ "type": "headless", "max_ticks": _max_ticks, "fast": _fast })
	print("[server] world ready: %d colonies, %d entities, %s" % [sim.known_colonies.size(), sim.dots.size(), "fast" if _fast else "real time"])

func _process(delta: float) -> void:
	_timer += delta
	if not _fast and _timer < TICK_SECONDS:
		return
	_timer = 0.0
	var t0 = Time.get_ticks_usec()
	sim.tick()
	# Nothing draws here, so drop the view flags each tick instead of letting them pile up.
	sim.take_view_changes()
	var ms = (Time.get_ticks_usec() - t0) / 1000.0
	_total_ms += ms
	var live = 0
	for c in sim.colony_counts:
		live += sim.colony_counts[c]
	var blocks = 0
	for c in sim.block_counts:
		blocks += sim.block_counts[c]
	print("[server] t%d  live %d  blocks %d  specks %d  tick %.1f ms" % [sim._tick_num, live, blocks, sim.specks.size(), ms])
	if _max_ticks > 0 and sim._tick_num >= _max_ticks:
		print("[server] done: %d ticks, mean %.1f ms/tick" % [sim._tick_num, _total_ms / sim._tick_num])
		get_tree().quit()
