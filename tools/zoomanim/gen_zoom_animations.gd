# Writes a zoom-animation spritesheet out as a SpriteFrames (#629).
#
# TWO KINDS OF SHEET, two readers, one output. A CARD-format sheet is READ by `CardSheet` -- it
# prints its own timing and carries its own registration. A LOOSE one is RECONSTRUCTED by
# `LooseSheet`: no cards, no timing, no registration, so its frames are cut to their ink, re-carded
# on that ink and given durations authored in the manifest (#635). An entry with a `loose` key is
# the second kind. What they promise differs and those files say how; from `_write_frames` down the
# two are one path.
#
# Two phases, because the SpriteFrames must reference an IMPORTED texture -- the same reason
# gen_lookdev_assets.gd is two phases, and the same shape:
#   godot --headless --path . --script res://tools/zoomanim/gen_zoom_animations.gd -- --atlas
#   godot --headless --path . --import
#   godot --headless --path . --script res://tools/zoomanim/gen_zoom_animations.gd -- --frames
# Add `--sheet <name>` to do one entry of SHEETS rather than all of them.
#
# This is the CLI and the WRITER only. What a card-format sheet SAYS -- where the cards are, what
# durations are printed over them, where one animation ends and the next begins -- is CardSheet's,
# which is static and pure so those rules can be exercised against a sheet a test draws rather than
# only against the one file in Art/.
extends SceneTree

# One entry per sheet. `region` picks ONE palette block -- these sheets carry the same animations
# two or three times over in different palettes, and cards outside the region are REPORTED rather
# than silently dropped. `backdrop` is a piece of the ORIGINAL GAME'S SCENE baked into the rip --
# on the Sage a flat green bush that stands behind him in every attack frame -- which must not
# reach a board that draws its own terrain; omit it and the step is skipped.
#
# Animation NAMES are typed here rather than read off the sheet, and the asymmetry with durations is
# deliberate: five names is not worth building letter recognition for, 159 durations is.
const SHEETS := {
	"Sage": {
		"source": "res://Art/Units/ZoomAnimations/Sage.png",
		"atlas": "res://Art/Units/ZoomAnimations/Sage_Frames.png",
		"output": "res://Resources/ZoomAnimations/Sage.tres",
		# The FEMALE sage. This sheet carries the class three times over -- male at the top (its
		# palettes are named Erk / Pent / Aion), then two female blocks below (Sonia / Limstella,
		# then Nino) -- and `MapSprites/Sage.png` is the female, so the male block was the wrong one.
		# Which block a unit needs is not derivable from the sheet; it is a content call, made here.
		"region": Rect2i(0, 700, 1000, 666),
		"animations": ["attack", "crit", "dodge", "staff", "staff_dodge"],
		"backdrop": Color8(0x09, 0x95, 0x4F),
	},
	# NO CARDS ON THIS SHEET, so it is read by LooseSheet and RE-CARDED (#635). Everything a card
	# format hands over free is reconstructed or authored here:
	#   - `region` is one animation's band rather than a palette block. The sheet's own labels sit
	#     inside it and are dropped by size.
	#   - `durations` are AUTHORED, in GBA frames at 60 Hz, because the sheet prints none. This set
	#     is a first guess to be tuned by eye: a settled stance, a fast strike, a held impact.
	#     74 frames is ~1.23s, and the axe lands on frame 8, ~0.63s in.
	# The Hand Axe and Map rows below the region are deliberately left unread -- one gesture is what
	# #603 asked for, and a second animation would have to agree with this one's card size.
	"Brigand": {
		"source": "res://Art/Units/ZoomAnimations/Brigand.png",
		"atlas": "res://Art/Units/ZoomAnimations/Brigand_Frames.png",
		"output": "res://Resources/ZoomAnimations/Brigand.tres",
		"loose": {
			"attack": {
				"region": Rect2i(0, 30, 473, 120),
				"durations": [8, 6, 6, 5, 6, 4, 3, 8, 10, 8, 5, 5],
			},
		},
	},
}

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

	# A sheet with no cards is a different READER and a different promise (#635); everything below
	# this line is the card format's.
	if spec.has("loose"):
		_run_loose(spec, source, want_atlas, want_frames)
		return

	var read := CardSheet.read(source, spec["region"] as Rect2i, spec["animations"] as Array)
	for note: String in (read["notes"] as Array):
		print("  (%s)" % note)
	if not (read["errors"] as Array).is_empty():
		for problem: String in (read["errors"] as Array):
			_fail(problem)
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
		_write_atlas(source, spec, animations, read["card"] as int)
	if want_frames:
		_write_frames(spec, animations, (spec["region"] as Rect2i).position)


# The loose path (#635): read each animation, RE-CARD it, and lay the animations out as stacked
# strips of one atlas. From `_write_frames` down nothing knows which reader produced the cards --
# they arrive as rects into the atlas either way, which is why the origin is a parameter now.
func _run_loose(spec: Dictionary, source: Image, want_atlas: bool, want_frames: bool) -> void:
	var loose: Dictionary = spec["loose"]
	var reads: Array = []
	var size := Vector2i.ZERO
	for anim_name: String in loose:
		var entry: Dictionary = loose[anim_name]
		var read := LooseSheet.read(source, entry["region"] as Rect2i, entry["durations"] as Array)
		for note: String in (read["notes"] as Array):
			print("  (%s)" % note)
		if not (read["errors"] as Array).is_empty():
			for problem: String in (read["errors"] as Array):
				_fail(problem)
			return
		var card: Vector2i = read["card"]
		var count: int = (read["frames"] as Array).size()
		print("    %-12s %2d frames re-carded to %s, %3d gba frames total   %s"
				% [anim_name, count, card, _sum(read["durations"] as Array), read["durations"]])
		reads.append({"name": anim_name, "read": read})
		size = Vector2i(maxi(size.x, card.x * count), size.y + card.y)

	# The atlas is composed whether or not it is WRITTEN: the card rects are what --frames needs,
	# and deriving them twice by two routes is how the two phases would drift apart.
	var atlas := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var animations: Array = []
	var row := 0
	for held: Dictionary in reads:
		var read: Dictionary = held["read"]
		animations.append({
			"name": held["name"],
			"cards": LooseSheet.paint(source, read, atlas, row),
			"durations": read["durations"],
		})
		row += (read["card"] as Vector2i).y

	if want_atlas:
		var err := atlas.save_png(ProjectSettings.globalize_path(spec["atlas"] as String))
		if err != OK:
			_fail("could not write %s (error %d)" % [spec["atlas"], err])
			return
		print("  wrote %s (%dx%d)" % [spec["atlas"], size.x, size.y])
	if want_frames:
		_write_frames(spec, animations, Vector2i.ZERO)


