# The job picker on the pre-mission card (#742) -- his ruling that a job is "selectable from the top
# left area where job name is displayed".
#
# WHAT A HEADLESS SUITE CANNOT SEE, said out loud: nothing here proves Godot turns a real click on a
# real OptionButton into item_selected, or that opening the list fires about_to_popup. Both signals are
# emitted directly. The honest proxy is that the control is enabled and mouse-reachable at all, which
# is asserted below and catches the likeliest way this breaks -- the same declaration
# test_gear_moves_on_screen.gd makes about drag and drop, for the same reason.
#
# THE PICKER IS NEVER REBUILT and the identity case is what holds that: a rebuild would replace the
# control the pick came out of, and node identity is the only assertion that can tell a refresh-in-place
# from a rebuild that restores the same text (#745's lesson, arriving at a second surface).
#
# WHAT IT MAY LIST is the last section (#964). Those cases doctor the phase's live Loadout and build
# their own card, because the picker is built once and the offer has to be in place before it is --
# and because a case reading the shipped rosters' own ticks would be pinning authored content.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const F := preload("res://tests/support/job_fixtures.gd")
const SCRATCH := "user://__job_picker_742.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController
var _tank: JobData
var _tank_snap: Dictionary


func before_test() -> void:
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)
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
	F.restore(_tank, _tank_snap)
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _enter_phase(cap := 2) -> bool:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the screen cannot be exercised")
		return false
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = names[0]
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	assert_int(ResourceSaver.save(sm.capture_scenario("job_picker_742", true), SCRATCH)).is_equal(OK)
	mc.begin_mission(SCRATCH)
	await await_idle_frame()
	return not mc.roster_units().is_empty()


func _a_card() -> PreMissionCard:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			for node in _walk(child):
				if node is PreMissionCard:
					return node
	return null


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _index_of(picker: OptionButton, job_id: String) -> int:
	for i in picker.item_count:
		if String(picker.get_item_metadata(i)) == job_id:
			return i
	return -1


func _chip_texts(card: PreMissionCard) -> Array[String]:
	var out: Array[String] = []
	for child in card._abilities_row.get_children():
		var label := child as Label
		if label != null:
			out.append(label.text)
	return out


func _ability(id: Abilities.Id) -> AbilityData:
	var ability := AbilityData.new()
	ability.id = id
	ability.display_name = String(Abilities.Id.keys()[id])
	return ability


# A piece with a ceiling exactly at what this unit has now: legal until anything nudges that stat up.
func _wear_ceiling_plate(unit: Unit, stat: Stats.Stat) -> ArmorData:
	var plate := ArmorData.new()
	plate.display_name = "Test Plate"
	plate.def_power = 2
	plate.stat_maximums = {stat: unit.get_body_stat(stat)}
	assert_bool(unit.add_item(plate)).is_true()
	assert_bool(unit.wear_armor(unit.inventory.find(plate))).is_true()
	return plate


# --- the pick reaches the unit ---------------------------------------------------------------------

func test_the_picker_opens_on_what_the_unit_holds_and_offers_no_job_as_a_real_choice() -> void:
	if not await _enter_phase():
		return
	var card := _a_card()
	assert_object(card).is_not_null()
	var picker := card._job_picker

	# Every roster character authors no starting job, so this is the state it opens in for all of them
	# -- which is exactly why "none" has to be a row rather than an absence.
	assert_array(card.unit.unit_instance.jobs).is_empty()
	assert_str(String(picker.get_item_metadata(picker.selected))).is_empty()
	assert_int(_index_of(picker, "tank")).is_greater(0)

	# The closest a headless suite gets to "a player can click this".
	assert_bool(picker.disabled).is_false()
	assert_int(picker.mouse_filter).is_not_equal(Control.MOUSE_FILTER_IGNORE)
	# The card's own width law: an OptionButton sized to its widest ITEM walks the column out of the
	# region, and fit_to_longest_item defaults TRUE.
	assert_bool(picker.fit_to_longest_item).is_false()


func test_picking_a_job_reaches_the_unit_and_the_ability_chips_follow() -> void:
	if not await _enter_phase():
		return
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var card := _a_card()
	var unit := card.unit
	assert_array(_chip_texts(card)).not_contains(["TAUNT"])

	var index := _index_of(card._job_picker, "tank")
	card._job_picker.select(index)
	card._job_picker.item_selected.emit(index)
	await await_idle_frame()

	assert_array(unit.unit_instance.jobs).contains_exactly(["tank"])
	assert_array(_chip_texts(card)).override_failure_message(
		"the job landed on the unit but the card never redrew").contains(["TAUNT"])


# --- the option tooltip ----------------------------------------------------------------------------

