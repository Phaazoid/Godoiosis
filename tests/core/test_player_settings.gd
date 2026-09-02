# Guards for the player-preferences store (Classes/core/PlayerSettings.gd, #350; two row KINDS
# since #418). Pure static calls — no nodes built — so this stays orphan-clean. tests/experiments's
# shape.
#
# before_test() calls PlayerSettings.reset_for_test() so every case starts hermetic (in-memory,
# defaults only, no disk I/O). The cases that need real disk opt back in against a temp cfg and
# clean up after themselves.
#
# The BOOL cases deliberately drive ALWAYS_SHOW_SQUAD_RINGS rather than the health setting: the
# health row is the choice kind now, and a bool case pointed at it would be asserting through a
# façade instead of at the toggle path it is about.
extends GdUnitTestSuite

const BOOL_SETTING := PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS
const CHOICE_SETTING := PlayerSettings.Setting.HEALTH_BARS
const ZOOM_SETTING := PlayerSettings.Setting.BATTLE_ZOOM_MODE

func before_test() -> void:
	PlayerSettings.reset_for_test()

# Every choice row's own enum size, by setting. A DECLARED list, and the law below refuses a choice
# row that is missing from it -- so the NEXT tenant cannot ship without its pin either. A function
# rather than a const because an enum's .size() is a call, not a constant expression.
func _choice_enum_sizes() -> Dictionary:
	return {
		PlayerSettings.Setting.HEALTH_BARS: PlayerSettings.HealthBars.size(),
		PlayerSettings.Setting.BATTLE_ZOOM_MODE: PlayerSettings.BattleZoom.size(),
		PlayerSettings.Setting.AIM_PALETTE: PlayerSettings.AimPalette.size(),
		# Three rows over ONE enum (#394) -- they are three preferences sharing a three-step
		# vocabulary, so the pin is the same size three times rather than three enums.
		PlayerSettings.Setting.CAMERA_PAN_SPEED: PlayerSettings.Scale.size(),
		PlayerSettings.Setting.MOUSE_SENSITIVITY: PlayerSettings.Scale.size(),
		PlayerSettings.Setting.CAMERA_SMOOTHING: PlayerSettings.Scale.size(),
	}

func test_every_setting_has_metadata() -> void:
	# Catches "added a Setting but forgot its DEFS entry" — the failure mode that would ship a
	# blank, unlabelled row, since SettingsScreen builds its rows straight off this table.
	for setting in PlayerSettings.Setting.values():
		assert_bool(PlayerSettings.DEFS.has(setting)).is_true()
		assert_str(PlayerSettings.title_of(setting)).is_not_empty()
		assert_str(PlayerSettings.desc_of(setting)).is_not_empty()

func test_every_choice_row_can_actually_be_rendered() -> void:
	# The kind is derived from `options` being present, so a choice row that declares an empty list
	# or a default outside it draws a strip with nothing pressed — and is unreachable thereafter.
	for setting: PlayerSettings.Setting in PlayerSettings.Setting.values():
		if not PlayerSettings.is_choice(setting):
			continue
		var labels: Array = PlayerSettings.options_of(setting)
		var name: String = PlayerSettings.Setting.keys()[setting]
		assert_int(labels.size()).override_failure_message(
				"%s is a choice row with no options" % name).is_greater(1)
		var fallback: int = PlayerSettings.default_value(setting)
		assert_int(fallback).override_failure_message(
				"%s defaults outside its own options list" % name).is_between(0, labels.size() - 1)

func test_every_choice_rows_options_and_enum_stay_in_step() -> void:
	# A DECLARED duplicate (Law #4): a row's enum values ARE the indices into its options list, and
	# the enum is authoritative. Nothing else can notice them drifting — a list one label short
	# leaves the last mode unreachable, silently, with the strip looking right.
	#
	# GENERALIZED from the health row alone by #647's second tenant: the case used to name one
	# setting, so a new choice row inherited none of this guard.
	var pinned := _choice_enum_sizes()
	for setting: PlayerSettings.Setting in PlayerSettings.Setting.values():
		if not PlayerSettings.is_choice(setting):
			continue
		var name: String = PlayerSettings.Setting.keys()[setting]
		assert_bool(pinned.has(setting)).override_failure_message(
				"%s is a choice row with no enum pinned here — add it to _choice_enum_sizes" % name).is_true()
		if not pinned.has(setting):
			continue
		assert_int(PlayerSettings.options_of(setting).size()).override_failure_message(
				"%s's labels no longer cover its own enum" % name).is_equal(pinned[setting])


