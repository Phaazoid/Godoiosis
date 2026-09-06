# The inspect panel's tooltip text builders (#68) -- the pure statics on info_panel.gd.
#
# These are called off the script directly rather than through a panel instance, because they ARE
# pure statics and a scene fixture would buy nothing here. That is a cost decision, NOT the old
# one: this file used to justify itself with "instantiating the full UnitInfoPanel scene segfaults
# headless", which is false -- tests/ui/test_game_scene_smoke.gd measured the game scene running
# fine under the runner on 2026-07-29 (#114). The panel IS instantiated, populated and read at
# runtime by tests/ui/test_tooltip_rendering.gd, which covers the half these statics structurally
# cannot: whether the panel ever calls them with the right unit's numbers.
#
# POLICY (2026-08-01, suite audit): assert what a line MEANS, not how it is worded. Seven cases here
# used to pin exact strings (`is_equal("Base 4 +1 DEX band")`), so rewording a tooltip failed a test
# with nothing wrong. Copy is not a contract; the facts a readout must state are.
extends GdUnitTestSuite

const InfoPanel := preload("res://Classes/ui/panels/info_panel.gd")

# --- MOV ---

func test_mov_tooltip_states_the_base_and_the_band() -> void:
	var tip: String = InfoPanel.mov_tooltip(4, 1, 0)
	assert_str(tip).contains("4")     # the base it started from
	assert_str(tip).contains("+1")    # the band's signed contribution
	assert_str(tip).contains("DEX")   # ...and which stat bought it


func test_mov_tooltip_shows_a_negative_band_as_negative() -> void:
	# A penalty must not render as a bonus; the sign is the whole point of a band readout.
	assert_str(InfoPanel.mov_tooltip(4, -1, 0)).contains("-1")


func test_mov_tooltip_never_mentions_weight() -> void:
	# Weight is tracked but wired to nothing (2026-07-27): MOV's readout must not imply
	# an encumbrance rule that no longer exists.
	assert_str(InfoPanel.mov_tooltip(4, 0, 0)).not_contains("heavy load")
	assert_str(InfoPanel.mov_tooltip(4, 0, 0)).not_contains("WT")


func test_mov_tooltip_leg_throttle() -> void:
	assert_str(InfoPanel.mov_tooltip(4, 0, 1)).contains("Halved")
	assert_str(InfoPanel.mov_tooltip(4, 0, 2)).contains("Pinned to 1")


func test_mov_tooltip_says_nothing_about_legs_when_both_are_intact() -> void:
	var tip: String = InfoPanel.mov_tooltip(4, 0, 0)
	assert_str(tip).not_contains("Halved")
	assert_str(tip).not_contains("Pinned")


# --- Weight ---

func test_weight_tooltip_reports_carried_only() -> void:
	# No CON body term (doctrine corrected 2026-07-27) -- weight is gear, full stop.
	var tip: String = InfoPanel.weight_tooltip(5)
	assert_str(tip).contains("Carried gear 5")
	assert_str(tip).not_contains("CON")


# --- stat_tooltip: provenance (#112) ---

func test_stat_tooltip_is_empty_when_nothing_modifies_the_stat() -> void:
	# No tooltip at all rather than a "Base 5 -> 5" that says nothing. Empty is the semantic
	# value here, not a wording choice, so exact equality is the right assertion.
	var empty: Array[String] = []
	assert_str(InfoPanel.stat_tooltip(5, 5, empty)).is_equal("")


func test_stat_tooltip_itemizes_every_source() -> void:
	# The point of the seam's source_name: a bag of ints can't say WHY CON is +5.
	var sources: Array[String] = ["Jobs +2", "Steady Tonic +3 (2 turns)", "Bulwark Plate +1"]
	var tip: String = InfoPanel.stat_tooltip(5, 11, sources)
	assert_str(tip).contains("5")     # where it started
	assert_str(tip).contains("11")    # where it ended up
	for source in sources:
		assert_str(tip).contains(source)


func test_stat_tooltip_shows_sources_even_when_they_cancel_out() -> void:
	# A +2 tonic against a -2 armour tax nets zero, but the player still needs to see both -- losing
	# the tonic is about to cost them 2, and a silent tooltip would make that look like a bug.
	var sources: Array[String] = ["Tonic +2", "Riveted Mail -2"]
	var tip: String = InfoPanel.stat_tooltip(5, 5, sources)
	assert_str(tip).contains("Tonic +2")
	assert_str(tip).contains("Riveted Mail -2")


# --- effect_source_text: provenance + the clock ---

func test_effect_source_text_names_the_source_and_its_delta() -> void:
	var text: String = InfoPanel.effect_source_text("Crisis", 5, 3)
	assert_str(text).contains("Crisis")
	assert_str(text).contains("+5")   # signed: a buff must not read like a debuff
	assert_str(text).contains("3")    # turns left