# The one line the tooltip exists for. Driven through about_to_popup rather than by calling the builder
# directly, so the connection is part of what is pinned.
func test_the_option_tooltip_names_the_armour_the_job_would_take_off() -> void:
	if not await _enter_phase():
		return
	var card := _a_card()
	var plate := _wear_ceiling_plate(card.unit, Stats.Stat.DEX)
	_tank.stat_nudges = {Stats.Stat.DEX: 1}

	var popup: PopupMenu = card._job_picker.get_popup()
	popup.about_to_popup.emit()
	var tip := popup.get_item_tooltip(_index_of(card._job_picker, "tank"))

	assert_str(tip).contains(plate.display_name)
	assert_str(tip).contains("comes off")
	# The demand is read off the piece, never authored as prose -- retuning the gate rewords this.
	assert_str(tip).contains(plate.requirement_text())

	# ...AND THE NUMBERS REACH THE PLAYER. Both transitions are built from what the model predicts,
	# because the tooltip is the only place these are read: a mutant that previewed DEF as unchanged
	# passed every other case in this file, and its tooltip warned that the plate comes off while
	# claiming the defence it was worn for had not moved.
	var ids: Array[String] = ["tank"]
	var unit := card.unit
	assert_int(unit.previewed_def_for_jobs(ids)).is_not_equal(unit.get_effective_def())
	assert_str(tip).contains("DEF %d → %d" % [unit.get_effective_def(), unit.previewed_def_for_jobs(ids)])
	assert_str(tip).contains("DEX %d → %d" % [
		unit.get_effective_stat(Stats.Stat.DEX), unit.previewed_stat_for_jobs(Stats.Stat.DEX, ids)])
	# ...and the option that changes nothing says so rather than warning about a piece it keeps.
	assert_str(popup.get_item_tooltip(_index_of(card._job_picker, ""))).not_contains(plate.display_name)


# --- the control survives its own use --------------------------------------------------------------

func test_the_picker_is_refreshed_in_place_and_never_rebuilt_by_its_own_pick() -> void:
	if not await _enter_phase():
		return
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]
	var card := _a_card()
	var before := card._job_picker
	var before_chips := card._abilities_row.get_children()

	var index := _index_of(before, "tank")
	before.select(index)
	before.item_selected.emit(index)
	await await_idle_frame()

	# Non-vacuity: the refresh really ran, so the identity below is a claim rather than an accident.
	assert_array(card._abilities_row.get_children()).override_failure_message(
		"nothing was rebuilt at all, so surviving a rebuild proves nothing").is_not_equal(before_chips)
	assert_object(card._job_picker).override_failure_message(
		"the refresh replaced the control the pick came out of").is_same(before)
	assert_str(String(card._job_picker.get_item_metadata(card._job_picker.selected))).is_equal("tank")


# --- what the mission offers (#964) ----------------------------------------------------------------

# A FRESH card against a doctored Loadout, rather than the screen's own. The picker is built once, so
# the offer has to be in place before the card is -- and going through the phase's live Loadout is what
# keeps these cases off whichever jobs the shipped rosters happen to tick (tests/README.md rule 4).
func _card_offering(ids: Array[String]) -> PreMissionCard:
	mc.loadout().available_jobs = ids
	return auto_free(PreMissionCard.build(mc.roster_units()[0], mc)) as PreMissionCard


func _offered_ids(card: PreMissionCard) -> Array[String]:
	var out: Array[String] = []
	for i in card._job_picker.item_count:
		out.append(String(card._job_picker.get_item_metadata(i)))
	return out


func test_the_picker_lists_what_the_mission_offers_and_nothing_else() -> void:
	if not await _enter_phase():
		return
	var only_tank: Array[String] = ["tank"]
	var card := _card_offering(only_tank)

	# "" is the none row, which is a real choice and never an offer.
	assert_array(_offered_ids(card)).override_failure_message(
		"the picker is reading the catalogue rather than the mission's own list"
		).contains_exactly_in_any_order(["", "tank"])


# The union, and the hole it closes: a character authoring a starting_job or a state_saved entry can
# arrive holding a job this mission does not offer. Without it that unit falls into the unknown-id
# branch, draws the RAW id, and cannot pick the job back once it is dropped.
func test_a_job_the_unit_already_holds_is_listed_even_when_the_mission_does_not_offer_it() -> void:
	if not await _enter_phase():
		return
	var carrier: Unit = mc.roster_units()[0]
	assert_str(carrier.set_sole_job("tank")).override_failure_message(
		"the fixture could not put a job on the unit, so the case below proves nothing").is_empty()

	var only_scout: Array[String] = ["scout"]
	mc.loadout().available_jobs = only_scout
	var card := auto_free(PreMissionCard.build(carrier, mc)) as PreMissionCard

	assert_array(_offered_ids(card)).override_failure_message(
		"the held job is missing from its own picker -- it draws as a raw id and cannot be re-picked"
		).contains(["tank"])
	# select(-1) is the raw-id branch: the control carries text with no row behind it.
	assert_int(card._job_picker.selected).override_failure_message(
		"the selection fell through to the raw-id branch instead of matching a listed row"
		).is_greater_equal(0)
	assert_str(String(card._job_picker.get_item_metadata(card._job_picker.selected))).is_equal("tank")


# EMPTY MEANS NONE here too: a dropdown holding only "— none —" is a control that cannot do anything.
func test_a_mission_offering_no_job_draws_no_picker_at_all() -> void:
	if not await _enter_phase():
		return
	var nothing: Array[String] = []
	var card := _card_offering(nothing)

	assert_object(card._job_picker).override_failure_message(
		"an offer of nothing still built a dropdown with only the none row in it").is_null()
	# The rest of the card is untouched, and the refresh that follows every redraw does not throw.
	card.refresh()
	assert_array(card._abilities_row.get_children()).is_not_empty()
