# Scenario load must survive a unit whose resource no longer resolves (#13): it loads back as
# null, and ScenarioManager.valid_entries drops it (with a push_error) so load_scenario never
# null-derefs. Pure/static — no game scene needed.
extends GdUnitTestSuite

func test_valid_entries_skips_null_unit_data() -> void:
	var scenario := ScenarioData.new()
	var good := ScenarioUnitEntry.new()
	good.unit_data = UnitData.new()
	scenario.unit_entries.append(ScenarioUnitEntry.new())  # unit_data left null = unresolved
	scenario.unit_entries.append(good)

	var kept := ScenarioManager.valid_entries(scenario)

	assert_int(kept.size()).is_equal(1)
	assert_object(kept[0]).is_same(good)

func test_valid_entries_keeps_all_when_none_missing() -> void:
	var scenario := ScenarioData.new()
	var a := ScenarioUnitEntry.new()
	a.unit_data = UnitData.new()
	var b := ScenarioUnitEntry.new()
	b.unit_data = UnitData.new()
	scenario.unit_entries.append(a)
	scenario.unit_entries.append(b)

	assert_int(ScenarioManager.valid_entries(scenario).size()).is_equal(2)

func test_new_entry_defaults_to_jobless() -> void:
	# Pins the additive-export safety net (#58, simplified #61): an old scenario's entries,
	# which never wrote this field, load with exactly this default — load_scenario needs no
	# migration.
	var entry := ScenarioUnitEntry.new()
	assert_bool(entry.jobs.is_empty()).is_true()
