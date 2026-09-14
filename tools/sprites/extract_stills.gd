extends Node

# #937: cut the three shipped stills for each Zerie character out of the pack's animation strips.
#
# WHY THIS RE-CANVASSES RATHER THAN COPYING FRAMES. Measuring first (measure_ink.gd) found two
# things that decided the shape of this:
#
#   1. The characters are TINY in their 100x100 cell -- median ink 21px against the Fire Emblem
#      art's 19px. The big canvas is lunge room for attack animations we are not shipping, so
#      copying frames straight over would ship 95% transparent padding and force every sizing
#      constant in the game to move for art that is, in the only sense that matters, the same size.
#   2. Their feet do NOT land on a common row -- 54 to 60, a spread of 6. The FE set's spread was
#      0, every sprite ending on row 31, and that shared baseline is the entire reason ONE
#      MapSpriteInk.INK_RECT can serve every sprite. 6px on a 21px character is a third of a body:
#      units would visibly float and sink against each other.
#
# So each frame is re-canvassed onto SHEET x SHEET with its feet on the bottom row. The baseline
# then holds BY CONSTRUCTION rather than by luck -- tighter than the art we are replacing, which
# only had it because someone at Intelligent Systems was careful.
#
# Run: godot --headless --path . res://tools/sprites/extract_stills.tscn

const CELL := 100          # the pack's own cell
const SHEET := 64          # ours: the smallest power of two holding every shipped frame (52x38)
const OUT_DIR := "res://Art/Units/MapSprites/"
# How much of its peak body a death frame must still carry to count as the settled corpse rather
# than a stage of the fade. Measured: the four dissolving deaths drop away far below this.
const SOLID_FRACTION := 0.7

var _roots := {
	1: "C:/Users/Dmanz/AppData/Local/Temp/claude/C--Iosis/0e28a58f-401c-48d0-9b92-c087873e5500/scratchpad/p01",
	2: "C:/Users/Dmanz/AppData/Local/Temp/claude/C--Iosis/0e28a58f-401c-48d0-9b92-c087873e5500/scratchpad/p02",
}

var _written := 0
var _clipped: Array[String] = []
var _inks: Array[Rect2i] = []
var _death_picks: Array[String] = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for pack: int in _roots:
		var split := _split_dir(_roots[pack])
		if split.is_empty():
			push_error("no Characters(100x100 split) under %s" % _roots[pack])
			continue
		for name: String in DirAccess.get_directories_at(split):
			_do_character(split, name)
	_report()
	get_tree().quit()


func _split_dir(root: String) -> String:
	for top: String in DirAccess.get_directories_at(root):
		var inner := root + "/" + top + "/Characters(100x100 split)"
		if DirAccess.dir_exists_absolute(inner):
			return inner
	return ""


# CASE-INSENSITIVE, and that is not defensiveness: Necromancer ships `_DEATH.png` where all 41
# others ship `_Death.png`, and an exact match silently dropped its downed sprite entirely. Scan
# what is actually on disk rather than asking for a name we assume.
func _sheet(dir: String, name: String, candidates: Array) -> String:
	var files := DirAccess.get_files_at(dir)
	for suffix: String in candidates:
		var want := (name + suffix + ".png").to_lower()
		for file: String in files:
			if file.to_lower() == want:
				return dir + "/" + file
	return ""


func _do_character(split: String, name: String) -> void:
	var dir := "%s/%s/%s" % [split, name, name]   # the no-shadow variant (dev call)
	if not DirAccess.dir_exists_absolute(dir):
		push_warning("%s has no plain variant folder" % name)
		return

	var idle_sheet := _sheet(dir, name, ["_Idle", "_Flying"])
	if idle_sheet.is_empty():
		push_warning("%s has no idle or flying sheet" % name)
		return
	var idle_img := Image.load_from_file(idle_sheet)
	var idle := _frame(idle_img, 0)
	var idle_ink := idle.get_used_rect()
	if idle_ink.size == Vector2i.ZERO:
		push_error("%s idle frame 1 is empty" % name)
		return

	# IDLE AND MOVING SHARE ONE HORIZONTAL ANCHOR. Centring each frame on its own ink would slide
	# the body sideways the instant a unit started moving, because a walk frame's ink is wider
	# (legs apart) and rarely symmetric about the torso.
	var anchor_x := idle_ink.position.x + idle_ink.size.x / 2
	_write(name, "", idle, idle_ink, anchor_x)

	# MOVING: the frame that differs most from idle, per character. There is no one right index --
	# measured, the most-different frame is 1 for sixteen characters and 5 for fifteen others -- and
	# a move still that looks like the idle still is a move still nobody can see.
	var walk_sheet := _sheet(dir, name, ["_Walk", "_Walk01", "_Flying"])
	if not walk_sheet.is_empty():
		var walk_img := Image.load_from_file(walk_sheet)
		if walk_img != null:
			var count := walk_img.get_width() / CELL
			var best := 0
			var most := -1
			for i: int in count:
				var d := _difference(idle, _frame(walk_img, i))
				if d > most:
					most = d
					best = i
			var moving := _frame(walk_img, best)
			_write(name, "_Moving", moving, moving.get_used_rect(), anchor_x)

	# DOWNED: the last frame of the death animation -- a body on the ground. It gets its OWN
	# horizontal anchor, because a sprawl is wide and asymmetric and holding it to the standing
	# anchor would push it off the canvas (Orc rider's is 52px across).
	#
	# NOT simply the last frame. Four characters' deaths DISSOLVE -- Warlock runs 11 frames and
	# Black Knight_C 10, against the usual 4 -- so their final frame is empty and taking it
	# produced no downed sprite at all, silently. Walk back to the last frame still carrying most
	# of its body: that is the settled corpse, before the fade starts eating it.
	var death_sheet := _sheet(dir, name, ["_Death"])
	if not death_sheet.is_empty():
		var death_img := Image.load_from_file(death_sheet)
		if death_img != null:
			var count := death_img.get_width() / CELL
			var areas: Array[int] = []
			var peak := 0
			for i: int in count:
				var a := _opaque_count(_frame(death_img, i))
				areas.append(a)
				peak = maxi(peak, a)
			var pick := 0
			for i: int in count:
				if areas[i] >= peak * SOLID_FRACTION:
					pick = i
			var body := _frame(death_img, pick)
			var body_ink := body.get_used_rect()
			_death_picks.append("%-20s frame %d of %d" % [name, pick + 1, count])
			if body_ink.size != Vector2i.ZERO:
				_write(name, "_Downed", body, body_ink,
						body_ink.position.x + body_ink.size.x / 2)


