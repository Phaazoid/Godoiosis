# The player's aim palette (#422): picking one repaints the three channels an aim wears, and the
# DEFAULT palette falls through to the colours the Game tab authors rather than to a copy of them.
#
# Pure static calls -- no board, no nodes -- so this stays orphan-clean; tests/core/test_player_settings
# is the shape.
#
# NO CASE HERE SAYS WHAT A COLOUR IS. Every one is the FORK: that a palette moves a channel, that
# DEFAULT does not, that the heal fork survives inside every palette. The dev tunes all four authored
# colours and must never turn this suite red by doing so.
extends GdUnitTestSuite

const PALETTE := PlayerSettings.Setting.AIM_PALETTE

# The authored statics, captured per case. They are CLASS level and outlive a case, so a suite that
# moved one and walked away would poison every suite after it in the run.
var _authored_attack: Color
var _authored_heal: Color
var _authored_footprint: Color

func before_test() -> void:
	PlayerSettings.reset_for_test()
	_authored_attack = OverlayManager.ATTACK_MODULATE
	_authored_heal = OverlayManager.HEAL_ATTACK_MODULATE
	_authored_footprint = OverlayManager.HOVER_MODULATE

func after_test() -> void:
	OverlayManager.ATTACK_MODULATE = _authored_attack
	OverlayManager.HEAL_ATTACK_MODULATE = _authored_heal
	OverlayManager.HOVER_MODULATE = _authored_footprint
	PlayerSettings.reset_for_test()

# An attack that HEALS, which is the other side of the reach fork.
func _healing_attack() -> AttackData:
	var attack := AttackData.new()
	attack.heals = true
	return attack


func test_default_reads_the_authored_static_rather_than_a_copy() -> void:
	# THE reason AIM_PALETTES holds no DEFAULT row. A copied row would be a second answer to "what
	# colour is an attack reach" and would go stale the instant the Game tab moved a knob -- which is
	# exactly what the dev does to these values, and the drift would only ever show up in play.
	PlayerSettings.set_choice(PALETTE, PlayerSettings.AimPalette.DEFAULT)
	var tuned := Color(0.11, 0.22, 0.33, 0.44)   # stands in for "whatever he just dragged it to"
	OverlayManager.ATTACK_MODULATE = tuned
	assert_that(OverlayManager.attack_reach_color(null)).override_failure_message(
			"the Default palette answered from a copy -- a tuned knob no longer reaches the board"
			).is_equal(tuned)

func test_a_player_who_never_opens_the_menu_gets_the_authored_colours() -> void:
	# #418's rule, applied to a fourth choice row: gaining the setting must not move what anyone
	# already sees.
	assert_int(PlayerSettings.default_value(PALETTE)).is_equal(PlayerSettings.AimPalette.DEFAULT)
	assert_that(OverlayManager.attack_reach_color(null)).is_equal(OverlayManager.ATTACK_MODULATE)
	assert_that(OverlayManager.attack_reach_color(_healing_attack())).is_equal(
			OverlayManager.HEAL_ATTACK_MODULATE)
	assert_that(OverlayManager.aim_fill_color()).is_equal(OverlayManager.HOVER_MODULATE)

func test_a_palette_repaints_every_channel_of_the_aim() -> void:
	# All three, because a palette that moved the reach pair and left the footprint behind would put
	# the player's colours under the authored yellow and lose the contrast an aim reads by.
	PlayerSettings.set_choice(PALETTE, PlayerSettings.AimPalette.COLOUR_BLIND)
	assert_that(OverlayManager.attack_reach_color(null)).override_failure_message(
			"picking a palette left the attack reach on its authored colour").is_not_equal(_authored_attack)
	assert_that(OverlayManager.attack_reach_color(_healing_attack())).override_failure_message(
			"picking a palette left the heal reach on its authored colour").is_not_equal(_authored_heal)
	assert_that(OverlayManager.aim_fill_color()).override_failure_message(
			"picking a palette left the footprint on its authored colour").is_not_equal(_authored_footprint)

