# The one writer behind every "keep this value" button (#272, widened by #373). Pure string
# transforms, so they are tested as such -- no file, no host, no scene.
#
# The bug worth catching here is not a wrong write, it is a write that DOES NOT HAPPEN: a
# declaration the rewriter cannot find must come back as "", so the caller reports a failure,
# never as the source unchanged -- which a caller would happily save and call success. Every case
# below that asserts is_empty() is that one bug wearing a different hat.
#
# Three shapes, because a game constant is authored three ways: an @export default, a static var,
# and one entry of a const table (BoardOverlays.LAYERS) that has no var to name at all. Whether a
# TABLE'S rows really are findable in the real files is a different question, asked per table by
# test_game_knobs.gd against the source on disk.
extends GdUnitTestSuite

const PLAIN := """extends Node3D

@export var block_height_scale := 1.0
@export var other := 2.0
"""

const WITH_SETTER := """extends Node3D

@export var cover_scale := 0.5: set = _set_cover_scale
"""

const TYPED := """extends Node3D

@export var cover_scale: float = 0.5
"""

const VECTOR := """extends Node3D

@export var flame_size := Vector2(0.5, 0.7): set = _set_flame_size
"""


# --- The rewriter ------------------------------------------------------------------------

func test_a_plain_export_default_is_rewritten() -> void:
	var out := KnobSource.rewrite_declaration_default(PLAIN, "block_height_scale", "0.62")
	assert_str(out).contains("@export var block_height_scale := 0.62")
	# The neighbouring declaration is untouched: a rewrite edits ONE line, not the block around it.
	assert_str(out).contains("@export var other := 2.0")


# Two of the three knobs own a setter, and the setter is what makes them live knobs at all -- a
# rewrite that dropped the suffix would leave a slider that moves nothing on the board.
func test_a_setter_suffix_survives_the_rewrite() -> void:
	var out := KnobSource.rewrite_declaration_default(WITH_SETTER, "cover_scale", "0.62")
	assert_str(out).is_equal("""extends Node3D

@export var cover_scale := 0.62: set = _set_cover_scale
""")


func test_a_typed_export_default_is_rewritten() -> void:
	var out := KnobSource.rewrite_declaration_default(TYPED, "cover_scale", "0.62")
	assert_str(out).contains("@export var cover_scale: float = 0.62")


# The comment is documentation the save was never asked to touch (#378: the first real Save
# deleted billboard_lift's). Whitespace before the # rides with it, so the comment column holds.
func test_a_trailing_comment_survives_the_rewrite() -> void:
	var commented := """extends Node3D

@export var fill_lift := 0.02          # quad height above the top face -- the z-fight gap
"""
	var out := KnobSource.rewrite_declaration_default(commented, "fill_lift", "0.04")
	assert_str(out).is_equal("""extends Node3D

@export var fill_lift := 0.04          # quad height above the top face -- the z-fight gap
""")


# Both suffixes at once, in their original order -- the setter is code and the comment is prose,
# and a rewrite that reordered them would not parse.
func test_a_setter_and_a_comment_survive_together() -> void:
	var both := """extends Node3D

@export var tuft_scale := 1.0: set = _set_tuft_scale   # stands the plants up (#280)
"""
	var out := KnobSource.rewrite_declaration_default(both, "tuft_scale", "1.3")
	assert_str(out).is_equal("""extends Node3D

@export var tuft_scale := 1.3: set = _set_tuft_scale   # stands the plants up (#280)
""")


# A comment may SAY ": set = _x" without BEING a setter. The value group refusing to cross a #
# is what makes this unambiguous -- without it, backtracking can hand half the comment to the
# setter group and the rewrite reassembles a line that never existed.
func test_a_comment_naming_a_setter_is_not_eaten_as_one() -> void:
	var tricky := """extends Node3D

@export var flame_lift := 0.5   # tuned live; the writer is: set = _set_flame_lift on the mirror
"""
	var out := KnobSource.rewrite_declaration_default(tricky, "flame_lift", "0.7")
	assert_str(out).is_equal("""extends Node3D

@export var flame_lift := 0.7   # tuned live; the writer is: set = _set_flame_lift on the mirror
""")


# A multi-argument literal must not be mistaken for the start of the setter suffix.
func test_a_vector_literal_is_rewritten_whole() -> void:
	var out := KnobSource.rewrite_declaration_default(VECTOR, "flame_size", "Vector2(0.4, 0.9)")
	assert_str(out).is_equal("""extends Node3D

@export var flame_size := Vector2(0.4, 0.9): set = _set_flame_size
""")


# THE case. Returning the source unchanged would be indistinguishable from a successful no-change
# save, so "not found" has to be representable as something a caller cannot mistake for success.
func test_an_unknown_property_returns_empty_rather_than_the_source() -> void:
	var out := KnobSource.rewrite_declaration_default(PLAIN, "renamed_since", "0.62")
	assert_str(out).override_failure_message(
		"a property the rewriter cannot find must return \"\", or a no-op write reads as a save").is_empty()


