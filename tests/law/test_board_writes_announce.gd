# No production code may write the board grid without announcing it (#319).
#
# The 3D mirror reconciles only the cells a writer marked through BoardGrid.paint()/erase()/reset().
# A writer that reaches past those doors to the raw TileMapLayer API still changes the 2D board, and
# the diorama simply never hears about it — so the symptom is a SILENT WRONG RENDER, not a crash and
# not a slowdown. Nothing else in the suite can see that: every existing case that would catch it
# now uses the doors itself.
#
# This is the guarantee the poll used to get structurally. It re-walked the whole board every frame,
# so it caught every writer with no trigger site to remember; that walk cost Prolog a whole 60fps
# frame budget (docs/performance.md -> "board size and the 3D authoring poll"). The speed was worth
# the trade only if the guarantee came back as a law, so here it is.
#
# DECLARED EXCEPTION: ScenarioManager assigns `tile_map_data` wholesale on every board load. A
# property assignment cannot be doored at all, and it is safe because a load emits board_loaded ->
# battle3d.rebuild(), which full-syncs. It is matched by neither pattern below, so it needs no
# allow-listing — but a SECOND bulk writer would need the same rebuild guarantee, and this comment
# is where that gets checked.
extends GdUnitTestSuite

# Production only. tests/ deliberately writes raw grids in fixtures that no mirror ever reads, and
# addons/ is vendored.
const SCANNED: Array[String] = ["res://Classes/", "res://Scenes/", "res://play/", "res://game.gd"]

# BoardGrid is where the doors live, so it is the one file that must call the raw API.
const DOOR := "res://Classes/board/BoardGrid.gd"

# The raw writes, both matched only on a GRID-NAMED RECEIVER. Both halves of that were measured
# rather than assumed, by this law's own first two runs:
#   - `set_cell` is not unique to TileMapLayer here (BoardHeights and MovementComponent both have
#     one), so the bare name flagged seven false positives.
#   - `erase_cell` IS TileMapLayer-only, but the board grid is not the only TileMapLayer: every
#     overlay is one too, and OverlayManager legitimately erases cells on them.
#
# The stated limit, since a source scan cannot know a receiver's type: a writer holding the board
# grid under a name not ending in "grid" slips past. Every production holder is `grid` or
# `game.grid` today. This is a backstop for review, not a proof. `clear(` is left out entirely --
# far too common a method name to match on at all.
const FORBIDDEN_PATTERNS: Array[String] = [
	"(?i)\\bgrid\\s*\\.\\s*set_cell\\s*\\(",
	"(?i)\\bgrid\\s*\\.\\s*erase_cell\\s*\\(",
]


func test_no_production_writer_reaches_past_the_board_grid_doors() -> void:
	var scanned := 0
	var offences: Array[String] = []
	var matchers: Array[RegEx] = []
	for pattern: String in FORBIDDEN_PATTERNS:
		matchers.append(RegEx.create_from_string(pattern))
	for path: String in _scripts():
		scanned += 1
		if path == DOOR:
			continue
		var text := FileAccess.get_file_as_string(path)
		var line_no := 0
		for line: String in text.split("\n"):
			line_no += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			for matcher: RegEx in matchers:
				if matcher.search(code) != null:
					offences.append("%s:%d  %s" % [path.get_file(), line_no, code])

	assert_array(offences).override_failure_message(
		"These write the board past BoardGrid's doors, so the 3D mirror never hears about them "
		+ "and silently renders a stale cell. Use paint()/erase()/reset() instead:\n  "
		+ "\n  ".join(offences)
	).is_empty()

	# Non-vacuity, the test_resource_uid_references.gd shape: without it an empty or mis-rooted
	# scan passes this suite while proving nothing at all.
	assert_int(scanned).override_failure_message(
		"the scan found no production scripts -- SCANNED is wrong, not the repo"
	).is_greater(20)


# The other half of non-vacuity, and the one that would actually rot: this law is worthless if
# BoardGrid stops being the thing that writes cells. Asserting the door FILE contains the raw calls
# proves the pattern above still matches something real.
func test_the_door_itself_still_makes_the_raw_calls() -> void:
	var door := FileAccess.get_file_as_string(DOOR)
	assert_bool(door.contains("set_cell(")).override_failure_message(
		"BoardGrid no longer calls set_cell -- either it was renamed, or the pattern this law "
		+ "scans for stopped matching anything, which makes the law above vacuous."
	).is_true()
	assert_bool(door.contains("erase_cell(")).is_true()


func _scripts() -> Array[String]:
	var found: Array[String] = []
	for root: String in SCANNED:
		if root.ends_with(".gd"):
			found.append(root)
			continue
		_walk(root, found)
	return found


func _walk(dir_path: String, found: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full, found)
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
