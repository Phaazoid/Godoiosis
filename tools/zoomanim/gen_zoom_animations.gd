# Writes a card-format spritesheet out as a SpriteFrames (#629).
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
		_write_frames(spec, animations)


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


func _write_frames(spec: Dictionary, animations: Array) -> void:
	var atlas_path := spec["atlas"] as String
	var sheet: Texture2D = load(atlas_path)
	if sheet == null:
		_fail("%s is not imported yet -- run --atlas, then `--import`, then --frames" % atlas_path)
		return

	var origin: Vector2i = (spec["region"] as Rect2i).position
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
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


func _sum(values: Array) -> int:
	var total := 0
	for v: int in values:
		total += v
	return total


func _fail(message: String) -> void:
	push_error(message)
	printerr("  FAILED: %s" % message)
	_failed = true
