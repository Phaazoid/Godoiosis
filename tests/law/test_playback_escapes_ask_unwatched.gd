# Every playback escape asks Pacing.unwatched() (#545). A skip IS the headless escape switched on at
# runtime, so an escape still spelling the headless check by hand is one the skip silently cannot
# reach: that beat, pan or fall plays at full length behind the fade while everything else collapses.
#
# A source law because no headless case can see it -- unwatched() is true for every case either way.
extends GdUnitTestSuite

# The files whose escapes are PLAYBACK's. Other headless checks (telemetry, the uploader, the
# hand-off banner's frame wait) answer a different question and stay as they are.
const PLAYBACK_FILES: Array[String] = [
	"res://Classes/core/Pacing.gd",
	"res://Classes/board/CameraController.gd",
	"res://Classes/presentation/CameraRig3D.gd",
	"res://Classes/units/MovementComponent.gd",
	"res://Classes/actions/OrderExecutor.gd",   # the battle zoom's wait for the camera (#1132 follow-up)
]

const DOOR := "res://Classes/core/Pacing.gd"
const SPELLINGS: Array[String] = ['get_name() == "headless"', 'get_name() != "headless"']


func test_no_playback_escape_spells_headless_past_the_one_predicate() -> void:
	var offences: Array[String] = []
	for path: String in PLAYBACK_FILES:
		var allowed := 1 if path == DOOR else 0
		var count := 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			for spelling: String in SPELLINGS:
				if code.contains(spelling):
					count += 1
		if count != allowed:
			offences.append("%s spells the headless check %d time(s), expected %d" % [
					path.get_file(), count, allowed])
	assert_array(offences).override_failure_message(
		"A playback escape bypasses Pacing.unwatched(), so a skip cannot reach it:\n  "
		+ "\n  ".join(offences)).is_empty()


# Non-vacuity: every file still HAS an escape, and it asks the predicate.
func test_every_playback_file_still_asks_the_predicate() -> void:
	for path: String in PLAYBACK_FILES:
		if path == DOOR:
			continue
		assert_bool(FileAccess.get_file_as_string(path).contains("Pacing.unwatched()")) \
			.override_failure_message("%s no longer asks Pacing.unwatched()" % path.get_file()) \
			.is_true()