# A component path (flame_size:x) has no declaration line of its own -- "x = 0.4" is not a thing a
# script can say. Refused loudly rather than half-written.
func test_a_component_path_is_refused() -> void:
	assert_str(KnobSource.rewrite_declaration_default(VECTOR, "flame_size:x", "0.4")).is_empty()


# ...which is why the save path asks a different question first. A component knob's DECLARATION is
# the vector's, so both axis knobs resolve to one line and one write.
func test_a_component_knob_resolves_to_the_declaration_it_shares() -> void:
	var width := {"node": "BoardMirror", "prop": "flame_size:x", "label": "Flame width"}
	var height := {"node": "BoardMirror", "prop": "flame_size:y", "label": "Flame height"}
	assert_str(KnobSource.declaration_prop(width)).is_equal("flame_size")
	assert_str(KnobSource.declaration_prop(height)).is_equal(
		KnobSource.declaration_prop(width))


func test_a_plain_knob_declares_itself() -> void:
	assert_str(KnobSource.declaration_prop(
		{"node": "BoardMirror", "prop": "cover_scale"})).is_equal("cover_scale")



# --- The static var form (#373) ------------------------------------------------------------
#
# The reach colours and the squad ring's alpha are statics on OverlayManager, not exports -- and
# static is what they HAVE to be, since attack_reach_color is static and reads them. Which prefix a
# declaration wears is a fact about the source rather than about the caller, so one pattern answers
# both; these cases are what say that out loud.

const STATIC_COLOR := """extends Node2D

static var ATTACK_MODULATE := Color(1, 0, 0, .5)
static var HEAL_ATTACK_MODULATE := Color(0, 1, 0, .5)
"""


func test_a_static_var_default_is_rewritten() -> void:
	var out := KnobSource.rewrite_declaration_default(
		STATIC_COLOR, "ATTACK_MODULATE", "Color(0.2, 0.4, 0.9, 0.6)")
	assert_str(out).contains("static var ATTACK_MODULATE := Color(0.2, 0.4, 0.9, 0.6)")
	# Its neighbour is left exactly as authored, shorthand floats and all: a rewrite edits ONE line.
	assert_str(out).contains("static var HEAL_ATTACK_MODULATE := Color(0, 1, 0, .5)")


func test_an_unknown_static_returns_empty_rather_than_the_source() -> void:
	assert_str(KnobSource.rewrite_declaration_default(
		STATIC_COLOR, "RENAMED_SINCE", "Color(1, 1, 1, 1)")).is_empty()


# --- The LAYERS entry form (#373) ----------------------------------------------------------
#
# A layer's colour is a field of a const dictionary, so there is no declaration line to find -- the
# rewriter has to hit one KEY'S entry and only its colour. Two things it must not do: touch a
# neighbouring layer, and disturb sort or kind, which carry the relationships #231 pinned.

const LAYERS_TABLE := """extends Node3D

const LAYERS: Dictionary[Layer, Dictionary] = {
	Layer.MOVE: {"color": Color(1, 1, 0, 0.5), "sort": 0, "kind": Kind.FILL},
	Layer.ATTACK: {"color": Color(1, 0, 0, 0.5), "sort": 1, "kind": Kind.FILL},
	Layer.ZONE_PATROL: {"color": OverlayManager.ZONE_PATROL_MODULATE, "sort": -3, "kind": Kind.FILL},
}
"""


func test_a_layer_colour_is_rewritten_in_place() -> void:
	var out := KnobSource.rewrite_layer_color(LAYERS_TABLE, "MOVE", "Color(1.0, 1.0, 0.0, 0.35)")
	assert_str(out).contains(
		'Layer.MOVE: {"color": Color(1.0, 1.0, 0.0, 0.35), "sort": 0, "kind": Kind.FILL},')


# The commas inside Color(...) are why the value cannot be matched as "up to the next comma", and
# this is the case that would catch it: a greedy or comma-bounded match eats the rest of the row.
func test_a_layer_rewrite_leaves_sort_and_kind_alone() -> void:
	var out := KnobSource.rewrite_layer_color(LAYERS_TABLE, "ATTACK", "Color(0.0, 0.0, 1.0, 1.0)")
	assert_str(out).contains('"sort": 1, "kind": Kind.FILL},')
	assert_str(out).contains('Layer.MOVE: {"color": Color(1, 1, 0, 0.5),')   # its neighbour, intact


