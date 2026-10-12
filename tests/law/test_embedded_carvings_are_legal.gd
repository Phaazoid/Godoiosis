# Every rune and carving a SAVED SCENARIO puts in a unit's hands is legal under the rules that load it
# (RuneData.is_legal, TransmutationData.is_legal). Deep Alchemy Phase 2 (2026-10-11) replaced a
# carving's sigils with a recipe line, and a scenario EMBEDS its runes -- a snapshot entry carries
# its own copy of the inventory, and an embedded character carries its own starting kit -- so the
# catalogs' own guard (tests/items/test_alchemy_catalogs.gd) cannot see those runes. Their carvings
# are library references since #1313, which that guard does read, but a rune is still the scenario's
# own: one resized below its carvings, or tempered against one, loads as a rune is_legal refuses, and
# nothing else says so (the embedded-content sweep rule, CLAUDE.md).
#
# Walks every scenario file the real scan finds (ScenarioManager.get_saved_scenarios, recursive --
# tests/flow/test_scenario_load_integrity.gd's precedent), so a new mission or fixture is covered
# with no per-file maintenance. It LOADS authored content on purpose and asserts nothing about what
# it contains -- no rune, recipe, count or name (tests/README.md rule 9). A repo carrying no
# carvings at all passes, and says so (rule 9's #596 clause).
extends GdUnitTestSuite


func _scenario_paths() -> Array[String]:
	var manager: ScenarioManager = auto_free(ScenarioManager.new())
	return manager.get_saved_scenarios()


# Every rune a scenario entry hands its unit: the entry's own saved inventory (a snapshot), plus the
# character's starting kit (what a reference entry spawns with, and what an embedded character
# still carries).
func _runes_of(entry: ScenarioUnitEntry) -> Array[RuneData]:
	var items: Array[Item] = []
	items.append_array(entry.inventory)
	if entry.unit_data != null:
		items.append_array(entry.unit_data.starting_inventory)
	var runes: Array[RuneData] = []
	for item: Item in items:
		var rune := item as RuneData
		if rune != null:
			runes.append(rune)
	return runes


func _where(path: String, index: int, entry: ScenarioUnitEntry, rune: RuneData) -> String:
	var who := entry.unit_data.display_name if entry.unit_data != null else "?"
	return "%s [entry %d, %s] rune '%s'" % [path.trim_prefix("res://"), index, who, rune.display_name]


# Why a carving is illegal, in the parse's own words where it has them -- the message names the fix.
static func _why(carving: TransmutationData) -> String:
	if carving.recipe_error() != "":
		return carving.recipe_error()
	return "%d verbs, past the largest circle cap of %d" % [carving.cost(), RuneData.max_circle_cap()]


func test_the_scan_finds_saved_scenarios() -> void:
	# Guards the sweep below against passing vacuously because the folder scan broke -- a fact about
	# the SCAN, not about what the dev has authored.
	assert_array(_scenario_paths()).override_failure_message(
		"no scenario files scanned -- the scan is broken, not the content").is_not_empty()


func test_every_embedded_rune_and_carving_is_legal() -> void:
	var problems: Array[String] = []
	var carvings_seen := 0
	for path: String in _scenario_paths():
		var scenario := load(path) as ScenarioData
		if scenario == null:
			continue   # test_scenario_load_integrity owns an unloadable file
		for i in scenario.unit_entries.size():
			var entry: ScenarioUnitEntry = scenario.unit_entries[i]
			if entry == null:
				continue
			for rune: RuneData in _runes_of(entry):
				var where := _where(path, i, entry, rune)
				for carving: TransmutationData in rune.inscriptions:
					if carving == null:
						problems.append("%s: an inscription is null" % where)
						continue
					carvings_seen += 1
					if not carving.is_legal():
						var carving_name := carving.display_name if carving.display_name != "" else "(unnamed)"
						problems.append("%s carving '%s' (recipe \"%s\"): %s"
							% [where, carving_name, carving.recipe, _why(carving)])
				if not rune.is_legal():
					problems.append(where + ": the rune breaks its own rules (RuneData.is_legal: "
						+ "capacity, circle cap, legal inscriptions, temper)")
	assert_array(problems).override_failure_message(
		("%d embedded rune/carving fault(s) -- each loads as content its own rules refuse. Re-author "
		+ "the copy in the scenario (or the character it embeds):\n  %s")
		% [problems.size(), "\n  ".join(problems)]).is_empty()
	if carvings_seen == 0:
		push_warning("no saved scenario carries a carving, so this sweep checked nothing")