# --- the façades refuse the other kind's row (#647) ---------------------------------------------
#
# The WRITERS are the half worth pinning: a bad read is one wrong frame, a bad write is a cfg the
# player carries between sessions. Each case asserts the store is UNMOVED, which is the observable
# consequence — the push_error beside it is for whoever is reading the log.

func test_writing_a_choice_row_through_the_toggle_facade_is_refused() -> void:
	# Unguarded, set_on writes a BOOL into a choice row; choice_of then reads it back as int(true) = 1
	# and load_state re-reads it the same way, so the wrong mode survives a relaunch consistently
	# wrong. That is the exact shape a caller left behind by a boolean-to-choice conversion has.
	PlayerSettings.set_choice(CHOICE_SETTING, PlayerSettings.HealthBars.EVERY)
	PlayerSettings.set_on(CHOICE_SETTING, true)
	assert_int(PlayerSettings.choice_of(CHOICE_SETTING)).override_failure_message(
			"set_on wrote a bool into a choice row — the mode is now whatever int(true) happens to mean") \
		.is_equal(PlayerSettings.HealthBars.EVERY)


func test_writing_a_toggle_row_through_the_choice_facade_is_refused() -> void:
	PlayerSettings.set_on(BOOL_SETTING, true)
	PlayerSettings.set_choice(BOOL_SETTING, 0)
	assert_bool(PlayerSettings.is_on(BOOL_SETTING)).override_failure_message(
			"set_choice wrote an index into a toggle row").is_true()


func test_the_battle_zoom_still_ships_on_for_everything() -> void:
	# #418's rule applied again: gaining a third option must not move what a player who never opens
	# the menu sees.
	assert_int(PlayerSettings.default_value(ZOOM_SETTING)) \
		.is_equal(PlayerSettings.BattleZoom.ALWAYS)
	assert_int(PlayerSettings.choice_of(ZOOM_SETTING)) \
		.is_equal(PlayerSettings.BattleZoom.ALWAYS)

func test_health_bars_are_hover_only_until_asked_otherwise() -> void:
	# The ticket's own default, unchanged by #418 adding a third value: #229's hover-only behaviour
	# is what a player who has never opened the menu still gets.
	assert_int(PlayerSettings.default_value(CHOICE_SETTING)) \
		.is_equal(PlayerSettings.HealthBars.HOVERED)
	assert_int(PlayerSettings.choice_of(CHOICE_SETTING)) \
		.is_equal(PlayerSettings.HealthBars.HOVERED)

func test_set_on_overrides_default() -> void:
	var want: bool = not PlayerSettings.default_value(BOOL_SETTING)
	PlayerSettings.set_on(BOOL_SETTING, want)
	assert_bool(PlayerSettings.is_on(BOOL_SETTING)).is_equal(want)

func test_set_choice_overrides_default() -> void:
	PlayerSettings.set_choice(CHOICE_SETTING, PlayerSettings.HealthBars.DAMAGED)
	assert_int(PlayerSettings.choice_of(CHOICE_SETTING)) \
		.is_equal(PlayerSettings.HealthBars.DAMAGED)