# A constant reference is a legal authored value, so the rewriter has to replace one of those too
# rather than only matching a literal call.
func test_a_layer_holding_a_constant_reference_is_still_rewritten() -> void:
	var out := KnobSource.rewrite_layer_color(
		LAYERS_TABLE, "ZONE_PATROL", "Color(0.5, 0.5, 0.5, 0.5)")
	assert_str(out).contains(
		'Layer.ZONE_PATROL: {"color": Color(0.5, 0.5, 0.5, 0.5), "sort": -3, "kind": Kind.FILL},')


func test_an_unknown_layer_returns_empty_rather_than_the_source() -> void:
	assert_str(KnobSource.rewrite_layer_color(
		LAYERS_TABLE, "RENAMED_SINCE", "Color(1, 1, 1, 1)")).is_empty()


# The whole point of the format being fragile in a KNOWN way: reformat LAYERS to multi-line entries
# and every colour save must fail loudly rather than write the wrong line or silently do nothing.
func test_a_reformatted_layers_table_refuses_rather_than_guessing() -> void:
	var reformatted := """const LAYERS := {
	Layer.MOVE: {
		"color": Color(1, 1, 0, 0.5),
	},
}
"""
	assert_str(KnobSource.rewrite_layer_color(reformatted, "MOVE", "Color(1, 1, 1, 1)")).is_empty()


# --- The SETTING_DEFAULT shape (#394) ------------------------------------------------------
#
# The third shape, and the first whose write is NOT where the value was read from: a player setting's
# live value belongs to the store, and what this rewrites is only what someone who never opens the
# options page gets.

const DEFS_TABLE := """extends Object

const DEFS := {
	Setting.SHOW_DIALOG: {
		"title": "Show mission dialog",
		"desc": "Characters speak during missions.",
		"default": true,
	},
	Setting.UNHOVERED_BAR_NUMBERS: {
		"title": "Numbers on unhovered bars",
		"desc": "Show the HP digits.",
		"default": false,
	},
}
"""

func test_a_setting_default_is_rewritten() -> void:
	var out := KnobSource.rewrite_setting_default(DEFS_TABLE, "UNHOVERED_BAR_NUMBERS", "true")
	assert_str(out).contains("\"default\": true,\n\t},\n}")
	# ...and the row ABOVE it is untouched, which is the whole risk of a multi-line entry match.
	assert_str(out).override_failure_message(
			"rewriting one setting's default moved another's").contains(
			"\"title\": \"Show mission dialog\"")
	assert_str(out).contains("Characters speak during missions.")

func test_the_entry_above_keeps_its_own_default() -> void:
	# The sibling half of the case above, stated as the value rather than the labels: SHOW_DIALOG
	# defaults true and must still, after its neighbour is written to.
	var out := KnobSource.rewrite_setting_default(DEFS_TABLE, "UNHOVERED_BAR_NUMBERS", "true")
	var dialog_entry := out.substr(out.find("Setting.SHOW_DIALOG"))
	dialog_entry = dialog_entry.substr(0, dialog_entry.find("},"))
	assert_str(dialog_entry).override_failure_message(
			"SHOW_DIALOG's own default was rewritten instead").contains("\"default\": true")

func test_an_unknown_setting_returns_empty_rather_than_the_source() -> void:
	assert_str(KnobSource.rewrite_setting_default(DEFS_TABLE, "NOT_A_SETTING", "true")).is_empty()

func test_a_setting_whose_entry_has_no_default_cannot_reach_the_next_ones() -> void:
	# THE case this shape is written around. The search is bounded to the entry's own braces, so a
	# row that has somehow lost its "default" key FAILS -- rather than running on and quietly
	# rewriting whichever sibling declares one next, which no caller could detect.
	var missing := """const DEFS := {
	Setting.BROKEN: {
		"title": "No default here",
	},
	Setting.SHOW_DIALOG: {
		"default": true,
	},
}
"""
	assert_str(KnobSource.rewrite_setting_default(missing, "BROKEN", "false")).override_failure_message(
			"the search escaped a defaultless entry and reached a sibling's default").is_empty()

func test_a_setting_name_that_is_not_an_identifier_is_refused() -> void:
	assert_str(KnobSource.rewrite_setting_default(DEFS_TABLE, "Setting.X", "true")).is_empty()

func test_every_setting_knob_is_findable_in_the_real_defs_table() -> void:
	# The table law, the shape test_game_knobs.gd uses for the other two kinds: a row naming a
	# Setting whose DEFS entry cannot be rewritten is a Save that reports success and writes nothing.
	var source := FileAccess.get_file_as_string(GameKnobs.SETTINGS_SCRIPT)
	assert_str(source).override_failure_message("could not read PlayerSettings.gd").is_not_empty()
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		if not knob.has("setting"):
			continue
		var name: String = PlayerSettings.Setting.keys()[knob["setting"]]
		assert_str(KnobSource.rewrite_setting_default(source, name, "false")).override_failure_message(
				"%s has no rewritable \"default\" in PlayerSettings.DEFS" % name).is_not_empty()