func _frame(sheet: Image, index: int) -> Image:
	return sheet.get_region(Rect2i(index * CELL, 0, CELL, sheet.get_height()))


func _opaque_count(img: Image) -> int:
	var n := 0
	for y: int in CELL:
		for x: int in CELL:
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n


func _difference(a: Image, b: Image) -> int:
	var n := 0
	for y: int in CELL:
		for x: int in CELL:
			if (a.get_pixel(x, y).a > 0.5) != (b.get_pixel(x, y).a > 0.5):
				n += 1
	return n


# Place one frame's ink onto a SHEET-square canvas: feet on the bottom row, `anchor_x` at centre.
func _write(name: String, suffix: String, src: Image, ink: Rect2i, anchor_x: int) -> void:
	if ink.size == Vector2i.ZERO:
		return
	var out := Image.create_empty(SHEET, SHEET, false, Image.FORMAT_RGBA8)
	var dst := Vector2i(SHEET / 2 - anchor_x, SHEET - (ink.position.y + ink.size.y))

	var landed := Rect2i(ink.position + dst, ink.size)
	if landed.position.x < 0 or landed.end.x > SHEET or landed.position.y < 0:
		_clipped.append("%s%s -> %s" % [name, suffix, landed])
	out.blit_rect(src, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)), dst)

	var path := "%s%s%s.png" % [OUT_DIR, name, suffix]
	var err := out.save_png(path)
	if err != OK:
		push_error("could not write %s (%d)" % [path, err])
		return
	_written += 1
	if suffix.is_empty():
		_inks.append(out.get_used_rect())


func _report() -> void:
	print("\nwrote %d PNGs into %s at %dx%d" % [_written, OUT_DIR, SHEET, SHEET])
	if _clipped.is_empty():
		print("nothing clipped the canvas")
	else:
		print("CLIPPED -- the canvas is too small for these:")
		for line: String in _clipped:
			print("   " + line)

	if _inks.is_empty():
		return
	var union: Rect2i = _inks[0]
	var feet := {}
	for r: Rect2i in _inks:
		union = union.merge(r)
		var f := r.position.y + r.size.y
		feet[f] = int(feet.get(f, 0)) + 1
	print("\nidle ink after normalising:")
	print("  union over all 42: %s" % union)
	print("  feet rows present: %s   (one entry == a shared baseline)" % [feet])

	# INK_RECT frames a TYPICAL character, not the biggest one. The Fire Emblem rect was 16x19 while
	# the Dragon drew 26 rows and simply overflowed it (#560) -- a ring sized to the widest member
	# hangs slack around everyone else. Median, centred on the shared anchor.
	var ws: Array[int] = []
	var hs: Array[int] = []
	for r: Rect2i in _inks:
		ws.append(r.size.x)
		hs.append(r.size.y)
	ws.sort()
	hs.sort()
	var mw: int = ws[ws.size() / 2]
	var mh: int = hs[hs.size() / 2]
	print("  ink width  min %d / median %d / max %d" % [ws[0], mw, ws[-1]])
	print("  ink height min %d / median %d / max %d" % [hs[0], mh, hs[-1]])
	print("  -> MapSpriteInk.SHEET := %d" % SHEET)
	print("  -> MapSpriteInk.INK_RECT := Rect2i(%d, %d, %d, %d)   (median box, feet on the last row)"
			% [(SHEET - mw) / 2, SHEET - mh, mw, mh])

	if not _death_picks.is_empty():
		print("\ndeath frame chosen per character (>= %d%% of peak body):" % int(SOLID_FRACTION * 100))
		for line: String in _death_picks:
			print("   " + line)
