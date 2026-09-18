# What a piece of gear SAYS on hover (#137), on the two pre-mission surfaces where a stranger picks
# it up. Both used to answer with the item's NAME and nothing else, so stripping the AI-written
# flavour out of the content files would have left them blank; the mechanical half is GENERATED
# (ArmorData.mechanical_text, VialData.mechanical_text), which is why there is anything to read.
#
# Reads the RENDERED tooltip off the row the player hovers, never ItemText.hover in isolation --
# tests/ui/test_rune_inventory_tooltip.gd's precedent: a builder that returns the right string
# proves nothing about whether the row ever wears it.
#
# THE CONTENT RAZOR: every item here is built in code and pushed into the live loadout, and every
# expectation is derived from the generator rather than typed out, so neither the shipped roster's
# contents nor the wording of a readout can red this suite.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__gear_hover_137.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# --- the phase, borrowed wholesale from tests/ui/test_pre_mission_screen.gd ---

func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the screen cannot be exercised")
		return ""
	return names[0]


func _author(roster: String, cap: int) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	var scenario := sm.capture_scenario("gear_hover_137", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _enter_phase() -> bool:
	var roster := _a_roster()
	if roster == "":
		return false
	mc.begin_mission(_author(roster, 2))
	await await_idle_frame()
	return _screen() != null


func _screen() -> PreMissionScreen:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _card_for(unit: Unit) -> PreMissionCard:
	for node in _walk(_screen()):
		var card := node as PreMissionCard
		if card != null and card.unit == unit:
			return card
	return null


# The row is found by the item it CARRIES, never by its position, so a reordered list is not a
# failure and an absent row is.
func _row_for(root: Node, item: Item) -> GearRow:
	for node in _walk(root):
		var row := node as GearRow
		if row != null and row.item == item:
			return row
	return null


func _redraw() -> void:
	_screen().refresh()
	await await_idle_frame()


# --- fixtures ---

func _plate(gate: bool) -> ArmorData:
	var plate := ArmorData.new()
	plate.display_name = "Test Plate"
	plate.def_power = 2
	if gate:
		var mins: Dictionary[Stats.Stat, int] = {}
		mins[Stats.Stat.STR] = 8
		plate.stat_minimums = mins
	return plate


func _vial(element: Elemental.Element) -> VialData:
	var vial := VialData.new()
	vial.display_name = "Test Vial"
	vial.element = element
	return vial


# The tooltip is WRAPPED, so a line wider than one tooltip line would come back broken and the
# containment check would fail for a reason that has nothing to do with the wire. Every fixture
# readout here is short; the width guard says so out loud rather than leaving that mysterious.
func _assert_says(tip: String, text: String, why: String) -> void:
	for line in text.split("\n"):
		assert_int(line.length()).override_failure_message(
			"the fixture's own readout is wider than a tooltip line, so wrapping broke it -- the "
			+ "fixture needs shortening, not the door").is_less(UiText.TOOLTIP_WIDTH)
		assert_str(tip).override_failure_message(why).contains(line)


# --- the stash: nobody to itemize for, and still something to read ---

func test_a_stash_row_says_what_a_piece_of_armour_demands() -> void:
	if not await _enter_phase():
		return
	var plate := _plate(true)
	mc.loadout().stash.append(plate)
	await _redraw()

	var bare := plate.mechanical_text(null)
	assert_str(bare).override_failure_message(
		"the fixture's armour describes itself as nothing, so this case cannot fail").is_not_empty()
	var row := _row_for(_screen(), plate)
	assert_object(row).override_failure_message("the stash drew no row for the armour").is_not_null()
	_assert_says(row.tooltip_text, bare,
		"a piece of armour in the stash hovers as its name alone")


func test_a_stash_row_says_what_a_vial_attunes() -> void:
	if not await _enter_phase():
		return
	var vial := _vial(Elemental.Element.FIRE)
	mc.loadout().stash.append(vial)
	await _redraw()

	var says := vial.mechanical_text()
	assert_str(says).is_not_empty()
	var row := _row_for(_screen(), vial)
	assert_object(row).override_failure_message("the stash drew no row for the vial").is_not_null()
	_assert_says(row.tooltip_text, says, "a vial hovers as its name alone")
	assert_str(row.tooltip_text).override_failure_message(
		"the readout never names the element the vial answers for"
	).contains(Elemental.display_name(Elemental.Element.FIRE))


# --- a unit's own gear: the same door, now with somebody to itemize for ---

func test_a_carried_row_itemizes_for_the_unit_holding_it() -> void:
	if not await _enter_phase():
		return
	var roster: Array[Unit] = mc.roster_units()
	if roster.is_empty():
		push_warning("the roster drew nobody, so there is no card to hover")
		return
	var wearer: Unit = roster[0]
	var plate := _plate(false)
	assert_bool(wearer.add_item(plate)).override_failure_message(
		"the fixture unit had no room for the armour").is_true()
	await _redraw()

	var card := _card_for(wearer)
	assert_object(card).is_not_null()
	var row := _row_for(card, plate)
	assert_object(row).override_failure_message("the card drew no row for the carried armour").is_not_null()
	_assert_says(row.tooltip_text, plate.mechanical_text(wearer),
		"the card hovers a piece of armour without the numbers it is worth to THIS unit")


# The null wielder is the stash's whole argument, and this is the property that states it: the same
# armour reads itemized on a card and un-itemized in the stash, where there is nobody to itemize for.
func test_the_stash_drops_the_terms_that_need_a_wearer() -> void:
	if not await _enter_phase():
		return
	var roster: Array[Unit] = mc.roster_units()
	if roster.is_empty():
		push_warning("the roster drew nobody, so there is no card to compare against")
		return
	var wearer: Unit = roster[0]
	var loose := _plate(false)
	mc.loadout().stash.append(loose)
	await _redraw()

	var itemized := loose.mechanical_text(wearer)
	var bare := loose.mechanical_text(null)
	assert_str(itemized).override_failure_message(
		"itemized and bare read the same, so this case could not tell them apart"
	).is_not_equal(bare)
	var row := _row_for(_screen(), loose)
	assert_object(row).override_failure_message("the stash drew no row for the armour").is_not_null()
	var scaled: String = itemized.split("\n")[0]
	assert_str(row.tooltip_text).override_failure_message(
		"the stash printed a wearer-scaled term with no wearer to scale it for"
	).not_contains(scaled)


# --- the one generator this ticket had to write ---

func test_an_alkahest_vial_says_it_answers_to_anything() -> void:
	var alkahest := _vial(Elemental.Element.NONE)
	alkahest.is_alkahest = true

	var says := alkahest.mechanical_text()
	assert_str(says).is_not_empty()
	# Never the five sigils listed out: granted_elements() answers the narrower empowerment
	# question, and matches() says alkahest charges anything at all.
	assert_str(says).not_contains(Elemental.display_name(Elemental.SIGIL_ELEMENTS[0]))


func test_a_vial_that_attunes_to_nothing_says_nothing() -> void:
	assert_str(_vial(Elemental.Element.NONE).mechanical_text()).override_failure_message(
		"a vial with no element authored invented a readout for itself").is_empty()
