# The invariant a shared test fixture rests on (#622): NO STATIC HOLDS BOARD-SCOPED STATE UNLESS
# clear_board RESETS IT.
#
# Why this is a law and not a comment. `clear_board()` is the reset door, and it is correct -- but
# it is HAND-MAINTAINED, and every line in it cites the leak it was added for: the Prolog accident
# (stale last_loaded_path), a sandbox inheriting the last mission's look (#253), camera start
# (#234), AI factions (#150), a tear-out left in the sky (#521), the playback lock (#484). Each of
# those comments records someone not remembering. A new `static var` holding battle-scoped state is
# covered only if the next person remembers too.
#
# So the classification is forced rather than trusted: a static in the board/presentation domain is
# TUNING (process-scoped by design -- a `static var` rather than a `const` exactly so a knob can
# write it), a CACHE (derived and idempotent), or BOARD-SCOPED (must die with the board). Anything
# in none of the three fails here, naming itself, until its author says which it is.
#
# The tuning arm is DERIVED from GameKnobs.CLASS_KNOBS rather than listed: that table names 98
# statics across the codebase, which covers 19 of the 28 in this domain for free and leaves only
# the 9 below to declare by hand. tests/dev/test_game_knobs.gd already reads the same table the
# same way to snapshot them. Law #4: one enumeration, and the two readers cannot drift.
#
# Scope is board/ + presentation/ deliberately: that is the domain a shared Battle3D fixture would
# share. Widening it is a decision about which suites may share next, not a tidy-up.
extends GdUnitTestSuite

const DOMAIN := ["res://Classes/board", "res://Classes/presentation"]
const SCENARIO_MANAGER := "res://Classes/flow/ScenarioManager.gd"

# Board-scoped state that legitimately lives in a static, each naming the call that must clear it.
# BoardSpace is static because the mirror and the camera rig both read the staging with no board
# reference to hand -- see #622's note that moving it onto a board-owned node is the ideal fix and
# is blocked on exactly that. Until then it is declared here and the second case keeps it honest.
const BOARD_SCOPED := {
	"_staged": "BoardSpace.clear_staging(",
	"_stage_offset": "BoardSpace.clear_staging(",
	"staging_version": "BoardSpace.clear_staging(",
	# The transition (#521 slice B). All of it dies inside clear_staging() itself rather than beside
	# its callers, which is what stops a board swapped mid-flight leaving a column in the sky.
	"_flight": "BoardSpace.clear_staging(",
	"_flight_plan": "BoardSpace.clear_staging(",
	"_flight_elapsed": "BoardSpace.clear_staging(",
	"_flight_from": "BoardSpace.clear_staging(",
	"_flight_to": "BoardSpace.clear_staging(",
	"_flight_entering": "BoardSpace.clear_staging(",
	"_camera_lift": "BoardSpace.clear_staging(",
	"_camera_lift_driven": "BoardSpace.clear_staging(",
}

# Process-scoped and therefore safe to survive a board reset, but NOT named by a knob table.
# Two kinds, and the distinction is worth keeping visible:
#   - derived caches, content-addressed and idempotent; re-deriving costs time, never correctness.
#   - tuning values that no knob reaches. They are `static var` rather than `const` for a knob's
#     sake and no knob arrived, so today nothing can move them -- the inverse of #264's born-dead
#     slider. Harmless to sharing, which is why they sit here rather than failing, but they are
#     real gaps against the 2026-08-12 rule that an aesthetic value gets a knob. Filed separately.
const PROCESS_SCOPED := [
	"_cube_mesh", "_cage_texture", "_cube_key",   # UnitHealthBar: cage geometry, keyed by _cube_key
	"_art_top_cache",                             # UnitSprite3D: per-texture art top, keyed by path
	"_warned_sets",                               # UnitSprite3D: which sets have already warned, keyed by path
	"GUARD_RING_SCALE",                           # tuning, no knob
	"texels_per_unit",                            # tuning, no knob
]


