# Reads a CARD-FORMAT spritesheet into a SpriteFrames (#629).
#
# Two phases, because the SpriteFrames must reference an IMPORTED texture -- the same reason
# gen_lookdev_assets.gd is two phases, and the same shape:
#   godot --headless --path . --script res://tools/zoomanim/gen_zoom_animations.gd -- --atlas
#   godot --headless --path . --import
#   godot --headless --path . --script res://tools/zoomanim/gen_zoom_animations.gd -- --frames
# Add `--sheet <name>` to do one entry of SHEETS rather than all of them.
#
# WHAT A CARD-FORMAT SHEET IS. Every frame sits in a fixed-size rectangle of one flat colour, laid
# out in rows, with its duration printed above it and the animation's name printed to the left of
# the row it starts. The Sage sheet is one; the project's three other GBA rips are NOT, and no
# amount of cleverness makes them one -- they carry neither timing nor registration (see #629).
#
# WHY THE CARD MATTERS BEYOND FINDING THE FRAME. The card is a fixed VIEWPORT, so where the sprite
# sits inside it IS the per-frame offset -- the animation's own footwork. Cropping each frame to its
# content instead would throw that away and play back as a jitter rather than a step. So a frame's
# rect is always the whole card, never the ink inside it.
#
# THREE RULES THAT ARE NOT ARBITRARY:
#
#  1. Cards are found by CARD COLOUR, never by "not the page colour". A sprite may overhang its card
#     into the gutter, and a not-the-page scan then welds it to its neighbour -- measured on the
#     Sage as a 136px run where two 66px cards should be. Overhanging SPRITE pixels are not CARD
#     pixels, so the card-colour scan cannot be fooled that way.
#
#  2. A row that STARTS an animation has its name printed to the LEFT of its first card; a
#     continuation row has nothing there. That is the structure, not a guess about gap sizes --
#     the Sage's Attack wraps over three rows and its Crit over two, and both split correctly.
#
#  3. A duration that cannot be read EXACTLY is a hard failure, never a nearest match. A wrong
#     duration is invisible in the output and shows up only as bad feel, weeks later; a refusal
#     names the card and is fixed in a minute.
extends SceneTree

# One entry per sheet. `region` picks ONE palette block -- these sheets carry the same animations
# two or three times over in different palettes, and cards outside the region are REPORTED rather
# than silently dropped. `backdrop` is a piece of the ORIGINAL GAME'S SCENE baked into the rip --
# on the Sage a flat green bush that stands behind him in every attack frame -- which must not
# reach a board that draws its own terrain; omit it and the step is skipped.
const SHEETS := {
	"Sage": {
		"source": "res://Art/Units/ZoomAnimations/Sage.png",
		"atlas": "res://Art/Units/ZoomAnimations/Sage_Frames.png",
		"output": "res://Resources/ZoomAnimations/Sage.tres",
		"region": Rect2i(0, 0, 960, 700),
		"animations": ["attack", "crit", "dodge", "staff", "staff_dodge"],
		"backdrop": Color8(0x09, 0x95, 0x4F),
	},
}

# GBA frames at 60 Hz, so a SpriteFrames animation runs at speed 60 and a frame's duration IS this
# number. The masks are the sheet's own printed labels, emitted from the sheet rather than typed.
#
# The 1/3 pair is the one that could have gone wrong: at 10x magnification the second digit of `13`
# reads equally well as a 5, and 13 vs 15 is a silent two-frame error on eight cards. Settled
# against the sheet's OWN text -- it prints "go to Attack frame 3", and that glyph is pixel
# identical to this one. Cross-check: this table predicts 24 cards at 8 and 8 cards at 60, which is
# exactly what the row structure independently gives.
const DURATION_GLYPHS: Array = [
	[8, ["..###...", ".#####..", "#######.", "#######.", ".#####..",
		".######.", "########", "#######.", ".#####..", "..###..."]],
	[6, ["...###..", "..#####.", ".#####..", ".#####..", "#######.",
		"########", "########", "#######.", ".#####..", "..###..."]],
	[60, ["...###....###..", "..#####..#####.", ".#####..#######", ".#####.########",
		"###############", "###############", "###############", "##############.",
		".#####..#####..", "..###....###..."]],
	[13, ["....#....#####.", "..####..#######", ".#####.#######.", "..####..#.###..",
		"..####...#####.", "..####...######", "..####..#######", ".#############.",
		"#############..", ".######..###..."]],
	[4, [".....#..", "....###.", "...####.", "..#####.", ".######.",
		"########", "#######.", ".######.", "..######", "...####."]],
	[20, ["..####....###..", ".######..#####.", "###############", "###.###########",
		".#..###########", "...###.########", "..###.#########", ".#############.",
		"#############..", ".######..###..."]],
	[11, ["....#......#...", "..####...####..", ".#####..#####..", "..####...####..",
		"..####...####..", "..####...####..", "..####...####..", ".######.######.",
		"###############", ".######.######."]],
	[18, ["....#....###...", "..####..#####..", ".#####.#######.", "..####.#######.",
		"..####..#####..", "..####..######.", "..####.########", ".#############.",
		"#############..", ".######..###..."]],
]

