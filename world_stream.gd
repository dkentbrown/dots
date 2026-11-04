extends RefCounted

# The wire format between the world server (server.gd) and a client's mirror (world_mirror.gd).
# The server owns the world; a client only draws it, so it is sent what the view reads and
# nothing more: per entity, where it sits and how it looks (colours are computed on the server),
# plus the few counters the HUD, the camera and the word cloud need.
#
# Messages are Dictionaries: "snapshot" (everything, on join) and "tick" (what changed since the
# last tick, from the sim's own view-change stream). Entities are packed per kind into parallel
# arrays rather than one Dictionary each, then the message is var_to_bytes'd, zstd-compressed and
# cut into CHUNK_BYTES pieces, each with a 12-byte header (message id u32, part u16, parts u16,
# uncompressed size u32), so no single WebSocket message is large enough to trip a proxy limit.
# Client → server messages are small Dictionaries sent whole: {"chant": text}, {"active": bool}.

const WorldSim = preload("res://world_sim.gd")

const CHUNK_BYTES = 256 * 1024
const HEADER_BYTES = 12

# Dot record flags.
const FLAG_BLOCK = 1
const FLAG_WALL = 2      # a wall's threat_dir follows in the dot "extra" array
const FLAG_FACING = 4    # the dot's facing follows in "extra" (after threat_dir for a wall)

# --- Server side ---

static func entity_batch(sim, ids) -> Dictionary:
	# Packed records for the given entity ids; ids that no longer exist are skipped.
	var d_ids = PackedInt64Array()
	var d_dirs = PackedVector3Array()
	var d_flags = PackedByteArray()
	var d_stack = PackedInt32Array()
	var d_extra = PackedVector3Array()
	var d_cols = PackedByteArray()
	var s_ids = PackedInt64Array()
	var s_dirs = PackedVector3Array()
	var m_ids = PackedInt64Array()
	var m_dirs = PackedVector3Array()
	var m_sizes = PackedFloat32Array()
	var m_cols = PackedByteArray()
	for id in ids:
		if sim.dot_data.has(id):
			var d = sim.dot_data[id]
			var flags = 0
			if d.get("is_block", false):
				flags |= FLAG_BLOCK
			if d.get("is_wall", false):
				flags |= FLAG_WALL
				d_extra.append(d["threat_dir"])
			if d.get("facing") != null:
				flags |= FLAG_FACING
				d_extra.append(d["facing"])
			d_ids.append(id)
			d_dirs.append(d["dir"])
			d_flags.append(flags)
			d_stack.append(d.get("stack_index", 0))
			var c = sim._dot_colors(id)
			_append_color(d_cols, c[0])
			_append_color(d_cols, c[1])
		elif sim.speck_data.has(id):
			s_ids.append(id)
			s_dirs.append(sim.speck_data[id]["dir"])
		elif sim.mark_data.has(id):
			var m = sim.mark_data[id]
			m_ids.append(id)
			m_dirs.append(m["dir"])
			m_sizes.append(m["size"])
			_append_color(m_cols, m["color"])
	return {
		"dots": [d_ids, d_dirs, d_flags, d_stack, d_extra, d_cols],
		"specks": [s_ids, s_dirs],
		"marks": [m_ids, m_dirs, m_sizes, m_cols],
	}

static func world_state(sim) -> Dictionary:
	# The counters the client reads besides entities. Profiles feed the word cloud's picks.
	var contacts = []
	for c in sim._current_contacts():
		contacts.append(sim._colony_profile(c))
	return {
		"tick": sim._tick_num,
		"counts": sim.colony_counts,
		"blocks": sim.block_counts,
		"soul": sim.soul_pool,
		"centers": sim._cached_colony_centers,
		"period": sim.colony_period,
		"perch": PackedInt64Array(sim.wall_perch.keys()),
		"self_profile": sim._colony_profile(WorldSim.LOCAL_COLONY),
		"contact_profiles": contacts,
	}

static func snapshot(sim) -> Dictionary:
	var ids = []
	ids.append_array(sim.dot_data.keys())
	ids.append_array(sim.speck_data.keys())
	ids.append_array(sim.mark_data.keys())
	var specs = []
	for spec in sim._field_specs:
		specs.append({ "name": spec["name"], "combat_role": spec.get("combat_role", "") })
	return {
		"kind": "snapshot",
		"state": world_state(sim),
		"field_colors": sim._field_colors,
		"field_specs": specs,
		"entities": entity_batch(sim, ids),
	}

static func tick_message(sim, changes: Array) -> Dictionary:
	# `changes` is sim.take_view_changes(): [dirty (id -> bits), gone (ids)].
	return {
		"kind": "tick",
		"state": world_state(sim),
		"entities": entity_batch(sim, changes[0].keys()),
		"gone": PackedInt64Array(changes[1]),
	}

static func _append_color(out: PackedByteArray, c: Color) -> void:
	out.append(c.r8)
	out.append(c.g8)
	out.append(c.b8)
	out.append(c.a8)

# --- Framing (both sides) ---

static func pack(msg: Dictionary, msg_id: int) -> Array:
	# One message as a list of chunk packets, ready for WebSocketPeer.send.
	var raw = var_to_bytes(msg)
	var z = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var parts = maxi(1, ceili(float(z.size()) / CHUNK_BYTES))
	var out = []
	for p in range(parts):
		var head = PackedByteArray()
		head.resize(HEADER_BYTES)
		head.encode_u32(0, msg_id)
		head.encode_u16(4, p)
		head.encode_u16(6, parts)
		head.encode_u32(8, raw.size())
		out.append(head + z.slice(p * CHUNK_BYTES, mini((p + 1) * CHUNK_BYTES, z.size())))
	return out

class Assembler:
	# Rebuilds messages from chunk packets (a WebSocket delivers them in order).
	var _id = -1
	var _parts = []
	var _got = 0

	func feed(packet: PackedByteArray):
		# The finished message Dictionary once its last chunk arrives; null until then.
		if packet.size() < HEADER_BYTES:
			return null
		var id = packet.decode_u32(0)
		var p = packet.decode_u16(4)
		var n = packet.decode_u16(6)
		var raw_size = packet.decode_u32(8)
		if id != _id:
			_id = id
			_parts = []
			_parts.resize(n)
			_got = 0
		if p >= n:
			return null
		if _parts[p] == null:
			_got += 1
		_parts[p] = packet.slice(HEADER_BYTES)
		if _got < n:
			return null
		var z = PackedByteArray()
		for part in _parts:
			z.append_array(part)
		_id = -1
		var msg = bytes_to_var(z.decompress(raw_size, FileAccess.COMPRESSION_ZSTD))
		return msg if msg is Dictionary else null
