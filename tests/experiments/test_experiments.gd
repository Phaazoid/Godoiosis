# Guards for the experiment / feature-flag harness (Classes/dev/Experiments.gd).
# Pure static calls — no nodes built — so this stays orphan-clean.
#
# before_test() calls Experiments.reset_for_test() so every case starts hermetic
# (in-memory, defaults only, no disk I/O). The persistence round-trip test opts back into
# real disk I/O against a temp cfg and cleans up after itself.
extends GdUnitTestSuite

func before_test() -> void:
	Experiments.reset_for_test()

func test_every_enum_flag_has_metadata() -> void:
	# Catches "added a Flag value but forgot its DEFS entry" (or a typo'd metadata key).
	for flag in Experiments.Flag.values():
		assert_bool(Experiments.DEFS.has(flag)).is_true()
		assert_str(Experiments.title_of(flag)).is_not_empty()
		assert_str(Experiments.desc_of(flag)).is_not_empty()

func test_default_honored_when_unset() -> void:
	var flag := Experiments.Flag.EXAMPLE_FLAG
	assert_bool(Experiments.is_on(flag)).is_equal(Experiments.default_of(flag))

func test_set_on_overrides_default() -> void:
	var flag := Experiments.Flag.EXAMPLE_FLAG
	Experiments.set_on(flag, not Experiments.default_of(flag))
	assert_bool(Experiments.is_on(flag)).is_equal(not Experiments.default_of(flag))

func test_toggle_flips_and_returns_new_value() -> void:
	var flag := Experiments.Flag.EXAMPLE_FLAG
	var before := Experiments.is_on(flag)
	var returned := Experiments.toggle(flag)
	assert_bool(returned).is_equal(not before)
	assert_bool(Experiments.is_on(flag)).is_equal(not before)

func test_reset_all_restores_defaults() -> void:
	var flag := Experiments.Flag.EXAMPLE_FLAG
	Experiments.set_on(flag, not Experiments.default_of(flag))
	Experiments.reset_all()
	assert_bool(Experiments.is_on(flag)).is_equal(Experiments.default_of(flag))

func test_persistence_roundtrip_keyed_by_name() -> void:
	# Exercise the real disk path against a temp cfg, then clean up.
	var flag := Experiments.Flag.EXAMPLE_FLAG
	Experiments._state.clear()
	Experiments._loaded = true
	Experiments.persistence_enabled = true
	Experiments.config_path = "user://experiments_roundtrip_test.cfg"
	if FileAccess.file_exists(Experiments.config_path):
		DirAccess.remove_absolute(Experiments.config_path)

	Experiments.set_on(flag, true)  # writes the cfg

	# Wipe memory and force a reload from disk.
	Experiments._state.clear()
	Experiments._loaded = false
	assert_bool(Experiments.is_on(flag)).is_true()

	# The cfg must be keyed by the flag NAME, not its int.
	var cfg := ConfigFile.new()
	assert_int(cfg.load(Experiments.config_path)).is_equal(OK)
	assert_bool(cfg.has_section_key(Experiments.CONFIG_SECTION, "EXAMPLE_FLAG")).is_true()

	# Clean up the temp file and restore the hermetic seam for any later suite.
	DirAccess.remove_absolute(Experiments.config_path)
	Experiments.reset_for_test()

# --- choice rows (#508) ---

func _a_choice() -> Experiments.Flag:
	for flag: Experiments.Flag in Experiments.all_flags():
		if Experiments.is_choice(flag):
			return flag
	return Experiments.Flag.EXAMPLE_FLAG

func test_every_choice_declares_options_and_a_default_inside_them() -> void:
	for flag: Experiments.Flag in Experiments.all_flags():
		if not Experiments.is_choice(flag):
			continue
		var options := Experiments.options_of(flag)
		assert_int(options.size()).override_failure_message(
			"%s offers fewer than two treatments -- that is a toggle" % Experiments.Flag.keys()[flag]).is_greater_equal(2)
		assert_int(int(Experiments.default_value(flag))).is_between(0, options.size() - 1)

func test_a_choice_reads_its_default_index_when_unset() -> void:
	var flag := _a_choice()
	assert_bool(Experiments.is_choice(flag)).override_failure_message("no choice flag is declared").is_true()
	assert_int(Experiments.choice_of(flag)).is_equal(int(Experiments.default_value(flag)))

func test_set_choice_clamps_into_the_options() -> void:
	var flag := _a_choice()
	Experiments.set_choice(flag, 999)
	assert_int(Experiments.choice_of(flag)).is_equal(Experiments.options_of(flag).size() - 1)

func test_the_toggle_writer_refuses_a_choice_row() -> void:
	# set_on would store a BOOL that choice_of then reads back as 1 -- #647's trap, refused outright.
	var flag := _a_choice()
	var before := Experiments.choice_of(flag)
	Experiments.set_on(flag, true)
	assert_int(Experiments.choice_of(flag)).is_equal(before)

func test_a_choice_survives_a_relaunch_as_an_INDEX() -> void:
	# The load must answer a choice BEFORE the toggle's bool(): bool(2) is true, which would read
	# every saved option back as 1 on every launch.
	var flag := _a_choice()
	var last := Experiments.options_of(flag).size() - 1
	Experiments._state.clear()
	Experiments._loaded = true
	Experiments.persistence_enabled = true
	Experiments.config_path = "user://experiments_choice_test.cfg"
	if FileAccess.file_exists(Experiments.config_path):
		DirAccess.remove_absolute(Experiments.config_path)
	Experiments.set_choice(flag, last)
	Experiments._state.clear()
	Experiments._loaded = false
	var read_back := Experiments.choice_of(flag)
	DirAccess.remove_absolute(Experiments.config_path)
	Experiments.reset_for_test()
	assert_int(read_back).is_equal(last)

func test_an_out_of_range_saved_choice_falls_back_to_the_default() -> void:
	var flag := _a_choice()
	Experiments._state.clear()
	Experiments.persistence_enabled = true
	Experiments.config_path = "user://experiments_choice_range_test.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value(Experiments.CONFIG_SECTION, Experiments.Flag.keys()[flag], 99)
	cfg.save(Experiments.config_path)
	Experiments._loaded = false
	var read_back := Experiments.choice_of(flag)
	DirAccess.remove_absolute(Experiments.config_path)
	Experiments.reset_for_test()
	assert_int(read_back).is_equal(int(Experiments.default_value(flag)))