# How far above a card its duration label may sit. Generous: a label that drifts outside this is
# unreadable and refused, which is the wanted outcome.
const LABEL_LOOKUP := 24

# A component this small is a pocket of card colour enclosed by the sprite (the gap between cape and
# body), not a card. The modal component size decides what a card IS, so this only trims noise.
const MIN_COMPONENT := 8

var _failed := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var want_atlas := args.has("--atlas")
	var want_frames := args.has("--frames")
	if not want_atlas and not want_frames:
		push_error("Nothing to do. Pass --atlas or --frames (see this file's header).")
		quit(1)
		return

	var only := ""
	var at := args.find("--sheet")
	if at >= 0 and at + 1 < args.size():
		only = args[at + 1]

	for name: String in SHEETS:
		if only != "" and name != only:
			continue
		_run(name, SHEETS[name], want_atlas, want_frames)

	quit(1 if _failed else 0)


func _run(name: String, spec: Dictionary, want_atlas: bool, want_frames: bool) -> void:
	print("=== %s" % name)
	var source := Image.new()
	var err := source.load(spec["source"] as String)
	if err != OK:
		_fail("cannot load %s (error %d)" % [spec["source"], err])
		return

	var read := _read_sheet(source, spec)
	if read.is_empty():
		return
	var animations: Array = read["animations"]

	var total := 0
	for anim: Dictionary in animations:
		total += (anim["cards"] as Array).size()
	print("  %d cards in %d animations" % [total, animations.size()])
	for anim: Dictionary in animations:
		var durations: Array = anim["durations"]
		print("    %-12s %2d frames, %3d gba frames total   %s"
				% [anim["name"], durations.size(), _sum(durations), durations])

	if want_atlas:
		_write_atlas(source, spec, animations)
	if want_frames:
		_write_frames(spec, animations)


# --- reading -----------------------------------------------------------------------------------


func _read_sheet(source: Image, spec: Dictionary) -> Dictionary:
	var region: Rect2i = (spec["region"] as Rect2i).intersection(
			Rect2i(Vector2i.ZERO, source.get_size()))
	var page := source.get_pixel(0, 0).to_rgba32()
	var card := _card_colour(source, page)
	if card < 0:
		return {}

	var components := _components(source, card, region)
	var cards := _modal_sized(components)
	if cards.is_empty():
		_fail("no cards found -- is the region right?")
		return {}
	if components.size() > cards.size():
		print("  (ignored %d card-coloured components that are not card sized -- pockets enclosed"
				% (components.size() - cards.size())
				+ " by the sprite)")
	_report_outside(source, card, region)

	var rows := _rows(cards)
	var names: Array = spec["animations"]
	var animations: Array = []
	for row: Array in rows:
		var first: Rect2i = row[0]
		if animations.is_empty() or _label_left_of(source, page, card, first, region):
			animations.append({"name": "", "cards": [], "durations": []})
		var current: Dictionary = animations[-1]
		for c: Rect2i in row:
			var duration := _duration_of(source, page, card, c)
			if duration <= 0:
				return {}
			(current["cards"] as Array).append(c)
			(current["durations"] as Array).append(duration)

	if animations.size() != names.size():
		_fail("found %d animations but the manifest names %d (%s) -- a row's name label was%s read"
				% [animations.size(), names.size(), ", ".join(PackedStringArray(names)),
				" wrongly" if animations.size() > names.size() else " missed"])
		return {}
	for i in animations.size():
		animations[i]["name"] = names[i]
	return {"animations": animations, "page": page, "card": card, "region": region}


# The most common colour that is not the page. Refused unless it wins by a clear margin: on a sheet
# where it does not, this is answering with a sprite colour and everything downstream is nonsense.
func _card_colour(img: Image, page: int) -> int:
	var hist: Dictionary = {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y).to_rgba32()
			if c != page:
				hist[c] = int(hist.get(c, 0)) + 1
	var best := -1
	var best_n := 0
	var second_n := 0
	for k: int in hist:
		var n := int(hist[k])
		if n > best_n:
			second_n = best_n
			best_n = n
			best = k
		elif n > second_n:
			second_n = n
	if best_n < second_n * 3:
		_fail("no clear card colour: #%08X has %d px against a runner-up with %d"
				% [best, best_n, second_n])
		return -1
	return best