func test_effect_source_text_keeps_a_negative_delta_negative() -> void:
	assert_str(InfoPanel.effect_source_text("Oath", -2, 3)).contains("-2")


func test_effect_source_text_pluralizes_its_clock() -> void:
	# One turn left is the tensest readout in the game; "1 turns" is the kind of thing that gets
	# noticed and mistrusted.
	assert_str(InfoPanel.effect_source_text("Crisis", 5, 1)).contains("1 turn")
	assert_str(InfoPanel.effect_source_text("Crisis", 5, 1)).not_contains("turns")
	assert_str(InfoPanel.effect_source_text("Crisis", 5, 3)).contains("3 turns")


func test_a_permanent_effect_shows_no_clock() -> void:
	var text: String = InfoPanel.effect_source_text("Oath", -2, StatEffect.PERMANENT)
	assert_str(text).contains("Oath")
	assert_str(text).contains("-2")
	assert_str(text).not_contains("turn")   # nothing is counting down


# --- def_tooltip (#44 / #84) ---

func test_def_tooltip_no_armor() -> void:
	var tip: String = InfoPanel.def_tooltip("", 0, 5, 0, 0, 0)
	assert_str(tip).contains("No armor worn")
	assert_str(tip).contains("0")        # the total, stated rather than left implied
	assert_str(tip).not_contains("x CON")   # no arithmetic line for armor that isn't there


func test_def_tooltip_with_armor() -> void:
	var tip: String = InfoPanel.def_tooltip("Scrap Plate", 10, 5, 10, 0, 10)
	assert_str(tip).contains("Scrap Plate")
	assert_str(tip).contains("10 armor x CON 5 = 10")
	assert_str(tip).not_contains("Cover")     # bare ground contributes no line at all
	assert_str(tip).contains("Total: 10")


func test_def_tooltip_itemizes_terrain_cover() -> void:
	# Standing in a Burrow-dug entrenchment (#84): the terrain term is broken out, not folded
	# silently into the armor figure, so the player can see WHY the number is up.
	var tip: String = InfoPanel.def_tooltip("Scrap Plate", 10, 5, 10, 2, 12)
	assert_str(tip).contains("10 armor x CON 5 = 10")
	assert_str(tip).contains("Cover (terrain): +2")
	assert_str(tip).contains("Total: 12")


func test_def_tooltip_cover_without_armor() -> void:
	var tip: String = InfoPanel.def_tooltip("", 0, 5, 0, 2, 2)
	assert_str(tip).contains("No armor worn")
	assert_str(tip).contains("Cover (terrain): +2")
	assert_str(tip).contains("Total: 2")


func test_def_tooltip_reports_the_total_it_was_handed() -> void:
	# The total is PASSED, never re-added here (RulesService.def_breakdown already composed it) --
	# a second addition would be a seam waiting to diverge from the number the resolver subtracts.
	# Handing it a total that does not match its parts must print the total it was given.
	assert_str(InfoPanel.def_tooltip("Scrap Plate", 10, 5, 10, 2, 99)).contains("Total: 99")


# --- ability_tooltip ---

func test_ability_tooltip_names_the_ability_and_its_kind() -> void:
	var tip: String = InfoPanel.ability_tooltip("Iron Will", "Passive", "Caps damage taken.")
	assert_str(tip).contains("Iron Will")
	assert_str(tip).contains("Passive")
	assert_str(tip).contains("Caps damage taken.")
	# Name and kind on one line, description on its own -- the structure the wrapper preserves.
	assert_int(tip.split("\n").size()).is_equal(2)


func test_ability_tooltip_without_description_is_a_single_line() -> void:
	var tip: String = InfoPanel.ability_tooltip("Taunt", "Reaction", "")
	assert_str(tip).contains("Taunt")
	assert_str(tip).contains("Reaction")
	assert_int(tip.split("\n").size()).is_equal(1)   # no dangling blank line


# --- def_tooltip: armour coverage (#424) ---

func test_def_tooltip_lists_the_kinds_the_piece_covers() -> void:
	var tip: String = InfoPanel.def_tooltip("Scrap Plate", 10, 5, 10, 0, 10, "vs blunt, slash, pierce")
	assert_str(tip).contains("Covers: blunt, slash, pierce")


func test_def_tooltip_says_nothing_about_coverage_for_a_piece_that_covers_all() -> void:
	# "" is what every piece authored before kinds existed answers; the row stays as it was.
	var tip: String = InfoPanel.def_tooltip("Scrap Plate", 10, 5, 10, 0, 10)
	assert_str(tip).not_contains("Covers")
