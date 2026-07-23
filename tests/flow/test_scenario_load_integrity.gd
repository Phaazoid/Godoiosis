# Load-integrity guard over every saved scenario file (#9 — the #80 lesson): a data-model
# change that misses Scenarios/**/*.tres fails HERE, loudly, instead of silently dropping
# fields and breaking weapons in-game weeks later. Pure load() + resource walks — no scene
# instantiation, headless-safe. Iterates whatever files exist, so every new fixture or
# playtest save is covered with zero per-file maintenance.
extends GdUnitTestSuite


func _scenario_paths() -> Array[String]:
	# The real scan (recursive as of #9), so fixtures/ subfolders are covered automatically.
	var manager: ScenarioManager = auto_free(ScenarioManager.new())
	return manager.get_saved_scenarios()


# path -> ScenarioData, silently skipping unloadable files (those fail their own test below).
func _loaded_scenarios() -> Dictionary[String, ScenarioData]:
	var result: Dictionary[String, ScenarioData] = {}
	for path in _scenario_paths():
		var scenario := load(path) as ScenarioData
		if scenario != null:
			result[path] = scenario
	return result


func _entry_label(path: String, index: int, entry: ScenarioUnitEntry) -> String:
	var who: String = "?"
	if entry != null and entry.unit_data != null:
		who = entry.unit_data.display_name
	return "%s [entry %d, %s]" % [path.get_file(), index, who]


func test_scan_finds_saved_scenarios() -> void:
	# Guards every test below against passing vacuously because the folder scan broke.
	assert_array(_scenario_paths()).is_not_empty()


func test_every_scenario_file_loads_as_scenario_data() -> void:
	var problems: Array[String] = []
	for path in _scenario_paths():
		if load(path) as ScenarioData == null:
			problems.append(path)
	assert_array(problems).is_empty()


func test_unit_entries_resolve() -> void:
	# Mirrors ScenarioManager.valid_entries' runtime check (#13), but as a red test instead
	# of a silent skip-with-push_error at load time.
	var problems: Array[String] = []
	var scenarios := _loaded_scenarios()
	for path in scenarios:
		var scenario: ScenarioData = scenarios[path]
		for i in scenario.unit_entries.size():
			var entry: ScenarioUnitEntry = scenario.unit_entries[i]
			if entry == null or entry.unit_data == null:
				problems.append(_entry_label(path, i, entry))
	assert_array(problems).is_empty()


func test_inventory_weapons_resolve_main_attack() -> void:
	# The exact #80 failure, updated for #83's inventory list (was: the single
	# equipped_weapon): embedded weapons whose fields Godot dropped on load leave
	# main_attack unresolvable — a 1-cell reach fallback that refuses counters.
	var problems: Array[String] = []
	var scenarios := _loaded_scenarios()
	for path in scenarios:
		var scenario: ScenarioData = scenarios[path]
		for i in scenario.unit_entries.size():
			var entry: ScenarioUnitEntry = scenario.unit_entries[i]
			if entry == null:
				continue
			for j in entry.inventory.size():
				if entry.inventory[j] == null:
					problems.append("%s: inventory[%d] is null" % [_entry_label(path, i, entry), j])
					continue
				var weapon := entry.inventory[j] as WeaponInstance
				if weapon == null:
					continue  # runes etc. — nothing to resolve here
				if weapon.template == null:
					problems.append("%s: inventory[%d] template did not resolve" % [_entry_label(path, i, entry), j])
				elif weapon.template.main_attack == null:
					problems.append("%s: template '%s' has no main_attack" % [_entry_label(path, i, entry), weapon.template.item_name])
	assert_array(problems).is_empty()


func test_inventory_weapon_families_are_mapped() -> void:
	# #82: an unmapped weapon_type makes WeaponInstance.make() push_error and return null —
	# a scenario holding one would break at copy_equippable time on load.
	var problems: Array[String] = []
	var scenarios := _loaded_scenarios()
	for path in scenarios:
		var scenario: ScenarioData = scenarios[path]
		for i in scenario.unit_entries.size():
			var entry: ScenarioUnitEntry = scenario.unit_entries[i]
			if entry == null:
				continue
			for j in entry.inventory.size():
				var weapon := entry.inventory[j] as WeaponInstance
				if weapon == null or weapon.template == null:
					continue  # reported by test_inventory_weapons_resolve_main_attack
				if WeaponInstance.make(weapon.template) == null:
					problems.append("%s: weapon_type unmapped for template '%s'" % [_entry_label(path, i, entry), weapon.template.item_name])
	assert_array(problems).is_empty()


func test_saved_indices_are_in_bounds() -> void:
	# #83: equipped_index and every limb_prosthetic_items value index into the saved
	# inventory — a hand-edited or truncated save must fail here, not as a load-time miss.
	var problems: Array[String] = []
	var scenarios := _loaded_scenarios()
	for path in scenarios:
		var scenario: ScenarioData = scenarios[path]
		for i in scenario.unit_entries.size():
			var entry: ScenarioUnitEntry = scenario.unit_entries[i]
			if entry == null:
				continue
			if entry.equipped_index < -1 or entry.equipped_index >= entry.inventory.size():
				problems.append("%s: equipped_index %d out of bounds (%d items)" % [_entry_label(path, i, entry), entry.equipped_index, entry.inventory.size()])
			for slot in entry.limb_prosthetic_items:
				var idx: int = entry.limb_prosthetic_items[slot]
				if idx < 0 or idx >= entry.inventory.size():
					problems.append("%s: limb_prosthetic_items[%s] = %d out of bounds" % [_entry_label(path, i, entry), slot, idx])
	assert_array(problems).is_empty()


func test_job_ids_resolve() -> void:
	# A job id persists as a bare String on the entry (#58); a renamed/deleted JobData would
	# strand it silently — get_effective_stat just skips ids the catalog can't resolve.
	var known := JobCatalog.get_jobs()
	var problems: Array[String] = []
	var scenarios := _loaded_scenarios()
	for path in scenarios:
		var scenario: ScenarioData = scenarios[path]
		for i in scenario.unit_entries.size():
			var entry: ScenarioUnitEntry = scenario.unit_entries[i]
			if entry == null:
				continue
			for id in entry.jobs:
				if not known.has(id):
					problems.append("%s: unknown job id '%s'" % [_entry_label(path, i, entry), id])
	assert_array(problems).is_empty()