func _components(img: Image, card: int, region: Rect2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var seen: Dictionary = {}
	var stride := img.get_width()
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if seen.has(y * stride + x) or img.get_pixel(x, y).to_rgba32() != card:
				continue
			var lo := Vector2i(x, y)
			var hi := lo
			var stack: Array[Vector2i] = [lo]
			seen[y * stride + x] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				lo.x = mini(lo.x, p.x); lo.y = mini(lo.y, p.y)
				hi.x = maxi(hi.x, p.x); hi.y = maxi(hi.y, p.y)
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = p + d
					if not region.has_point(q):
						continue
					if seen.has(q.y * stride + q.x) or img.get_pixel(q.x, q.y).to_rgba32() != card:
						continue
					seen[q.y * stride + q.x] = true
					stack.append(q)
			var r := Rect2i(lo, hi - lo + Vector2i.ONE)
			if r.size.x >= MIN_COMPONENT and r.size.y >= MIN_COMPONENT:
				out.append(r)
	return out


# What a card IS, measured rather than declared: the size that most components share.
func _modal_sized(components: Array[Rect2i]) -> Array[Rect2i]:
	var tally: Dictionary = {}
	for r: Rect2i in components:
		tally[r.size] = int(tally.get(r.size, 0)) + 1
	var best := Vector2i.ZERO
	var best_n := 0
	for k: Vector2i in tally:
		if int(tally[k]) > best_n:
			best_n = int(tally[k])
			best = k
	var out: Array[Rect2i] = []
	for r: Rect2i in components:
		if r.size == best:
			out.append(r)
	return out


func _report_outside(img: Image, card: int, region: Rect2i) -> void:
	var whole := Rect2i(Vector2i.ZERO, img.get_size())
	if region.encloses(whole):
		return
	var outside := 0
	for y in img.get_height():
		for x in img.get_width():
			if not region.has_point(Vector2i(x, y)) and img.get_pixel(x, y).to_rgba32() == card:
				outside += 1
	if outside > 0:
		print("  (%d card-coloured px lie OUTSIDE the region and were not read -- the sheet's other"
				% outside + " palette blocks and its credit box)")


func _rows(cards: Array[Rect2i]) -> Array:
	var by_y: Dictionary = {}
	for r: Rect2i in cards:
		var row: Array = by_y.get(r.position.y, [])
		row.append(r)
		by_y[r.position.y] = row
	var keys: Array = by_y.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		var row: Array = by_y[k]
		row.sort_custom(func(a: Rect2i, b: Rect2i): return a.position.x < b.position.x)
		out.append(row)
	return out


func _label_left_of(img: Image, page: int, card: int, first: Rect2i, region: Rect2i) -> bool:
	for y in range(first.position.y, first.end.y):
		for x in range(region.position.x, first.position.x):
			var c := img.get_pixel(x, y).to_rgba32()
			if c != page and c != card:
				return true
	return false


func _duration_of(img: Image, page: int, card: int, c: Rect2i) -> int:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for y in range(maxi(0, c.position.y - LABEL_LOOKUP), c.position.y):
		for x in range(c.position.x, c.end.x):
			var p := img.get_pixel(x, y).to_rgba32()
			if p == page or p == card:
				continue
			lo.x = mini(lo.x, x); lo.y = mini(lo.y, y)
			hi.x = maxi(hi.x, x); hi.y = maxi(hi.y, y)
	if hi.x < 0:
		_fail("no duration label above the card at %s" % c.position)
		return 0

	var label := Rect2i(lo, hi - lo + Vector2i.ONE)
	var mask: PackedStringArray = []
	for y in range(label.position.y, label.end.y):
		var line := ""
		for x in range(label.position.x, label.end.x):
			var p := img.get_pixel(x, y).to_rgba32()
			line += "#" if (p != page and p != card) else "."
		mask.append(line)

	for entry: Array in DURATION_GLYPHS:
		if PackedStringArray(entry[1]) == mask:
			return entry[0]
	_fail("unreadable duration label at %s (%dx%d) over the card at %s:\n    %s"
			% [label.position, label.size.x, label.size.y, c.position, "\n    ".join(mask)])
	return 0


# --- writing -----------------------------------------------------------------------------------


# The atlas is the region, cropped, with every background keyed to transparent. Cropped rather than
# whole because the region already declares which palette block is wanted, and rather than REPACKED
# because a repack costs the one property that makes a wrong frame cheap to diagnose: an atlas rect
# plus the region's origin is a coordinate you can find on the source sheet by eye.
func _write_atlas(source: Image, spec: Dictionary, animations: Array) -> void:
	var region: Rect2i = (spec["region"] as Rect2i).intersection(
			Rect2i(Vector2i.ZERO, source.get_size()))
	var page := source.get_pixel(0, 0).to_rgba32()
	var card := _card_colour(source, page)
	var atlas := Image.create(region.size.x, region.size.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))

	var backdrop: int = (spec["backdrop"] as Color).to_rgba32() if spec.has("backdrop") else -1
	var report := {"lifted": 0, "lo": Vector2i(1 << 30, 1 << 30), "hi": Vector2i(-1, -1)}
	for anim: Dictionary in animations:
		for c: Rect2i in (anim["cards"] as Array):
			_blit_card(source, atlas, c, region.position, card, backdrop, report)

	if backdrop >= 0:
		# The box is the evidence, not decoration: a backdrop the character also wears would spread
		# it across the whole card instead of confining it to one shape.
		print("  lifted %d backdrop px, all within a %s..%s box of the card"
				% [report["lifted"], report["lo"], report["hi"]])
	var err := atlas.save_png(ProjectSettings.globalize_path(spec["atlas"] as String))
	if err != OK:
		_fail("could not write %s (error %d)" % [spec["atlas"], err])
		return
	print("  wrote %s (%dx%d)" % [spec["atlas"], atlas.get_width(), atlas.get_height()])


