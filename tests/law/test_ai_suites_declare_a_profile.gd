# Every AI suite declares the AI profile its units play (#1230). An unassigned unit plays the SHIPPED
# Hard band, which the dev tunes in the inspector -- so a suite that left it unassigned would redden
# the first time he retunes a band, on a case about something else (the content razor, and #449's
# "a suite declares its branch"). Seventeen of these suites build their units through the production
# board builder, so no test-support helper could declare it for them.
extends GdUnitTestSuite

const SUITES := "res://tests/ai/"


func test_every_ai_suite_sets_and_clears_its_profile_fixture() -> void:
	var scanned := 0
	var offences: Array[String] = []
	for file: String in DirAccess.get_files_at(SUITES):
		if not file.ends_with(".gd"):
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string(SUITES + file)
		if not text.contains("AIProfiles.use_fixtures("):
			offences.append("%s: never calls AIProfiles.use_fixtures" % file)
		if not text.contains("AIProfiles.clear_fixtures()"):
			offences.append("%s: never calls AIProfiles.clear_fixtures, so its fixture leaks into the next suite" % file)

	assert_array(offences).override_failure_message(
		"An AI suite must say which profile its units play -- AIProfiles.use_fixtures in before_test, "
		+ "clear_fixtures in after_test:\n  " + "\n  ".join(offences)).is_empty()
	assert_int(scanned).override_failure_message(
		"the scan found no AI suites -- SUITES is wrong, not the repo").is_greater(10)
