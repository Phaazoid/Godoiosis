# THE law #552 exists to keep: the water a tile SHOWS is the water it IS.
#
# Shallow water is ordinary ground and deep water drowns you, and the two are told apart on the
# board by their top face alone -- there is no second Kind to read (#116: "One Kind, two tiles").
# Before this the sheet painted both the identical flat blue: measured, the deep tile was one
# colour in all 256 of its pixels and the shallow tile in 242 of them. A player could not see which
# was which, and the hover card was already saying it in words.
#
# So there are two halves and each has its own case. HOW DEEP a cell is comes from the board mask,
# derived from the tile's own `walkable` flag -- the flag the rules read, which is what stops the
# render and the ruleset drifting apart. (It was two shader materials keyed on a baked `deep` until
# #552 slice 2b; this header said so until #578.)
#
# The BASE COLOUR is a KNOB PAIR since #578, and used to be the tile's authored modulate on the
# reading that it had to reach the flat view too. That held until the shallow/deep boundary had to
# BLEND, which a per-tile bake structurally cannot do -- by fragment() the two tints are two texels
# in one atlas. 3D takes knobs, the flat view keeps the modulate, and the divergence is DECLARED on
# #292. Hence the atlas case below asserts water is composed UNTINTED, which is the inverse of what
# it asserted for two days.
#
# The last case is a wire, not a look: a global uniform is spelled in THREE places (the shader, the
# knob table, project.godot) and a misspelling in any of them is silent -- GLSL just reads zero.
extends GdUnitTestSuite

const MESHLIB_PATH := "res://Scenes/LookDev/lookdev_meshlib.tres"
const TILESET_PATH := "res://Resources/TestTiles.tres"
const SHADER_PATH := "res://Scenes/LookDev/water.gdshader"
const ATLAS_PATH := "res://Art/LookDev/ground_atlas_0.png"

var _library: MeshLibrary
var _tiles: TileSet
var _by_name: Dictionary[String, int] = {}


func before_test() -> void:
	_library = load(MESHLIB_PATH) as MeshLibrary
	assert_object(_library).override_failure_message(
			"the meshlib is missing or unreadable at %s" % MESHLIB_PATH).is_not_null()
	_tiles = load(TILESET_PATH) as TileSet
	assert_object(_tiles).override_failure_message(
			"the tileset is missing or unreadable at %s" % TILESET_PATH).is_not_null()
	_by_name.clear()
	for id: int in _library.get_item_list():
		_by_name[_library.get_item_name(id)] = id


# Every WATER tile the tileset declares, with the source it came from. Read off the TILESET rather
# than off a list here, so a water tile authored tomorrow joins these cases by existing.
func _water_tiles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _tiles.get_source_count():
		var source_id := _tiles.get_source_id(s)
		var atlas := _tiles.get_source(source_id) as TileSetAtlasSource
		if atlas == null:
			continue
		for i in atlas.get_tiles_count():
			var coords := atlas.get_tile_id(i)
			if atlas.get_tile_size_in_atlas(coords) != Vector2i.ONE:
				continue
			var data := atlas.get_tile_data(coords, 0)
			if GridUtils.terrain_kind_of(data) != Terrain.Kind.WATER:
				continue
			out.append({"source": source_id, "coords": coords, "data": data, "atlas": atlas})
	return out


# Every item name that draws THIS tile's surface: its block, and the wedge per climb and shape.
func _surface_items(source_id: int, coords: Vector2i) -> PackedStringArray:
	var names := PackedStringArray([BoardMirror.tile_item_name(source_id, coords)])
	for climb: int in BoardMirror.RAMP_ITEM_NAMES:
		for form: Terrain.Form in [Terrain.Form.WEDGE, Terrain.Form.OUTER, Terrain.Form.INNER]:
			names.append(BoardMirror.ramp_item_name(source_id, coords, climb, form))
	return names