# The card's pixels, minus its own background, minus the backdrop colour.
#
# A flat colour key, and that it is SAFE was measured rather than assumed -- the assumption worth
# checking is that the character never wears the backdrop's colour, since a key would then punch
# holes in him. Over the Sage's 55 cards the union bounding box of EVERY backdrop-coloured pixel is
# the bush's own box, (4,6)..(33,40), and the five frames with no bush have none of the colour at
# all: the counts run 20..640 and cap at exactly 640, which is the bush unoccluded. So the varying
# counts are the character standing in FRONT of one static shape, not a second user of the colour.
# `report` carries that evidence back out so the next sheet is checked rather than trusted.
func _blit_card(source: Image, atlas: Image, c: Rect2i, origin: Vector2i, card: int,
		backdrop: int, report: Dictionary) -> void:
	for y in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			var col := source.get_pixel(x, y)
			var rgba := col.to_rgba32()
			if rgba == card:
				continue
			if backdrop >= 0 and rgba == backdrop:
				var p := Vector2i(x, y) - c.position
				report["lifted"] = int(report["lifted"]) + 1
				report["lo"] = (report["lo"] as Vector2i).min(p)
				report["hi"] = (report["hi"] as Vector2i).max(p)
				continue
			atlas.set_pixelv(Vector2i(x, y) - origin, col)


func _write_frames(spec: Dictionary, animations: Array) -> void:
	var atlas_path := spec["atlas"] as String
	var sheet: Texture2D = load(atlas_path)
	if sheet == null:
		_fail("%s is not imported yet -- run the --atlas phase, then `--import`, then --frames"
				% atlas_path)
		return

	var origin: Vector2i = (spec["region"] as Rect2i).position
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim: Dictionary in animations:
		var name := StringName(anim["name"] as String)
		frames.add_animation(name)
		# GBA frames at 60 Hz: at this speed a frame's relative duration IS its printed number.
		frames.set_animation_speed(name, 60.0)
		frames.set_animation_loop(name, false)
		var cards: Array = anim["cards"]
		var durations: Array = anim["durations"]
		for i in cards.size():
			var cut := AtlasTexture.new()
			cut.atlas = sheet
			cut.region = Rect2((cards[i] as Rect2i).position - origin, (cards[i] as Rect2i).size)
			frames.add_frame(name, cut, float(durations[i]))

	var out := spec["output"] as String
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	# A headless ResourceSaver.save() writes NO uid -- not for the file's own header and not for the
	# ext_resource naming the atlas (#481). Left alone, the first editor save would add them and hand
	# the dev a modified file he never edited, and a REGENERATION would mint a different one, leaving
	# anything that had come to name this SpriteFrames pointing at nothing. DevWidgets is the one
	# answer to that (the meshlib generator calls the same pair); do not grow a second here.
	var previous_uids := DevWidgets.uid_map_in_file(out)
	var err := ResourceSaver.save(frames, out)
	if err != OK:
		_fail("could not write %s (error %d)" % [out, err])
		return
	if not DevWidgets.restore_uids(out, previous_uids):
		_fail("could not restore uids on %s" % out)
		return
	print("  wrote %s" % out)


func _sum(values: Array) -> int:
	var total := 0
	for v in values:
		total += v
	return total


func _fail(message: String) -> void:
	push_error(message)
	printerr("  FAILED: %s" % message)
	_failed = true