func _write_atlas(source: Image, spec: Dictionary, animations: Array, card: int) -> void:
	var backdrop: int = (spec["backdrop"] as Color).to_rgba32() if spec.has("backdrop") else -1
	var painted := CardSheet.paint(source, spec["region"] as Rect2i, animations, card, backdrop)
	if backdrop >= 0:
		print("  lifted %d backdrop px, all within a %s..%s box of the card"
				% [painted["lifted"], painted["lo"], painted["hi"]])

	var atlas := painted["image"] as Image
	var err := atlas.save_png(ProjectSettings.globalize_path(spec["atlas"] as String))
	if err != OK:
		_fail("could not write %s (error %d)" % [spec["atlas"], err])
		return
	print("  wrote %s (%dx%d)" % [spec["atlas"], atlas.get_width(), atlas.get_height()])


func _write_frames(spec: Dictionary, animations: Array, origin: Vector2i) -> void:
	var atlas_path := spec["atlas"] as String
	var sheet: Texture2D = load(atlas_path)
	if sheet == null:
		_fail("%s is not imported yet -- run --atlas, then `--import`, then --frames" % atlas_path)
		return

	var ground := _ground_point(sheet, animations, origin)
	if ground.x < 0.0:
		return   # _ground_point already said why

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	# Where the character stands inside a card (#634). Stored WITH the set because it is a fact about
	# this art that only the sheet can answer, and the sprite that plays it has no way to re-derive it
	# without scanning pixels every time a frame changes.
	frames.set_meta(&"ground_point", ground)
	for anim: Dictionary in animations:
		var name := StringName(anim["name"] as String)
		frames.add_animation(name)
		# GBA frames at 60 Hz: at this speed a frame's relative duration IS its printed number.
		frames.set_animation_speed(name, 60.0)
		# The sheet's own loop pointers all return to an idle pose the GAME does not want to sit in;
		# a gesture here plays once and hands the sprite back. See #629 for the pointers themselves.
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
	# ext_resource naming the atlas (#481). Left alone, a REGENERATION would drop a uid the editor
	# had since stamped, leaving anything that had come to name this SpriteFrames pointing at
	# nothing. DevWidgets is the one answer to that (the meshlib generator calls the same pair).
	var previous_uids := DevWidgets.uid_map_in_file(out)
	var err := ResourceSaver.save(frames, out)
	if err != OK:
		_fail("could not write %s (error %d)" % [out, err])
		return
	if not DevWidgets.restore_uids(out, previous_uids):
		_fail("could not restore uids on %s" % out)
		return
	print("  wrote %s" % out)


# Where the character stands, measured off the IDLE pose -- frame 0 of every animation, which on an
# FE card sheet is the stance each gesture returns to. Measured on the PAINTED atlas and not the
# source: on the source a card is a flat opaque rectangle of card colour, so its ink bounds would be
# the whole card. paint() is what keys that colour and the backdrop away.
#
# Every animation's frame 0 must agree, and a disagreement REFUSES rather than picking one. If the
# five idle poses are not the same pose then "the idle frame" is not a thing this sheet has, and one
# anchor for the set would silently hang four of them wrong -- the same class of error as a duration
# that does not glyph-match, which this tool already treats as fatal.
func _ground_point(sheet: Texture2D, animations: Array, origin: Vector2i) -> Vector2:
	var image := sheet.get_image()
	if image == null:
		_fail("could not read pixels back from the imported atlas")
		return Vector2(-1, -1)
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()

	var agreed := Vector2(-1, -1)
	var agreed_by := ""
	for anim: Dictionary in animations:
		var cards: Array = anim["cards"]
		if cards.is_empty():
			continue
		var first: Rect2i = cards[0]
		var card := Rect2i(first.position - origin, first.size)
		var point := CardSheet.ground_point(image, card)
		if point.x < 0.0:
			_fail("%s frame 0 has nothing drawn on it, so there is no stand point to measure"
					% anim["name"])
			return Vector2(-1, -1)
		if agreed.x < 0.0:
			agreed = point
			agreed_by = anim["name"] as String
		elif not point.is_equal_approx(agreed):
			_fail("idle poses disagree: %s stands at %s but %s stands at %s -- this sheet has no one idle frame"
					% [agreed_by, agreed, anim["name"], point])
			return Vector2(-1, -1)
	if agreed.x < 0.0:
		_fail("no animation carried a frame to measure a stand point from")
		return Vector2(-1, -1)
	print("  stand point %s (idle ink bottom-centre, agreed by all %d animations)"
			% [agreed, animations.size()])
	return agreed

func _sum(values: Array) -> int:
	var total := 0
	for v: int in values:
		total += v
	return total


func _fail(message: String) -> void:
	push_error(message)
	printerr("  FAILED: %s" % message)
	_failed = true