# THE bake, and its DELETION (#552 slice 2b). `deep` used to be a per-material uniform, so the
# generator built two water materials and picked between them by the tile's walkable flag. That is
# gone: how deep a cell is now lives in the board mask, per CELL, where it can be interpolated --
# and the walkable wire it used to carry moved with it, to
# test_water_knobs.gd::test_the_mask_says_how_deep_each_water_cell_is.
#
# What is left to guard here is the COLLAPSE itself, and it is worth a case because a half-done
# revert is silent: a shallow tile and a deep tile must wear the SAME material object. If they ever
# wear two again, something is baking depth per material a second time, and the shader would be
# reading two answers to one question.
func test_shallow_and_deep_water_wear_the_one_material() -> void:
	var by_walkable: Dictionary[bool, Array] = {true: [], false: []}
	for tile: Dictionary in _water_tiles():
		var data: TileData = tile["data"]
		for item_name in _surface_items(tile["source"], tile["coords"]):
			assert_bool(_by_name.has(item_name)).override_failure_message(
					"no item '%s' -- the meshlib is stale, regenerate it" % item_name).is_true()
			if not _by_name.has(item_name):
				continue
			var mat := _library.get_item_mesh(_by_name[item_name]).surface_get_material(0)
			var shaded := mat as ShaderMaterial
			assert_object(shaded).override_failure_message(
					"'%s' wears a %s, not the water shader" % [item_name, mat]).is_not_null()
			by_walkable[GridUtils.walkable_of(data)].append(shaded)
	# Both sorts have to be present or the case proves nothing: one material is trivially true of a
	# tileset with only shallow water in it.
	assert_bool(by_walkable[true].is_empty()).override_failure_message(
			"no WADEABLE water tile authored; the collapse is untested").is_false()
	assert_bool(by_walkable[false].is_empty()).override_failure_message(
			"no DROWNING water tile authored; the collapse is untested").is_false()
	var all: Array = by_walkable[true] + by_walkable[false]
	for mat: ShaderMaterial in all:
		assert_bool(mat == all[0]).override_failure_message(
				"water surfaces wear more than one material -- depth is baked per material " \
				+ "again, which is the second answer the board mask exists to be the only one " \
				+ "of, and a shallow/deep boundary cannot blend across it").is_true()


# The blast radius, from the other end: the shader is on water and NOWHERE else. A material is
# shared across items by construction, so leaking it onto one wrong tile leaks it onto a whole kind.
func test_only_water_wears_the_water_shader() -> void:
	var water_items: Dictionary[String, bool] = {}
	for tile: Dictionary in _water_tiles():
		for item_name in _surface_items(tile["source"], tile["coords"]):
			water_items[item_name] = true
	# The declared Kind FALLBACK is water too, and wears it for the same reason: a cell with no
	# per-tile item would otherwise sit still in the middle of a moving lake.
	water_items[_library.get_item_name(BoardMirror.KIND_TO_ITEM[Terrain.Kind.WATER])] = true

	var shaded_surfaces: Dictionary[String, int] = {}
	var shader := load(SHADER_PATH) as Shader
	for id: int in _library.get_item_list():
		var item_name := _library.get_item_name(id)
		var mesh := _library.get_item_mesh(id)
		for surface in mesh.get_surface_count():
			var shaded := mesh.surface_get_material(surface) as ShaderMaterial
			if shaded == null:
				continue
			assert_bool(shaded.shader == shader).override_failure_message(
					"'%s' surface %d wears an unknown ShaderMaterial" \
					% [item_name, surface]).is_true()
			assert_bool(water_items.has(item_name)).override_failure_message(
					"'%s' is not a water item but wears the water shader" % item_name).is_true()
			shaded_surfaces[item_name] = shaded_surfaces.get(item_name, 0) + 1

	# And the other direction: a water BLOCK wears it on both of its surfaces. The rule is not
	# "surface 0 only" any more -- it was, until the Body shade knob turned out to be driving the
	# 0.004-unit rim in surface 0 and nothing else, while the walls in surface 1 wore a plain
	# material the shader never saw. The shader answers both questions and forks on the world
	# normal: the up-facing quad is the water's FACE, the walls and the rim are its BODY.
	for tile: Dictionary in _water_tiles():
		var block := BoardMirror.tile_item_name(tile["source"], tile["coords"])
		var mesh := _library.get_item_mesh(_by_name[block])
		assert_int(shaded_surfaces.get(block, 0)).override_failure_message(
				"'%s' wears the water shader on %d of its %d surfaces -- a block's WALLS are the " \
				% [block, shaded_surfaces.get(block, 0), mesh.get_surface_count()] \
				+ "water's body, and a knob that shades them can only reach them here") \
				.is_equal(mesh.get_surface_count())