func test_every_palette_covers_every_channel() -> void:
	# A table that has fallen behind its enum still draws -- through a push_error, in the authored
	# colours -- so nothing on screen says the player's pick was dropped. DEFAULT's ABSENCE is
	# asserted in the same breath, since that is the rule the first case depends on.
	for palette: int in PlayerSettings.AimPalette.values():
		var palette_name: String = PlayerSettings.AimPalette.keys()[palette]
		var has_row: bool = OverlayManager.AIM_PALETTES.has(palette)
		if palette == PlayerSettings.AimPalette.DEFAULT:
			assert_bool(has_row).override_failure_message(
					"DEFAULT has a table row -- it must fall through to the authored statics").is_false()
			continue
		assert_bool(has_row).override_failure_message(
				"%s is a palette with no colours" % palette_name).is_true()
		if not has_row:
			continue
		var row: Dictionary = OverlayManager.AIM_PALETTES[palette]
		for channel: int in OverlayManager.AimChannel.values():
			var channel_name: String = OverlayManager.AimChannel.keys()[channel]
			assert_bool(row.has(channel)).override_failure_message(
					"the %s palette has no %s colour" % [palette_name, channel_name]).is_true()

func test_the_heal_fork_survives_every_palette() -> void:
	# A palette is three colours and not one: flattening the reach pair together would cost the one
	# thing that fill exists to say, and only for the players who picked the palette.
	for palette: int in PlayerSettings.AimPalette.values():
		PlayerSettings.set_choice(PALETTE, palette)
		var palette_name: String = PlayerSettings.AimPalette.keys()[palette]
		assert_that(OverlayManager.attack_reach_color(null)).override_failure_message(
				"the %s palette paints a hit and a heal the same colour" % palette_name
				).is_not_equal(OverlayManager.attack_reach_color(_healing_attack()))

func test_a_watch_aim_is_untouched_by_the_palette() -> void:
	# SCOPE, pinned so a half-widening is loud rather than a surprise in play: #422 moved the reach
	# pair and the footprint, and the dev scoped the watch pair OUT. If the watch ever joins them,
	# this is the case to delete on purpose (#675) -- see AIM_PALETTES for why it is worth a look
	# in play first: the watch's red-orange and the colour-blind palette's vermillion are neighbours.
	for palette: int in PlayerSettings.AimPalette.values():
		PlayerSettings.set_choice(PALETTE, palette)
		var palette_name: String = PlayerSettings.AimPalette.keys()[palette]
		assert_that(OverlayManager.attack_reach_color(null, true)).override_failure_message(
				"the %s palette repainted a WATCH reach, which is outside #422's scope" % palette_name
				).is_equal(OverlayManager.WATCH_REACH_MODULATE)
		assert_that(OverlayManager.aim_fill_color(true)).override_failure_message(
				"the %s palette repainted a WATCH footprint, which is outside #422's scope" % palette_name
				).is_equal(OverlayManager.WATCH_HOVER_MODULATE)

func test_the_pulse_follows_the_palettes_footprint() -> void:
	# DERIVED, not authored: the pulse is the fill at the low alpha. A palette that moved the fill and
	# left the pulse on the old hue would breathe between two different colours.
	PlayerSettings.set_choice(PALETTE, PlayerSettings.AimPalette.HIGH_CONTRAST)
	var fill := OverlayManager.aim_fill_color()
	var pulse := OverlayManager.aim_pulse_color()
	assert_float(pulse.r).is_equal_approx(fill.r, 0.001)
	assert_float(pulse.g).is_equal_approx(fill.g, 0.001)
	assert_float(pulse.b).is_equal_approx(fill.b, 0.001)
	assert_float(pulse.a).override_failure_message(
			"the pulse stopped using the authored low alpha").is_equal_approx(
			OverlayManager.HOVER_PULSE_MODULATE.a, 0.001)
