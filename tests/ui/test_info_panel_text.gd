# Headless coverage for the inspect panel's tooltip text builders (#68). Tests the statics
# directly off the script — instantiating the full UnitInfoPanel scene segfaults headless
# (see tests/README), so all composable text lives in pure static funcs on info_panel.gd.
extends GdUnitTestSuite

const InfoPanel := preload("res://Classes/ui/panels/info_panel.gd")

func test_mov_tooltip_unencumbered() -> void:
	assert_str(InfoPanel.mov_tooltip(4, 1, 5, 8, 1, 0)).is_equal("Base 4 +1 DEX band")

func test_mov_tooltip_heavy_load() -> void:
	assert_str(InfoPanel.mov_tooltip(4, 0, 9, 8, 1, 0)).contains("-1 heavy load (WT 9 >= 8)")

func test_mov_tooltip_below_threshold_has_no_penalty_line() -> void:
	assert_str(InfoPanel.mov_tooltip(4, 0, 7, 8, 1, 0)).not_contains("heavy load")

func test_mov_tooltip_leg_throttle() -> void:
	assert_str(InfoPanel.mov_tooltip(4, 0, 5, 8, 1, 1)).contains("Halved")
	assert_str(InfoPanel.mov_tooltip(4, 0, 5, 8, 1, 2)).contains("Pinned to 1")

func test_weight_tooltip_breakdown() -> void:
	var tip: String = InfoPanel.weight_tooltip(4, 5, 8, 1)
	assert_str(tip).contains("Body (CON) 4 + gear 5")
	assert_str(tip).contains("At 8+ MOV takes -1")

func test_def_tooltip_no_armor() -> void:
	assert_str(InfoPanel.def_tooltip("", 0, 5, 0, 0)).is_equal("No armor worn\nTotal: 0")

func test_def_tooltip_with_armor() -> void:
	var tip: String = InfoPanel.def_tooltip("Scrap Plate", 10, 5, 10, 0)
	assert_str(tip).contains("Scrap Plate")
	assert_str(tip).contains("10 armor x CON 5 = 10")
	assert_str(tip).not_contains("Cover")     # bare ground contributes no line at all
	assert_str(tip).contains("Total: 10")

func test_def_tooltip_itemizes_terrain_cover() -> void:
	# Standing in a Burrow-dug entrenchment (#84): the terrain term is broken out, not folded
	# silently into the armor figure, so the player can see WHY the number is up.
	var tip: String = InfoPanel.def_tooltip("Scrap Plate", 10, 5, 10, 2)
	assert_str(tip).contains("10 armor x CON 5 = 10")
	assert_str(tip).contains("Cover (terrain): +2")
	assert_str(tip).contains("Total: 12")

func test_def_tooltip_cover_without_armor() -> void:
	var tip: String = InfoPanel.def_tooltip("", 0, 5, 0, 2)
	assert_str(tip).contains("No armor worn")
	assert_str(tip).contains("Cover (terrain): +2")
	assert_str(tip).contains("Total: 2")

func test_ability_tooltip_with_description() -> void:
	assert_str(InfoPanel.ability_tooltip("Iron Will", "Passive", "Caps damage taken.")) \
		.is_equal("Iron Will (Passive)\nCaps damage taken.")

func test_ability_tooltip_without_description() -> void:
	assert_str(InfoPanel.ability_tooltip("Taunt", "Reaction", "")).is_equal("Taunt (Reaction)")