# The other half of the read, and the half that reaches BOTH views: shallow water is lighter than
# deep. Asserted as the FORK and never as either side of it -- how much lighter is a by-eye call
# that will move, and a test that pins one of those numbers turns re-tuning into a red run.
func test_shallow_water_reads_lighter_than_deep() -> void:
	var shallow: Array[Dictionary] = []
	var deep: Array[Dictionary] = []
	for tile: Dictionary in _water_tiles():
		if GridUtils.walkable_of(tile["data"]):
			shallow.append(tile)
		else:
			deep.append(tile)
	assert_bool(shallow.is_empty()).override_failure_message(
			"no walkable water tile authored; the case is vacuous").is_false()
	assert_bool(deep.is_empty()).override_failure_message(
			"no unwalkable water tile authored; the case is vacuous").is_false()

	for wet: Dictionary in shallow:
		for dry: Dictionary in deep:
			var lit: Color = (wet["data"] as TileData).modulate
			var dark: Color = (dry["data"] as TileData).modulate
			assert_float(lit.get_luminance()).override_failure_message(
					"tile %s is walkable but its modulate is no lighter than %s's -- in the FLAT " \
					% [wet["coords"], dry["coords"]] + "view that tint is the whole difference " \
					+ "between wading and drowning").is_greater(dark.get_luminance())


# THE INVERSE OF WHAT THIS ASSERTED UNTIL #578, and the reason is worth having in one place.
#
# The generator used to bake each water tile's authored modulate into the composed atlas, because
# the 3D board read its base colour from there. It cannot any more: a per-tile bake is two texels in
# one texture by the time fragment() runs, so the shallow/deep boundary changed colour in a single
# pixel however smoothly every other channel glided across it. 3D takes a knob pair instead, water's
# top face stopped sampling the atlas at all, and a tint baked here would have no reader.
#
# So water is composed RAW, and the non-vacuity guard below is what gives the case teeth: it demands
# that some water tile still AUTHORS a modulate, which is what makes "untinted" evidence that the
# generator skipped one rather than evidence that there was nothing to skip. Every other kind still
# bakes -- that half is the `stands_up` branch and is untouched.
func test_the_composed_atlas_leaves_water_untinted() -> void:
	var baked := (load(ATLAS_PATH) as Texture2D).get_image()
	if baked.is_compressed():
		baked.decompress()
	var skipped := 0
	for tile: Dictionary in _water_tiles():
		var source: TileSetAtlasSource = tile["atlas"]
		var modulate: Color = (tile["data"] as TileData).modulate
		if modulate == Color(1, 1, 1, 1):
			continue
		var sheet := source.texture.get_image()
		if sheet.is_compressed():
			sheet.decompress()
		var region := source.get_tile_texture_region(tile["coords"], 0)
		for y in range(region.size.y):
			for x in range(region.size.x):
				var art := sheet.get_pixel(region.position.x + x, region.position.y + y)
				# Water tiles are fully opaque -- measured -- so the kind base the generator blits
				# underneath is covered and the composed pixel is the art alone.
				assert_float(art.a).override_failure_message(
						"tile %s is not opaque, so this comparison would be reading the kind " \
						% tile["coords"] + "base through it").is_equal_approx(1.0, 0.01)
				var got := baked.get_pixel(region.position.x + x, region.position.y + y)
				assert_bool(_within(got, art, 2.0 / 255.0)).override_failure_message(
						"the composed atlas draws water tile %s at %s where its raw sheet art is " \
						% [tile["coords"], got] + "%s -- the generator is still baking the tile's " \
						% art + "modulate, which the shader would then tint a second time") \
						.is_true()
		skipped += 1
	assert_int(skipped).override_failure_message(
			"no water tile authors a modulate, so an untinted atlas proves nothing about the " \
			+ "generator skipping one").is_greater(0)


