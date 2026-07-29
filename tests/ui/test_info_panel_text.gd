# Headless coverage for the inspect panel's tooltip text builders (#68). Tests the statics
# directly off the script — instantiating the full UnitInfoPanel scene segfaults headless
# (see tests/README), so all composable text lives in pure static funcs on info_panel.gd.
extends GdUnitTestSuite

const InfoPanel := preload("res://Classes/ui/panels/info_panel.gd")

func test_mov_tooltip_unencumbered() -> void:
	assert_str(InfoPanel.mov_tooltip(4, 1, 0)).is_equal("Base 4 +1 DEX band")

func test_mov_tooltip_never_mentions_weight() -> void:
	# Weight is tracked but wired to nothing (2026-07-27): MOV's readout must not imply
	# an encumbrance rule that no longer exists.
	assert_str(InfoPanel.mov_tooltip(4, 0, 0)).not_contains("heavy load")
	assert_str(InfoPanel.mov_tooltip(4, 0, 0)).not_contains("WT")

func test_mov_tooltip_leg_throttle() -> void:
	assert_str(InfoPanel.mov_tooltip(4, 0, 1)).contains("Halved")
	assert_str(InfoPanel.mov_tooltip(4, 0, 2)).contains("Pinned to 1")

func test_weight_tooltip_reports_carried_only() -> void:
	# No CON body term (doctrine corrected 2026-07-27) — weight is gear, full stop.
	var tip: String = InfoPanel.weight_tooltip(5)
	assert_str(tip).contains("Carried gear 5")
	assert_str(tip).not_contains("CON")

# --- stat_tooltip: provenance (#112) ---

func test_stat_tooltip_is_empty_when_nothing_modifies_the_stat() -> void:
	# No tooltip at all rather than a "Base 5 → 5" that says nothing.
	var empty: Array[String] = []
	assert_str(InfoPanel.stat_tooltip(5, 5, empty)).is_equal("")

func test_stat_tooltip_itemizes_every_source() -> void:
	# The point of the seam's source_name: a bag of ints can't say WHY CON is +5.
	var sources: Array[String] = ["Jobs +2", "Steady Tonic +3 (2 turns)", "Bulwark Plate +1"]
	var tip: String = InfoPanel.stat_tooltip(5, 11, sources)
	assert_str(tip).contains("Base 5")
	assert_str(tip).contains("11")
	assert_str(tip).contains("Steady Tonic +3 (2 turns)")
	assert_str(tip).contains("Bulwark Plate +1")

func test_stat_tooltip_shows_sources_even_when_they_cancel_out() -> void:
	# A +2 tonic against a -2 armour tax nets zero, but the player still needs to see both — losing
	# the tonic is about to cost them 2, and a silent tooltip would make that look like a bug.
	var sources: Array[String] = ["Tonic +2", "Riveted Mail -2"]
	var tip: String = InfoPanel.stat_tooltip(5, 5, sources)
	assert_str(tip).contains("Tonic +2")
	assert_str(tip).contains("Riveted Mail -2")

func test_effect_source_text_names_the_source_and_its_clock() -> void:
	assert_str(InfoPanel.effect_source_text("Crisis", 5, 3)).is_equal("Crisis +5 (3 turns)")
	assert_str(InfoPanel.effect_source_text("Crisis", 5, 1)).is_equal("Crisis +5 (1 turn)")
	assert_str(InfoPanel.effect_source_text("Oath", -2, StatEffect.PERMANENT)).is_equal("Oath -2")

func test_def_tooltip_no_armor() -> void:
	assert_str(InfoPanel.def_tooltip("", 0, 5, 0, 0, 0)).is_equal("No armor worn\nTotal: 0")

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

func test_ability_tooltip_with_description() -> void:
	assert_str(InfoPanel.ability_tooltip("Iron Will", "Passive", "Caps damage taken.")) \
		.is_equal("Iron Will (Passive)\nCaps damage taken.")

func test_ability_tooltip_without_description() -> void:
	assert_str(InfoPanel.ability_tooltip("Taunt", "Reaction", "")).is_equal("Taunt (Reaction)")