func _statics() -> Dictionary:
	var found := {}   # name -> "File.gd"
	var rx := RegEx.create_from_string("(?m)^static var (\\w+)")
	for dir: String in DOMAIN:
		for file: String in ResourceDir.files_with_extension(dir, "gd"):
			var path := "%s/%s" % [dir, file]
			var f := FileAccess.open(path, FileAccess.READ)
			assert_object(f).override_failure_message("could not read %s" % path).is_not_null()
			var text := f.get_as_text()
			f.close()
			for m: RegExMatch in rx.search_all(text):
				found[m.get_string(1)] = file
	return found


func _knobbed() -> Dictionary:
	var names := {}
	for knob: Dictionary in GameKnobs.CLASS_KNOBS:
		if knob.has("static"):
			names[str(knob["static"])] = true
	return names


# ==============================================================================
#  The law
# ==============================================================================

func test_every_static_in_the_board_domain_declares_what_kind_it_is() -> void:
	var knobbed := _knobbed()
	var unclassified: Array[String] = []
	for name: String in _statics():
		if knobbed.has(name) or PROCESS_SCOPED.has(name) or BOARD_SCOPED.has(name):
			continue
		unclassified.append("%s (%s)" % [name, _statics()[name]])
	assert_array(unclassified).override_failure_message(
		("These statics are classified by nothing: %s\n"
		+ "A static in this domain must be one of three things, and which one decides whether a "
		+ "board reset has to reach it:\n"
		+ "  TUNING       -> give it a GameKnobs.CLASS_KNOBS row (it is then covered here for free)\n"
		+ "  CACHE        -> derived and idempotent; add it to PROCESS_SCOPED with what keys it\n"
		+ "  BOARD-SCOPED -> add it to BOARD_SCOPED naming the call that clears it, and make "
		+ "clear_board() make that call") % ", ".join(unclassified)).is_empty()


func test_every_board_scoped_static_is_actually_reset_by_clear_board() -> void:
	# Declaring something board-scoped and then not clearing it is the failure this half exists for:
	# the declaration above would otherwise be a comment that reads as a guarantee.
	var f := FileAccess.open(SCENARIO_MANAGER, FileAccess.READ)
	assert_object(f).is_not_null()
	var src := f.get_as_text()
	f.close()
	var start := src.find("func clear_board")
	assert_int(start).override_failure_message("clear_board() is gone or renamed").is_greater(-1)
	var end := src.find("\nfunc ", start + 10)
	var body := src.substr(start, (end - start) if end > start else -1)

	var missing: Array[String] = []
	for name: String in BOARD_SCOPED:
		if not body.contains(BOARD_SCOPED[name]):
			missing.append("%s (expected clear_board to call %s)" % [name, BOARD_SCOPED[name]])
	assert_array(missing).override_failure_message(
		"Board-scoped statics nothing resets: %s" % ", ".join(missing)).is_empty()


func test_the_scan_actually_found_something() -> void:
	# Non-vacuity, and not decoration: point DOMAIN at an empty folder, or let the regex stop
	# matching, and BOTH cases above pass over zero statics. tests/dev/test_look_presets.gd carries
	# the same guard for the same reason.
	var statics := _statics()
	# 28 in the domain today. The floor is deliberately well under that -- it is a rot detector,
	# not a census, and a census would fail every time someone adds or removes one.
	assert_int(statics.size()).override_failure_message(
		"the static scan matched nothing -- DOMAIN or the regex has rotted").is_greater(20)
	assert_int(_knobbed().size()).override_failure_message(
		"CLASS_KNOBS named no statics -- the tuning arm has rotted, and every knobbed static "
		+ "would now read as unclassified").is_greater(50)
	# The declared lists must describe things that EXIST; a stale name is a rule guarding nothing.
	var stale: Array[String] = []
	for name: String in BOARD_SCOPED:
		if not statics.has(name):
			stale.append(name)
	for name: String in PROCESS_SCOPED:
		if not statics.has(name):
			stale.append(name)
	assert_array(stale).override_failure_message(
		"declared here but no longer a static in the domain: %s" % ", ".join(stale)).is_empty()