func _within(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance \
			and absf(a.b - b.b) <= tolerance


# The parse canary. Godot compiles its own shader language to GLSL, and a shader that fails that
# parse still LOADS — it just exposes no uniforms — so nothing else in this file would notice: the
# materials would carry their parameters, the meshlib would be identical, and the first sign would
# be an error surface on the dev's screen. It also pins the name the generator sets by hand -- one
# since #578, `atlas` having gone with the tile-art base colour it existed to carry.
func test_the_water_shader_parses_and_exposes_what_the_generator_sets() -> void:
	var shader := load(SHADER_PATH) as Shader
	assert_object(shader).is_not_null()
	var names := PackedStringArray()
	for entry: Dictionary in shader.get_shader_uniform_list():
		names.append(entry["name"])
	assert_bool(names.is_empty()).override_failure_message(
			"the water shader exposes no uniforms at all -- it failed to parse, and every water " \
			+ "surface will render as an error").is_false()
	for wanted in ["body_tex"]:
		assert_bool(names.has(wanted)).override_failure_message(
				"gen_lookdev_assets sets shader parameter '%s' and the shader declares no such " \
				% wanted + "uniform -- the value is dropped in silence").is_true()


# BOARD DATA: the one declared exemption from the two laws below, and its guest list is CLOSED.
# These describe the BOARD rather than either water, so they can never name a type and they have no
# knob row -- the mask is derived from the terrain, not tuned. Membership is asserted in BOTH
# directions, because a hole a future knob could fall into unnamed is the law quietly deleted,
# while a named category with a fixed membership is a category.
const BOARD_GLOBALS := ["water_board_mask", "water_board_mask_rect", "water_board_shore_range",
		"water_board_mask_range"]

# SHARED tuning: the SECOND declared exemption, and a different one from the board data above.
# These ARE knobs -- they have rows, they are swept -- but each describes the TRANSITION between the
# two waters rather than either one, so there is nothing a per-type pair could mean. A closed list
# again, asserted in both directions, because the failure to design against is a genuinely per-type
# knob landing here to dodge the naming rule.
const SHARED_GLOBALS := ["water_depth_range", "water_shore_fade_range"]

# PHASE globals: the ones that set WHERE a wave is rather than how strong it is. Interpolating one
# across the depth seam is #646, and the closed list is the BOARD_GLOBALS shape for the same reason
# -- the suffix check below catches a renamed or duplicated wave knob, but a NEW kind of phase knob
# (a flow direction, a second octave's rate) can only be caught by a human putting it here.
const PHASE_GLOBALS := ["water_deep_wave_speed", "water_shallow_wave_speed",
		"water_deep_wave_scale", "water_shallow_wave_scale"]


# What the shader declares, in one place. Three cases used to parse this line for themselves with
# the same one-liner, and the sampler #552 slice 2 added broke all three at once: a sampler carries
# its hints after a colon (`: filter_linear, repeat_disable`), so the NAME is the last word before
# that colon and not the last word on the line.
func _declared_globals() -> PackedStringArray:
	var out := PackedStringArray()
	for line in (load(SHADER_PATH) as Shader).code.split("\n"):
		var text := line.strip_edges()
		if not text.begins_with("global uniform "):
			continue
		var head := text.trim_suffix(";").split(":")[0].strip_edges()
		var words := head.split(" ")
		out.append(words[words.size() - 1])
	return out


# A global uniform is spelled in three files and NOTHING complains when two of them disagree: an
# undeclared global refuses to compile, and a misspelled one silently reads zero. So the three
# spellings are held to being one set.
#
# Board data is spelled in TWO of the three -- no knob row, because nobody tunes the shape of the
# board -- so it is held to the project.godot half alone.
func test_every_water_knob_is_spelled_the_same_in_all_three_places() -> void:
	var declared := _declared_globals()
	assert_int(declared.size()).override_failure_message(
			"the water shader declares no globals; the case is vacuous").is_greater(0)
	var tunable: Array[String] = []
	for name in declared:
		if not BOARD_GLOBALS.has(name):
			tunable.append(name)

	var rows: Dictionary[String, bool] = {}
	for knob: Dictionary in GameKnobs.KNOBS:
		# The Water FAMILY: two groups since every dial went per type. Matching the prefix rather
		# than naming both is what stops a third group from silently falling out of this law -- and
		# the non-vacuity assertion above is what stops the prefix being wrong, since a filter that
		# matches nothing would let every case pass over an empty set.
		if (knob["group"] as String).begins_with("Water"):
			rows[knob["prop"]] = true
	assert_array(rows.keys()).override_failure_message(
			"the Water knob rows and the shader's tunable globals are different sets -- a row " \
			+ "with no uniform moves nothing, and a uniform with no row cannot be tuned") \
			.contains_exactly_in_any_order(tunable)

	for name in declared:
		assert_bool(ProjectSettings.has_setting("shader_globals/%s" % name)) \
				.override_failure_message("the shader declares global '%s' and project.godot " \
				% name + "does not -- the shader will refuse to compile").is_true()


# THE regression guard for #552 slice 1c: no water uniform is ambiguous about which water it acts
# on. Shallow's character used to be a fixed RATIO off deep's, living in the shader as constants --
# so one dial moved both types together and "shallow choppy, deep glassy" could not be expressed at
# all. A ratio between two authored things is itself an authored thing; the failure this catches is
# a value quietly reverting to acting on both.
#
# Every DEEP one must have a shallow twin. The reverse is deliberately NOT required: the bed and its
# caustics are what you see THROUGH shallow water and deep water is opaque, so they are shallow-only
# by nature rather than by omission -- they carry the word anyway so the panel needs no remembering.
func test_no_water_uniform_is_ambiguous_about_its_type() -> void:
	var deep_side: Dictionary[String, bool] = {}
	var shallow_side: Dictionary[String, bool] = {}
	var board_side: Array[String] = []
	var shared_side: Array[String] = []
	for name in _declared_globals():
		if BOARD_GLOBALS.has(name):
			board_side.append(name)
			continue
		if SHARED_GLOBALS.has(name):
			shared_side.append(name)
			continue
		var deep := name.begins_with("water_deep_")
		var shallow := name.begins_with("water_shallow_")
		assert_bool(deep or shallow).override_failure_message(
				"global '%s' names neither water type -- one dial moving both is what the " % name \
				+ "per-type split deleted, and a ratio hidden in a const is a feel value with no " \
				+ "surface. If it is genuinely board data and not a knob, it belongs in " \
				+ "BOARD_GLOBALS and needs saying out loud there").is_true()
		if deep:
			deep_side[name.trim_prefix("water_deep_")] = true
		elif shallow:
			shallow_side[name.trim_prefix("water_shallow_")] = true
	assert_bool(deep_side.is_empty()).override_failure_message(
			"the shader declares no deep globals; the case is vacuous").is_false()
	for stem: String in deep_side:
		assert_bool(shallow_side.has(stem)).override_failure_message(
				"'%s' is tunable on deep water and not on shallow -- one type would be stuck " \
				% stem + "with whatever the other was tuned to").is_true()
	# The exemption holds EXACTLY what it says it holds. Missing means a board global was renamed
	# without saying so; extra is impossible by construction, but asserting both directions is what
	# makes this a list rather than a filter.
	assert_array(board_side).override_failure_message(
			"the board-data exemption is declared as %s and the shader's is %s" \
			% [BOARD_GLOBALS, board_side]).contains_exactly_in_any_order(BOARD_GLOBALS)
	assert_array(shared_side).override_failure_message(
			"the shared-tuning exemption is declared as %s and the shader's is %s -- a knob that " \
			% [SHARED_GLOBALS, shared_side] + "genuinely acts on one water type belongs in a " \
			+ "deep/shallow pair, not in here").contains_exactly_in_any_order(SHARED_GLOBALS)


# A DECLARED uniform is not a READ one, and a knob wired to a uniform nobody samples is a slider
# that moves nothing. Aimed at the bug class #552 shipped twice: Shallow bed and Body shade both
# went min-to-max with no visible change.
#
# Worth saying what this does NOT catch, because a law that oversells its reach is worse than no
# law. Neither of those two would have reddened here -- both were read; one drove the 0.004-unit
# rim, which #559 built to be invisible, and the other was per-art-pixel noise below what the eye
# resolves at a playing distance. Whether a knob's effect is VISIBLE is not a question any headless
# test can ask. This catches the next one along: a uniform nothing samples at all.
func test_every_global_the_shader_declares_is_actually_read() -> void:
	var code := (load(SHADER_PATH) as Shader).code
	var checked := 0
	for name in _declared_globals():
		# Count every mention and subtract the declaration itself; a comment naming it is close
		# enough to a read for this purpose, and being generous here is the right side to err on --
		# the finding worth having is ZERO.
		var mentions := code.count(name)
		assert_int(mentions).override_failure_message(
				"the shader declares global '%s' and never reads it -- its knob, its row and its " \
				% name + "project.godot entry all exist and the slider moves nothing").is_greater(1)
		checked += 1
	assert_int(checked).override_failure_message(
			"the shader declares no globals; the case is vacuous").is_greater(0)


# The shader with every `//` comment removed, so a law may scan CODE without a prose example of the
# very thing it forbids reddening it.
func _shader_code_without_comments() -> String:
	var out := ""
	for line in (load(SHADER_PATH) as Shader).code.split("\n"):
		var at := line.find("//")
		out += (line if at < 0 else line.substr(0, at)) + "\n"
	return out


# Every mix() call's DIRECT arguments, with nested calls stripped to their name. So
# `mix(wave(p, ts, water_shallow_wave_scale), ..., d)` yields "wave", not the global inside it --
# passing a phase knob DOWN into a wave field is the fix, while passing it to mix() is the bug, and
# a line-level text match cannot tell those two apart.
func _mix_arguments(code: String) -> PackedStringArray:
	var out := PackedStringArray()
	var from := 0
	while true:
		var at := code.find("mix(", from)
		if at < 0:
			break
		from = at + 4
		var depth := 0
		var arg := ""
		var i := from
		while i < code.length():
			var c := code[i]
			if c == ")":
				if depth == 0:
					break
				depth -= 1
			elif c == "(":
				depth += 1
			elif c == "," and depth == 0:
				out.append(arg)
				arg = ""
			elif depth == 0:
				arg += c
			i += 1
		out.append(arg)
	return out


# #646. A PARAMETER THAT SETS PHASE CANNOT BE INTERPOLATED ACROSS SPACE; ONE THAT SETS AMPLITUDE CAN.
#
# Slice 2b made every knob pair mix() on the mask's depth value so the shallow/deep boundary would
# glide rather than snap, and that is right for the amplitudes. For wave scale and wave speed it made
# the surface a CHIRP: a sinusoid's frequency and phase rate do not lerp, so the transition cell got
# ~7 extra periods of phase crammed into it, growing with distance from the world origin and growing
# again with TIME without bound. The bands, the shoreline and the specular all ringed at once,
# because all three read the same wave value.
#
# What this does NOT catch, said out loud rather than left to be discovered: it pins the mix()
# SPELLING, so a hand-rolled `a * (1.0 - d) + b * d` would chirp exactly the same way and pass here.
# That blind spot is confirmed by a mutant rather than asserted -- see the PR.
func test_no_phase_knob_is_interpolated_across_a_seam() -> void:
	# The category holds exactly what it says it holds, both directions -- a renamed wave knob goes
	# missing, and a member the shader no longer declares is a law pointing at nothing.
	var phase_side: Array[String] = []
	for name in _declared_globals():
		if name.ends_with("_wave_speed") or name.ends_with("_wave_scale"):
			phase_side.append(name)
	assert_array(phase_side).override_failure_message(
			"the phase-knob category is declared as %s and the shader's is %s" \
			% [PHASE_GLOBALS, phase_side]).contains_exactly_in_any_order(PHASE_GLOBALS)

	var args := _mix_arguments(_shader_code_without_comments())
	assert_int(args.size()).override_failure_message(
			"the shader contains no mix() calls at all; the case is vacuous").is_greater(0)

	var offenders: Array[String] = []
	for arg in args:
		for name: String in PHASE_GLOBALS:
			if arg.contains(name):
				offenders.append("%s, in mix(... %s ...)" % [name, arg.strip_edges()])
	assert_array(offenders).override_failure_message(
			"a phase knob is being interpolated across the depth seam (%s) -- that varies a " \
			% ", ".join(offenders) + "sinusoid's frequency and phase rate per fragment, which " \
			+ "chirps the surface into rings along the boundary and tightens them as TIME runs. " \
			+ "Evaluate both wave fields and mix the RESULT instead").is_empty()
