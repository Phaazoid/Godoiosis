# What the HUD actually RENDERS: every tooltip on screen is display-safe, and the panel feeds its
# text builders the right unit.
#
# Replaces the source-scanning law that used to live at tests/law/test_tooltip_wrapping.gd
# (2026-08-01, suite audit). That test read Classes/ui/*.gd as TEXT and grepped each function for
# `tooltip_text` without `UiText`, on a stated premise that has since been disproven in this very
# tree: "Classes/ui/ has ZERO runtime coverage because the game scene segfaults inside the runner
# (#114)". It does not segfault -- tests/ui/test_game_scene_smoke.gd measured that on 2026-07-29 and
# says so in its own header, so the suite was contradicting itself. Grepping source was a workaround
# for a blocker that was never real.
#
# Asserting the OUTCOME instead is strictly stronger. The source scan could only see whether the
# token `UiText` appeared somewhere in the same function; it could not see a site that wrapped at
# the wrong width, a builder that emitted an unbreakable over-long line, or a tooltip set anywhere
# but a literal `tooltip_text =` assignment. This walks the live Control tree of a populated panel
# and checks the strings themselves.
#
# The assertion is `UiText.wrap(t) == t` rather than a line-length check, because wrap() is
# idempotent: re-wrapping already-wrapped text is a no-op, so equality means exactly "this string is
# already in display-safe form". It also handles the documented trade-off for free -- a single word
# longer than the width is left alone by wrap(), so it does not read as a violation.
#
# Scope is the GAME UI only: the walk starts at `game`, so Classes/dev/'s DevOverlay (a sibling of
# GameContainer under Main, with its own short one-line tooltips in its own OS window) is excluded
# structurally rather than by matching on a node name that could drift.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

# The fixture must reach content long enough that wrapping is load-bearing; see
# test_the_fixture_reaches_content_that_needs_wrapping for why these two floors exist.
const MIN_LONGEST_LINE := UiText.TOOLTIP_WIDTH - 10
const MIN_WRAPPED_LINES := 3

var _main: Node
var game: Node2D


func before_test() -> void:
	# Named + parented exactly as in production so game.gd's absolute /root/Main/DevOverlay lookup
	# resolves; see tests/ui/test_game_scene_smoke.gd, which this fixture is copied from.
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.spawn_sandbox()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


# The worst case the HUD has to render, not the default sandbox unit. This matters more than it
# looks: a bare sandbox unit wears no armor and holds no abilities, so its longest tooltip is about
# twenty characters and EVERY assertion in this file would pass without wrapping existing at all.
# Dressing it in the authored Insulated Weave is what puts the original regression's own content --
# a long granted-ability description -- on screen.
func _inspect_a_dressed_unit() -> Unit:
	var unit: Unit = null
	for candidate: Unit in game._all_units():
		if candidate.get_faction() == Team.Faction.PLAYER:
			unit = candidate
			break
	assert_object(unit).is_not_null()

	var weave: ArmorData = ArmorCatalog.get_editable()["Insulated Weave"]
	unit.add_item(weave)
	unit.wear_armor(unit.inventory.find(weave))
	unit.apply_stat_effect(StatEffect.make("Steady Tonic", {Stats.Stat.CON: 3}, 2))

	# Fixture preconditions, asserted at the source rather than in each case that depends on them.
	# wear_armor enforces the wear gate, so a future gate on the Weave would silently leave the unit
	# undressed and quietly weaken every assertion below -- and the two wiring cases would fail on a
	# null deref rather than saying why.
	assert_object(unit.worn_armor).override_failure_message(
		"The fixture did not dress the unit -- wear_armor was refused, so every case in this file is weaker than it reads."
		).is_not_null()
	assert_int(unit.get_live_abilities().size()).override_failure_message(
		"The dressed unit has no live abilities -- the abilities section will render nothing and the long-description content never reaches the screen."
		).is_greater(0)

	var board: BoardContext = game._board()
	game.unit_info_panel.set_unit(unit, true, board)
	return unit


# Every non-empty tooltip under `game`, as [node path, text].
func _rendered_tooltips() -> Array:
	var found: Array = []
	_collect(game, found)
	return found


func _collect(node: Node, found: Array) -> void:
	var control := node as Control
	if control != null and control.tooltip_text != "":
		found.append([str(node.get_path()), control.tooltip_text])
	for child in node.get_children():
		_collect(child, found)


func _paths_joined(entries: Array) -> String:
	var parts: Array[String] = []
	for entry in entries:
		parts.append(str(entry[0]))
	return "\n  ".join(parts)


# --- the fixture is actually rendering something ---

