extends RefCounted
class_name CameraTrace

# The camera's black box (#669): a bounded ring of what the rig's channels were, and what happened
# to them, dumped into report.md beside the View line.
#
# WHY IT EXISTS. The View line (#240, grown at #602 round 6) says where the camera IS. Every
# expensive bug in the #602 arc was a SEQUENCE bug -- round 5's race, round 8's release edge firing
# before the death show cleared -- and a final-frame reading cannot show a sequence. This can. The
# law behind it: build diagnostics in the channel that crosses the collaboration boundary. Claude
# never launches the game, so a report that answers "what was the camera doing, and in what order"
# by itself is a play-check round nobody spends.
#
# TWO VERBS, and the split is the whole of "cheap while idle" (#521B's discrete-moments law):
#
#   note()   -- a discrete moment, and it NAMES A CAUSE: a lock claimed, a stage published, a zoom
#               door opened, a release deferred. Always appends; never rate-limited, because the
#               named moments are exactly what a sequence is read off and losing one to a timer
#               would defeat the ticket.
#   sample() -- the heartbeat, and it is what makes the trace HONEST rather than merely complete.
#               It reads the channels wherever they got to, so a write that went nowhere near a
#               door still shows up: stash_view() zeroes _target_drop outright, restore_view()
#               assigns _target_yaw_degrees, and _process clamps _target_aim against pan_limit.
#               An earlier design hooked the rig's mutator doors instead and would have missed all
#               three -- and worse, hold_at/drop_to/lift_to are re-driven EVERY FRAME under
#               playback, so a door hook writes ~60 entries a second and a 120-entry ring covers
#               two seconds, evicting the very edges the trace exists to show.
#
# The rate limit is therefore load-bearing, not tidiness: 5 Hz while anything moves means the ring
# spans ~20s of continuous motion, and an idle camera writes nothing at all.
#
# PURE ON TIME -- every verb takes now_msec rather than reading the clock. CameraRig3D.recovered()'s
# idiom (the caller owns the headless escape): a suite drives the clock by hand and asserts the rate
# limit deterministically instead of sleeping through it.
#
# It sits in presentation/ rather than dev/ because it is written by shipping code on every frame of
# playback and read by the player-facing reporter (#131) -- the same reasoning that moved LookKnobs
# out of dev/ at #393. Where a thing is READ is not what decides where it lives.

# How many moments the ring holds. A COUNT, not a wall-clock window: entries are stamped and
# render() prints the span they actually cover, so an overflowing pass says "3.2 s" rather than
# silently claiming the ten seconds a pruned window would imply.
const MAX_ENTRIES := 120

# The heartbeat's floor, in milliseconds. See the header for why this number is the difference
# between a ring that spans a pass and one that spans two seconds.
const SAMPLE_INTERVAL_MSEC := 200

# How far a float channel must move to count as movement. Below the smallest thing worth reading in
# a report -- render() prints one decimal -- so a channel asymptotically approaching its target
# stops writing entries once it is visually there.
const CHANNEL_EPSILON := 0.01

# Oldest first, newest last, each {"t": int, "event": String, "channels": Dictionary}. An entry's
# channels are the snapshot AT that moment, which is what lets a reader follow a sequence down the
# page instead of reconstructing one from a single final reading.
var _entries: Array[Dictionary] = []

# When the last HEARTBEAT landed. Notes deliberately do not touch it: a named moment must never
# consume the sample budget, or a burst of events would blind the ease between them.
var _last_sample_msec := 0


# A named moment. Always lands.
func note(event: String, channels: Dictionary, now_msec: int) -> void:
	_append(event, channels, now_msec)


# The heartbeat. Lands only if something moved AND the floor has elapsed.
#
# Compared against the LAST ENTRY whatever wrote it, so a note() taken this frame is the baseline
# for the next sample -- which is what stops a door and the heartbeat from recording the same
# moment twice.
func sample(channels: Dictionary, now_msec: int) -> void:
	if not _entries.is_empty():
		if now_msec - _last_sample_msec < SAMPLE_INTERVAL_MSEC:
			return
		var last: Dictionary = _entries[-1]["channels"]
		if not _differs(channels, last):
			return
	_last_sample_msec = now_msec
	# Unnamed on purpose: render() leaves the column blank, so the eye follows the named rows and
	# reads the blanks as the ease between them.
	_append("", channels, now_msec)


func _append(event: String, channels: Dictionary, now_msec: int) -> void:
	_entries.append({"t": now_msec, "event": event, "channels": channels.duplicate()})
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)


# Did any channel move? Floats by epsilon, everything else by identity, so the same helper serves
# the bools and the time scale without the caller having to say which is which.
static func _differs(now: Dictionary, before: Dictionary) -> bool:
	for key: String in now:
		if not before.has(key):
			return true
		var a: Variant = now[key]
		var b: Variant = before[key]
		if a is float and b is float:
			if absf((a as float) - (b as float)) > CHANNEL_EPSILON:
				return true
		elif a != b:
			return true
	return false


# The report section's body. `now_msec` is the moment of the DUMP, so every row reads as "this long
# before the report was filed" -- which is the question a bug report is answering.
func render(now_msec: int) -> String:
	if _entries.is_empty():
		return "(nothing recorded -- no camera channel has moved this run)"

	var oldest: int = _entries[0]["t"]
	var out := "%d moments over %.1f s (ring holds %d, oldest evicted). Newest last; a blank " % [
		_entries.size(), (now_msec - oldest) / 1000.0, MAX_ENTRIES]
	out += "event is a heartbeat sample rather than a named moment.\n\n```\n"
	out += "     t  event                        aim         lift         drop          dist"
	out += "     dolly     yaw   pitch  brw  tscale\n"
	for entry: Dictionary in _entries:
		out += _row(entry, now_msec)
	out += "```\n"
	return out


static func _row(entry: Dictionary, now_msec: int) -> String:
	var at: int = entry["t"]
	var event: String = entry["event"]
	var c: Dictionary = entry["channels"]
	return "%6.2f  %-24s %11s  %11s  %11s  %11s  %6s  %6s  %6s  %-3s  %5s\n" % [
		(at - now_msec) / 1000.0,
		event,
		_vec(c.get("aim", Vector2.ZERO)),
		_pair(c.get("lift", 0.0), c.get("lift_target", 0.0)),
		_pair(c.get("drop", 0.0), c.get("drop_target", 0.0)),
		_pair(c.get("dist", 0.0), c.get("dist_target", 0.0)),
		_num(c.get("dolly", 0.0)),
		_num(c.get("yaw", 0.0)),
		_num(c.get("pitch", 0.0)),
		"yes" if bool(c.get("borrowed", false)) else "no",
		_num(c.get("tscale", 1.0)),
	]


# A live->target pair collapses to ONE number when the channel has arrived, so a settled row reads
# at a glance and only a channel still in flight spends the width saying so. That gap IS the
# diagnosis for all three eased channels (#602 rounds 7 and 8), which is why it is never hidden.
static func _pair(live: Variant, target: Variant) -> String:
	var a := float(live)
	var b := float(target)
	if absf(a - b) <= CHANNEL_EPSILON:
		return _num(a)
	return "%s->%s" % [_num(a), _num(b)]


static func _num(value: Variant) -> String:
	return "%.1f" % float(value)


static func _vec(value: Variant) -> String:
	var at := value as Vector2
	return "(%.1f, %.1f)" % [at.x, at.y]
