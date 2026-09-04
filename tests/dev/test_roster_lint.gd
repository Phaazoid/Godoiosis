# RosterLint's teeth (#735), plus the sweep over every shipped roster.
#
# Nothing here pins authored content (tests/README.md #9): the sweep asserts a PROPERTY every
# roster must hold, and the fixture cases build their own rosters in memory so a rule's teeth do
# not depend on what happens to be authored today.
extends GdUnitTestSuite

const CAST := "res://tests/support/CastFixture.tres"


func _entry(state_saved: bool) -> ScenarioUnitEntry:
	var entry := ScenarioUnitEntry.new()
	entry.unit_data = load(CAST)
	entry.state_saved = state_saved
	return entry


# A reference entry is the shape a roster member normally has: point at the character file and let
# its starting kit be the whole answer.
func _reference_roster() -> Roster:
	var roster := Roster.new()
	roster.entries = [_entry(false)]
	return roster


func _texts(findings: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for finding: Dictionary in findings:
		out.append(finding["text"])
	return "\n".join(out)


func test_a_plain_reference_roster_is_clean() -> void:
	assert_array(RosterLint.check(_reference_roster())).is_empty()


func test_no_roster_is_not_a_defective_roster() -> void:
	# BoardLint owns "this board names a roster that isn't there"; a null here is just absence.
	assert_array(RosterLint.check(null)).is_empty()


# --- The hollow snapshot: the easiest mistake in the file and the hardest to see ---

func test_a_snapshot_that_captured_nothing_is_found() -> void:
	# state_saved defaults TRUE in the inspector, so this is what "add a character and leave the
	# tick" produces. apply_unit_state would then fill the inventory with nulls, unequip, and set
	# jobs to [] -- replacing the character's own starting kit with the empty snapshot.
	var roster := Roster.new()
	roster.entries = [_entry(true)]
	var findings := RosterLint.check(roster)
	assert_int(findings.size()).override_failure_message(_texts(findings)).is_equal(1)
	assert_int(findings[0]["severity"]).is_equal(RosterLint.Severity.DEGRADES)
	assert_str(findings[0]["text"]).contains("state_saved")


func test_a_snapshot_that_captured_something_is_clean() -> void:
	# The rule is "captured NOTHING", not "is a snapshot" -- a roster entry carrying real per-mission
	# state is the whole point of rosters being plural (#731's balance-testing lever).
	var entry := _entry(true)
	entry.stats = {Stats.Stat.STR: 9}
	var roster := Roster.new()
	roster.entries = [entry]
	assert_array(RosterLint.check(roster)).is_empty()


# --- One job at a time, bound at the roster (#731 ruling 10) ---

func test_two_jobs_on_a_snapshot_entry_are_found() -> void:
	var entry := _entry(true)
	entry.stats = {Stats.Stat.STR: 9}   # so the hollow-snapshot rule stays quiet and this case is alone
	entry.jobs = ["a", "b"]
	var findings := RosterLint.check(_roster_of(entry))
	assert_int(findings.size()).override_failure_message(_texts(findings)).is_equal(1)
	assert_int(findings[0]["severity"]).is_equal(RosterLint.Severity.DEGRADES)
	assert_str(findings[0]["text"]).contains("2 jobs")


func test_the_effective_list_is_the_character_file_for_a_reference_entry() -> void:
	# The teeth of effective_jobs: a reference entry's own `jobs` is empty and never applied --
	# apply_unit_state only runs when state_saved -- so the jobs it deploys with are the ones
	# _seed_starting_kit adds from UnitData.starting_jobs. Reading entry.jobs here would report a
	# two-job character as clean.
	var entry := _entry(false)
	var data: UnitData = entry.unit_data.duplicate()   # never mutate the shared cached fixture
	data.starting_jobs = ["a", "b"]
	entry.unit_data = data
	var findings := RosterLint.check(_roster_of(entry))
	assert_int(findings.size()).override_failure_message(_texts(findings)).is_equal(1)
	assert_str(findings[0]["text"]).contains("2 jobs")


func test_one_job_is_clean_in_both_entry_shapes() -> void:
	var snapshot := _entry(true)
	snapshot.stats = {Stats.Stat.STR: 9}
	snapshot.jobs = ["a"]
	assert_array(RosterLint.check(_roster_of(snapshot))).is_empty()

	var reference := _entry(false)
	var data: UnitData = reference.unit_data.duplicate()
	data.starting_jobs = ["a"]
	reference.unit_data = data
	assert_array(RosterLint.check(_roster_of(reference))).is_empty()


# --- Battle state, which a unit on no board cannot have ---

func test_battle_state_on_a_roster_entry_is_found_and_named() -> void:
	var entry := _entry(true)
	entry.stats = {Stats.Stat.STR: 9}
	entry.in_crisis = true
	entry.rally_count = 2
	var findings := RosterLint.check(_roster_of(entry))
	assert_int(findings.size()).override_failure_message(_texts(findings)).is_equal(1)
	assert_str(findings[0]["text"]).contains("in_crisis")
	assert_str(findings[0]["text"]).contains("rally_count")


func test_an_empty_entry_is_found_rather_than_crashing() -> void:
	var roster := Roster.new()
	roster.entries = [null]
	var findings := RosterLint.check(roster)
	assert_int(findings.size()).is_equal(1)
	assert_str(findings[0]["text"]).contains("empty")


# --- The sweep over what actually ships ---

func test_every_shipped_roster_is_authored_cleanly() -> void:
	# Non-vacuity first, and it is not decoration: files_with_extension returns [] for a folder that
	# does not exist, so without this the sweep below passes over nothing and proves nothing. Same
	# guard test_attack_lint.gd carries for the same reason.
	var names := RosterCatalog.saved_rosters()
	assert_bool(names.is_empty()).override_failure_message(
		"no rosters found in %s -- the sweep below would pass over nothing"
			% RosterCatalog.ROSTER_DIR).is_false()

	var problems: Array[String] = []
	for name: String in names:
		var roster := RosterCatalog.resolve(name)
		assert_object(roster).override_failure_message(
			"roster '%s' is listed but did not load" % name).is_not_null()
		for finding: Dictionary in RosterLint.check(roster):
			problems.append("%s: %s" % [name, finding["text"]])
	assert_array(problems).is_empty()


func _roster_of(entry: ScenarioUnitEntry) -> Roster:
	var roster := Roster.new()
	roster.entries = [entry]
	return roster