func test_persistence_roundtrip_keyed_by_name() -> void:
	# A preference the player set must survive quitting the game — the dev call for this ticket.
	# Exercises the real disk path against a temp cfg, then cleans up.
	_open_disk("user://settings_roundtrip_test.cfg")
	PlayerSettings.set_on(BOOL_SETTING, true)  # writes the cfg

	_relaunch()
	assert_bool(PlayerSettings.is_on(BOOL_SETTING)).is_true()

	# Keyed by the enum NAME, not its int: reordering Setting must not repoint a saved preference.
	var cfg := ConfigFile.new()
	assert_int(cfg.load(PlayerSettings.config_path)).is_equal(OK)
	assert_bool(cfg.has_section_key(PlayerSettings.CONFIG_SECTION, "ALWAYS_SHOW_SQUAD_RINGS")).is_true()

	_close_disk()

func test_a_choice_survives_the_relaunch_too() -> void:
	# #418: a choice persists as an INT, a path the bool round trip above cannot exercise at all —
	# load_state types its read by kind, so a choice read as a bool comes back as EVERY or HOVERED
	# depending only on whether the index was zero.
	_open_disk("user://settings_choice_roundtrip_test.cfg")
	PlayerSettings.set_choice(CHOICE_SETTING, PlayerSettings.HealthBars.DAMAGED)

	_relaunch()
	assert_int(PlayerSettings.choice_of(CHOICE_SETTING)).override_failure_message(
			"the chosen health-bar mode did not survive a relaunch"
			).is_equal(PlayerSettings.HealthBars.DAMAGED)

	_close_disk()

func test_a_cfg_pointing_outside_the_options_falls_back_to_the_default() -> void:
	# The cfg is a text file the player can open, so an out-of-range index is reachable INPUT, not
	# a bug. Left untrusted it indexes past the options list the moment the page is drawn.
	var path := "user://settings_out_of_range_test.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value(PlayerSettings.CONFIG_SECTION, "HEALTH_BARS", 99)   # fixture setup, not the claim
	assert_int(cfg.save(path)).is_equal(OK)

	_open_disk(path)
	_relaunch()
	assert_int(PlayerSettings.choice_of(CHOICE_SETTING)).override_failure_message(
			"an out-of-range cfg value reached the options list"
			).is_equal(PlayerSettings.HealthBars.HOVERED)

	_close_disk()

func test_a_headless_run_honours_nobodys_preferences() -> void:
	# #449: the suite must never inherit the machine's own settings.cfg. It did, and the cost was a
	# presentation case that passed or failed depending on what the dev had switched on while
	# playtesting -- taking the nine cases after it out of the run with no sign it had.
	# A cfg holding the OPPOSITE of the default is written, the store is re-booted over it, and the
	# DEFAULT is still what comes back, because nobody is at the keyboard in a headless process.
	var path := "user://settings_headless_test.cfg"
	var want: bool = not PlayerSettings.default_value(BOOL_SETTING)
	var cfg := ConfigFile.new()
	cfg.set_value(PlayerSettings.CONFIG_SECTION, "ALWAYS_SHOW_SQUAD_RINGS", want)
	assert_int(cfg.save(path)).is_equal(OK)   # fixture setup, not the claim

	# The boot the game gets, aimed at a real file on disk: persistence on, then _static_init.
	PlayerSettings.persistence_enabled = true
	PlayerSettings.config_path = path
	PlayerSettings._static_init()
	_relaunch()

	assert_bool(PlayerSettings.is_on(BOOL_SETTING)).override_failure_message(
			"a headless run read a cfg off this machine -- the suite inherits whoever's preferences"
			).is_equal(bool(PlayerSettings.default_value(BOOL_SETTING)))

	DirAccess.remove_absolute(path)
	PlayerSettings.reset_for_test()

# --- helpers -----------------------------------------------------------------------------------

# Opt back into the real disk path, against a temp cfg nobody else owns.
func _open_disk(path: String) -> void:
	PlayerSettings._state.clear()
	PlayerSettings._loaded = true
	PlayerSettings.persistence_enabled = true
	PlayerSettings.config_path = path

# Wipe memory and force a reload from disk — the relaunch, as far as this store can see one.
func _relaunch() -> void:
	PlayerSettings._state.clear()
	PlayerSettings._loaded = false

func _close_disk() -> void:
	DirAccess.remove_absolute(PlayerSettings.config_path)
	PlayerSettings.reset_for_test()
