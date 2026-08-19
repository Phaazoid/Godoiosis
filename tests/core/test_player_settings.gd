# Guards for the player-preferences store (Classes/core/PlayerSettings.gd, #350).
# Pure static calls — no nodes built — so this stays orphan-clean. tests/experiments's shape.
#
# before_test() calls PlayerSettings.reset_for_test() so every case starts hermetic (in-memory,
# defaults only, no disk I/O). The round-trip case opts back into real disk against a temp cfg and
# cleans up after itself.
extends GdUnitTestSuite

func before_test() -> void:
	PlayerSettings.reset_for_test()

func test_every_setting_has_metadata() -> void:
	# Catches "added a Setting but forgot its DEFS entry" — the failure mode that would ship a
	# blank, unlabelled checkbox, since SettingsScreen builds its rows straight off this table.
	for setting in PlayerSettings.Setting.values():
		assert_bool(PlayerSettings.DEFS.has(setting)).is_true()
		assert_str(PlayerSettings.title_of(setting)).is_not_empty()
		assert_str(PlayerSettings.desc_of(setting)).is_not_empty()

func test_health_bars_are_hover_only_until_asked_otherwise() -> void:
	# The ticket's own default: #229's hover-only behavior is what a player who has never opened
	# the menu still gets.
	assert_bool(PlayerSettings.default_of(PlayerSettings.Setting.ALWAYS_SHOW_HEALTH)).is_false()
	assert_bool(PlayerSettings.is_on(PlayerSettings.Setting.ALWAYS_SHOW_HEALTH)).is_false()

func test_set_on_overrides_default() -> void:
	var setting := PlayerSettings.Setting.ALWAYS_SHOW_HEALTH
	PlayerSettings.set_on(setting, not PlayerSettings.default_of(setting))
	assert_bool(PlayerSettings.is_on(setting)).is_equal(not PlayerSettings.default_of(setting))

func test_persistence_roundtrip_keyed_by_name() -> void:
	# A preference the player set must survive quitting the game — the dev call for this ticket.
	# Exercises the real disk path against a temp cfg, then cleans up.
	var setting := PlayerSettings.Setting.ALWAYS_SHOW_HEALTH
	PlayerSettings._state.clear()
	PlayerSettings._loaded = true
	PlayerSettings.persistence_enabled = true
	PlayerSettings.config_path = "user://settings_roundtrip_test.cfg"
	if FileAccess.file_exists(PlayerSettings.config_path):
		DirAccess.remove_absolute(PlayerSettings.config_path)

	PlayerSettings.set_on(setting, true)  # writes the cfg

	# Wipe memory and force a reload from disk — the relaunch, as far as this store can see one.
	PlayerSettings._state.clear()
	PlayerSettings._loaded = false
	assert_bool(PlayerSettings.is_on(setting)).is_true()

	# Keyed by the enum NAME, not its int: reordering Setting must not repoint a saved preference.
	var cfg := ConfigFile.new()
	assert_int(cfg.load(PlayerSettings.config_path)).is_equal(OK)
	assert_bool(cfg.has_section_key(PlayerSettings.CONFIG_SECTION, "ALWAYS_SHOW_HEALTH")).is_true()

	DirAccess.remove_absolute(PlayerSettings.config_path)
	PlayerSettings.reset_for_test()
