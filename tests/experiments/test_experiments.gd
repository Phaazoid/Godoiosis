# Guards for the experiment / feature-flag harness (Classes/Definitions/Experiments.gd).
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