func test_the_populated_panel_renders_tooltips() -> void:
	# Vacuity guard. Every case below reads _rendered_tooltips(); if inspecting a unit stopped
	# populating the panel, they would all pass while pinning nothing.
	_inspect_a_dressed_unit()
	await await_idle_frame()

	var tooltips := _rendered_tooltips()
	assert_int(tooltips.size()).override_failure_message(
		"Inspecting a unit rendered almost no tooltips -- the panel stopped populating, and every assertion in this file is now vacuous."
		).is_greater(9)

	# ...and from more than one builder, so a single surviving section can't carry the file.
	var sections := {}
	for entry in tooltips:
		for section: String in ["LimbsRow", "StatsGrid", "AbilitiesList", "InventoryPanel"]:
			if str(entry[0]).contains(section):
				sections[section] = true
	assert_int(sections.size()).override_failure_message(
		"Tooltips came from only these panel sections: %s -- expected limbs, stats, abilities and inventory all rendering." % str(sections.keys())
		).is_greater_equal(3)


func test_the_fixture_reaches_content_that_needs_wrapping() -> void:
	# The guard that gives this whole file teeth. Wrapping only matters near the width, so if the
	# authored content the fixture reaches is all short, test_every_rendered_tooltip_is_display_safe
	# passes no matter what wrap() does. This fails LOUDLY when the fixture stops being worst-case
	# -- e.g. an ability description gets re-authored short -- rather than going quietly toothless.
	_inspect_a_dressed_unit()
	await await_idle_frame()

	var longest_line := 0
	var most_lines := 0
	for entry in _rendered_tooltips():
		var lines: PackedStringArray = str(entry[1]).split("\n")
		most_lines = maxi(most_lines, lines.size())
		for line in lines:
			longest_line = maxi(longest_line, line.length())

	assert_int(longest_line).override_failure_message(
		"Longest rendered tooltip line is %d chars, under the %d floor -- nothing on screen is near the %d-char width, so the display-safety law is not being exercised. Give the fixture longer authored content."
		% [longest_line, MIN_LONGEST_LINE, UiText.TOOLTIP_WIDTH]).is_greater_equal(MIN_LONGEST_LINE)
	assert_int(most_lines).override_failure_message(
		"No rendered tooltip reached %d lines -- the fixture is not producing multi-line wrapped text." % MIN_WRAPPED_LINES
		).is_greater_equal(MIN_WRAPPED_LINES)


# --- the law ---

func test_every_rendered_tooltip_is_display_safe() -> void:
	# Godot's built-in tooltip is a Label with autowrap OFF, and autowrap is a property rather than
	# a theme item, so there is no global switch -- the rule can only hold at each site. wrap() is
	# idempotent, so `wrap(t) == t` means "already wrapped", and an unwrapped long line is the
	# failure the player actually sees: text running off the right edge of the screen.
	_inspect_a_dressed_unit()
	await await_idle_frame()

	var offenders: Array = []
	for entry in _rendered_tooltips():
		if UiText.wrap(str(entry[1])) != str(entry[1]):
			offenders.append(entry)

	assert_int(offenders.size()).override_failure_message(
		"These tooltips are not in wrapped form -- Godot will not wrap them, so they run off-screen:\n  %s"
		% _paths_joined(offenders)).is_equal(0)


# --- the wiring: the panel feeds its builders THIS unit ---
#
# The old suite tested info_panel's static builders in isolation with exact expected strings, which
# could not see whether the panel ever called them with the right arguments. These three do.

func test_a_stat_tooltip_names_a_live_effect_source() -> void:
	# #112's whole point: a bag of ints can't say WHY CON is +3. The effect is applied above, so its
	# source name has to survive all the way onto a rendered stat row.
	_inspect_a_dressed_unit()
	await await_idle_frame()

	var found := false
	for entry in _rendered_tooltips():
		if str(entry[1]).contains("Steady Tonic"):
			found = true
	assert_bool(found).override_failure_message(
		"No rendered tooltip names the live StatEffect's source -- the stats row is not reading the unit's effects."
		).is_true()


func test_the_def_row_names_the_worn_armor() -> void:
	# DEF is gear-only, so the readout has to name the piece paying it; "DEF 0" alone would be
	# indistinguishable from wearing nothing.
	var unit := _inspect_a_dressed_unit()
	await await_idle_frame()

	var found := false
	for entry in _rendered_tooltips():
		if str(entry[1]).contains(unit.worn_armor.item_name):
			found = true
	assert_bool(found).override_failure_message(
		"No rendered tooltip names the worn armor (%s) -- the DEF row is not reading worn_armor."
		% unit.worn_armor.item_name).is_true()


func test_a_gear_granted_ability_reaches_the_readout() -> void:
	# #90: the live kit is innate + jobs + WORN GEAR, derived live and never stored. The abilities
	# section has to show the gear-granted one, or the panel is reading the persistent half only.
	var unit := _inspect_a_dressed_unit()
	await await_idle_frame()

	var granted: Array[AbilityData] = unit.worn_armor.granted_abilities
	assert_int(granted.size()).is_greater(0)   # the fixture's armor must actually grant something

	var found := false
	for entry in _rendered_tooltips():
		if str(entry[1]).contains(granted[0].display_name):
			found = true
	assert_bool(found).override_failure_message(
		"The abilities section never renders '%s', granted by the worn armor -- the readout is missing the gear source of the live kit."
		% granted[0].display_name).is_true()
