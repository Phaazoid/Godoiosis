# The pre-mission screen (#740 + #743): the menu the player stands in over the phase #739 opened.
#
# WHAT THIS SUITE PINS AND WHAT IT DELIBERATELY DOES NOT. The screen locks the board by joining
# game.menu_is_up() rather than by eating clicks, because battle3d picks cells itself and calls
# game._on_left_click directly -- so a full-rect Control is transparent to the shipped view. That
# DOOR'S refusal is already pinned, by tests/presentation/test_input_bridge.gd's
# test_the_board_lock_refuses_bridge_clicks_natively, so what is missing and what these cases add is
# the PREDICATE: up means locked, hidden means not. Standing up a Battle3D fixture here would be a
# second copy of a test that exists.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__pre_mission_740.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6
# A visible vertical scrollbar eats width off the content it scrolls; anything wider than this is a
# region that expanded, anything narrower has collapsed to a minimum.
const SCROLLBAR_ALLOWANCE := 24.0

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


func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the screen cannot be exercised")
		return ""
	return names[0]


func _roster_size(name: String) -> int:
	var roster: Roster = RosterCatalog.resolve(name)
	return 0 if roster == null else roster.entries.size()


func _author(roster: String, cap: int) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	var scenario := sm.capture_scenario("pre_mission_740", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _enter_phase(cap := 2) -> bool:
	var roster := _a_roster()
	if roster == "" or _roster_size(roster) <= cap:
		push_warning("the shipped roster is not larger than the cap, so the screen has no reserve")
		return false
	mc.begin_mission(_author(roster, cap))
	await await_idle_frame()
	return true


func _screen() -> PreMissionScreen:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


func _cards() -> Array[PreMissionCard]:
	var found: Array[PreMissionCard] = []
	var screen := _screen()
	if screen == null:
		return found
	for node in _walk(screen):
		if node is PreMissionCard:
			found.append(node)
	return found


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


# --- the screen opens with the phase, and locks the board with it ---

func test_the_phase_opens_the_screen_and_the_board_behind_it_is_out_of_reach() -> void:
	if not await _enter_phase():
		return

	assert_object(_screen()).override_failure_message(
		"the phase opened with no screen").is_not_null()
	assert_bool(mc.deployment_menu_is_up()).is_true()
	assert_bool(game.menu_is_up()).override_failure_message(
		"the screen is up and the board is still the player's to click").is_true()
	assert_bool(game._board_locked_for_player()).override_failure_message(
		"THE predicate both click doors read -- battle3d's direct dispatch and _unhandled_input"
	).is_true()


# The board preview, and the case the whole design hangs on: hiding the menu has to hand the board
# back, or Tab shows you a board you cannot touch.
func test_swapping_to_the_board_hands_it_back_and_swapping_away_takes_it_again() -> void:
	if not await _enter_phase():
		return

	mc.toggle_deployment_menu()
	assert_bool(_screen().visible).is_false()
	assert_bool(game.menu_is_up()).override_failure_message(
		"the menu was swapped away and the board is still locked -- the preview is unusable").is_false()
	assert_bool(game._board_locked_for_player()).is_false()
	assert_int(game.game_state).override_failure_message(
		"the phase itself ended when the menu hid").is_equal(game.GameState.PRE_MISSION)

	mc.toggle_deployment_menu()
	assert_bool(_screen().visible).is_true()
	assert_bool(game.menu_is_up()).is_true()


# ModalCard._input has no visibility guard of its own, so a hidden card still receives ui_cancel.
# Harmless only while this screen declines to take that key -- set_process_input is what keeps it so.
func test_a_hidden_screen_stops_listening_for_input() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	assert_bool(screen.is_processing_input()).is_true()

	mc.toggle_deployment_menu()
	assert_bool(screen.is_processing_input()).override_failure_message(
		"a hidden card still eats keys, which breaks the moment it overrides _on_cancel").is_false()


# --- the three ways the phase ends, all of which must take the screen with them ---

func test_beginning_the_mission_from_the_screen_closes_it() -> void:
	if not await _enter_phase():
		return

	_screen()._on_begin()
	await await_idle_frame()
	# #774 put a confirm in front of the commit, on all three of its doors.
	for child in game.ui_layer.get_children():
		if child is ConfirmCard:
			child.answered.emit(true)
	await await_idle_frame()

	assert_object(_screen()).override_failure_message(
		"the screen outlived the mission it started").is_null()
	assert_bool(game.menu_is_up()).is_false()
	assert_bool(mc.is_deploying()).is_false()


# Abandon never reaches clear_board -- the board is left standing behind Mission Select -- so nothing
# else would ever take this screen down, and it would hold units the next load frees.
func test_abandoning_closes_the_screen() -> void:
	if not await _enter_phase():
		return

	mc.abandon_mission()
	await await_idle_frame()

	assert_object(_screen()).override_failure_message(
		"the screen survived Abandon, holding units the next mission will free").is_null()
	# #774's bar rides the same teardown, and this is the exit with no clear_board behind it: a
	# survivor here would sit over Mission Select offering to begin a mission nobody is in.
	for child in game.ui_layer.get_children():
		assert_bool(child is PreMissionBar).override_failure_message(
			"the board-side bar survived Abandon").is_false()


func test_a_board_swap_closes_the_screen() -> void:
	if not await _enter_phase():
		return

	sm.clear_board()   # F2, Load Game and the next mission all route through here
	await await_idle_frame()

	assert_object(_screen()).is_null()
	assert_bool(mc.deployment_menu_is_up()).is_false()


# --- the card grid ---

func test_the_grid_draws_one_card_per_roster_member() -> void:
	if not await _enter_phase():
		return
	var roster: Array[Unit] = mc.roster_units()
	assert_array(roster).is_not_empty()

	var cards := _cards()
	assert_int(cards.size()).override_failure_message(
		"the grid and the roster disagree about who exists").is_equal(roster.size())
	for i in range(cards.size()):
		assert_object(cards[i].unit).override_failure_message(
			"card %d is not the %d'th roster entry" % [i, i]).is_same(roster[i])


# THE case the entry-order store exists for, and the one an obvious version of it cannot see.
#
# Asserting the order at phase start is VACUOUS: the draw places the first N entries and leaves the
# rest in the reserve, both in entry order, so node order and entry order agree exactly at the only
# moment such a case looks. They diverge only once the player CHANGES THEIR MIND -- undeploying
# somebody reparents them to the end of the reserve -- which is what this drives before asking.
#
# (Measured: a mutant deriving roster_units() from node order passes an assert-at-start version of
# this, and passes it twice over, because _refresh_cards rebuilds only when the roster's SIZE
# changes, so the grid's order is settled at build time whatever the store says. The store is
# therefore belt-and-braces for the grid TODAY and the real contract underneath it -- kept and
# declared rather than deleted to make a mutant tidy.)
func test_the_roster_keeps_its_entry_order_after_the_player_changes_their_mind() -> void:
	if not await _enter_phase(2):
		return
	var before: Array[Unit] = mc.roster_units().duplicate()
	assert_int(before.size()).is_greater(2)

	var placed: Unit = null
	var waiting: Unit = null
	for unit: Unit in before:
		if placed == null and unit.get_parent() == game.units_root:
			placed = unit
		elif waiting == null and unit.get_parent() == game.reserve_root:
			waiting = unit
	assert_object(placed).is_not_null()
	assert_object(waiting).is_not_null()

	game.undeploy_unit(placed)                                    # -> the end of the reserve
	game.deploy_unit(waiting, mc.open_deployment_cells()[0])      # -> the end of units_root
	await await_idle_frame()

	assert_array(mc.roster_units()).override_failure_message(
		"the roster reordered when a unit was swapped -- a grid drawn off this would reshuffle "
		+ "under the player mid-decision").is_equal(before)


func test_a_deploy_toggle_puts_its_unit_on_the_board_and_takes_it_off_again() -> void:
	if not await _enter_phase(2):
		return
	var waiting: PreMissionCard = null
	for card in _cards():
		if card.unit.get_parent() == game.reserve_root:
			waiting = card
	assert_object(waiting).override_failure_message(
		"precondition: the cap left nobody in reserve").is_not_null()

	# Make room, then send the waiting one in -- through the card's own signal, which is the wire.
	var placed: PreMissionCard = _cards()[0]
	placed.deploy_toggled.emit(placed.unit)
	await await_idle_frame()
	assert_object(placed.unit.get_parent()).override_failure_message(
		"the toggle did not take a placed unit off the board").is_same(game.reserve_root)

	waiting.deploy_toggled.emit(waiting.unit)
	await await_idle_frame()
	assert_object(waiting.unit.get_parent()).override_failure_message(
		"the toggle did not bring a waiting unit in").is_same(game.units_root)
	assert_bool(mc.open_deployment_cells().has(waiting.unit.movement.cell)).override_failure_message(
		"the unit landed somewhere it should not have").is_false()


func test_a_cards_deploy_button_is_refused_once_the_cap_is_full_and_says_why() -> void:
	if not await _enter_phase(2):
		return
	assert_int(mc.deployed_roster_count()).is_equal(2)

	for card in _cards():
		if card.unit.get_parent() == game.reserve_root:
			assert_bool(card._deploy_button.disabled).override_failure_message(
				"the cap is full and this card still offers to place someone").is_true()
			assert_str(card._deploy_button.tooltip_text).override_failure_message(
				"a dead button with no reason on it").contains("full")
			return
	push_warning("the cap left nobody in reserve, so the refusal was not exercised")


# --- the contract, and the count that moved onto the force ---

# commit_deployment's refusal speaks through TurnBanner, which is a plain child of Game while this
# screen sits on a CanvasLayer -- so under the menu that banner cannot be seen at all. Begin has to
# carry its own refusal or it is a silent dead button.
func test_begin_is_refused_with_nobody_placed_and_carries_the_reason_itself() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	assert_bool(screen._begin_button.disabled).is_false()

	for card in _cards():
		if card.unit.get_parent() == game.units_root:
			game.undeploy_unit(card.unit)
	screen.refresh()

	assert_bool(screen._begin_button.disabled).override_failure_message(
		"Begin is live with nobody placed, and its refusal is invisible under this screen").is_true()
	assert_str(screen._begin_button.tooltip_text).contains("at least one")


# One builder, so the briefing before the battle and the status during it cannot word a condition
# differently -- the contract renders MissionStatusPanel.briefing_rows and nothing of its own.
func test_the_contract_renders_the_same_briefing_the_hud_does() -> void:
	if not await _enter_phase():
		return
	var drawn: Array[String] = []
	for row in _screen()._objectives_box.get_children():
		drawn.append((row as Label).text)
	assert_array(drawn).override_failure_message(
		"the contract drew nothing for a board with a declared objective").is_not_empty()

	var expected: Array[String] = []
	for row: Label in MissionStatusPanel.briefing_rows(mc, game._board()):
		expected.append(row.text)
		row.free()
	assert_array(drawn).override_failure_message(
		"the contract and the corner HUD are wording the same board differently").is_equal(expected)


func test_the_force_count_sits_on_the_deployed_strip_and_says_what_it_counts() -> void:
	if not await _enter_phase(2):
		return
	var screen := _screen()

	assert_str(screen._force_strip_count.text).override_failure_message(
		"a bare '2 / 4' beside the force names nothing").contains("members")
	assert_str(screen._force_strip_count.text).contains("2")
	assert_str(screen._force_count.text).contains("deployed")


# --- the two structural laws ---

# Load-bearing rather than styling: nothing is frozen behind this screen -- it claims no ModalLock --
# so CameraController's WASD poll and HoverPresenter._process are still running underneath.
func test_the_backdrop_is_fully_opaque() -> void:
	if not await _enter_phase():
		return
	var backdrop: ColorRect = null
	for child in _screen().get_children():
		if child is ColorRect:
			backdrop = child
			break
	assert_object(backdrop).is_not_null()
	assert_float(backdrop.color.a).override_failure_message(
		"a translucent backdrop shows the board panning under the menu").is_equal(1.0)


# #418's law: a card whose content can grow must bound its own body. Every one of these lists is
# authored or roster-sized, so any of them can outgrow its region.
func test_every_list_that_can_grow_scrolls_inside_its_own_region() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	for named: Array in [
		["the card grid", screen._grid],
		["the stash", screen._stash_box],
		["the contract's conditions", screen._objectives_box],
		["the deployed force", screen._squads_row],
	]:
		var node: Control = named[1]
		var bounded := false
		var walk: Node = node.get_parent()
		while walk != null and walk != screen:
			if walk is ScrollContainer:
				bounded = true
				break
			walk = walk.get_parent()
		assert_bool(bounded).override_failure_message(
			"%s can grow and is not inside a ScrollContainer -- it will push the layout out of the "
			% named[0] + "viewport rather than scroll").is_true()
		if not bounded:
			continue

		# ...AND IT HAS TO HAVE A WIDTH ONCE IT IS IN THERE. The ancestry assertion above is blind to
		# geometry, which is how the stash shipped as rows a pixel or two wide: a ScrollContainer lays
		# its child out at the child's COMBINED MINIMUM unless the child's flags carry SIZE_EXPAND, and
		# every label on this screen is clip_text, so that minimum is zero by design. Structure and
		# geometry are two claims and one cannot cover for the other.
		var scroll: ScrollContainer = walk
		assert_float(node.size.x).override_failure_message(
			"%s is %d px wide inside a %d px scroller -- its content collapsed to its minimum"
			% [named[0], node.size.x, scroll.size.x]).is_greater(scroll.size.x - SCROLLBAR_ALLOWANCE)


# The outline his mockup had and the build did not: a unit that is coming with you is readable from
# the grid rather than by checking six toggles. Both directions, because a state that cannot be left
# is a state nobody can trust -- and the colour is asserted against QueueStyle rather than a literal,
# so the parchment palette moves it without touching this.
func test_a_deployed_units_card_wears_the_friendly_outline_and_gives_it_back() -> void:
	if not await _enter_phase(1):
		return
	var plain: PreMissionCard = null
	var placed: PreMissionCard = null
	for card in _cards():
		if game.is_deployed(card.unit):
			placed = card
		else:
			plain = card
	assert_object(placed).override_failure_message("the draw placed nobody").is_not_null()
	assert_object(plain).override_failure_message("every card is deployed, so there is nothing to "
		+ "contrast against").is_not_null()

	var ally := QueueStyle.ink(QueueStyle.Role.READOUT_ALLY)
	assert_object(_border_of(placed)).is_equal(ally)
	assert_object(_border_of(plain)).is_not_equal(ally)

	# ...and it follows the toggle, rather than being decided once at build time.
	placed.deploy_toggled.emit(placed.unit)
	await await_idle_frame()
	assert_object(_border_of(placed)).override_failure_message(
		"the card kept its outline after coming off the board").is_not_equal(ally)
	plain.deploy_toggled.emit(plain.unit)
	await await_idle_frame()
	assert_object(_border_of(plain)).override_failure_message(
		"a card deployed after build never took the outline").is_equal(ally)


func _border_of(card: PreMissionCard) -> Color:
	var box := card.get_theme_stylebox("panel") as StyleBoxFlat
	return Color.MAGENTA if box == null else box.border_color


# --- the aura ring rides the portrait (#930) ---

# THE WIRE, not the two ends: the card's own identity column has to carry a real AuraRing reading this
# card's own unit. A widget that exists and a card that draws one are different facts, and only the
# second is what the player sees.
#
# It also pins the PLACEMENT, which is a dev ruling rather than a detail: the ring rides the portrait
# so the card's BODY stays free for a weapon-proficiency readout the day proficiency does something
# (dev, 2026-09-12). A ring that drifted into the stat region would spend room that is spoken for.
func test_every_card_wears_its_units_aura_ring_around_the_portrait() -> void:
	if not await _enter_phase():
		return
	var cards := _cards()
	assert_int(cards.size()).is_greater(0)

	for card in cards:
		var rings: Array[Node] = []
		for node in _walk(card):
			if node is AuraRing:
				rings.append(node)
		assert_int(rings.size()).override_failure_message(
			"%s's card draws %d aura rings" % [card.unit.get_unit_name(), rings.size()]).is_equal(1)

		var ring: AuraRing = rings[0]
		assert_object(ring.unit).is_same(card.unit)
		# It draws the portrait itself -- that is what lets the hover readout land on top of the
		# sprite rather than under it, and it is why nothing else in the column holds one.
		assert_object(ring.portrait).is_same(card.unit.unit_data.map_sprite)
		assert_that(ring.ground).is_equal(AuraRing.Ground.SKINNED)
		# It frames the CHARACTER, not the canvas: every map sprite draws its ink in the lower half of
		# its sheet, so an ink-centred ring sits BELOW the box's middle and a box-centred one does not.
		# Without this the difference is invisible to a headless suite -- a mutant proved it.
		assert_float(ring._centre.y).override_failure_message(
			"the ring is centred on the sprite's canvas, so it frames the empty half above the "
			+ "character").is_greater(ring.size.x * 0.5)

		# THE RESERVATION, as an assertion rather than a comment: the ring ends above the stat grid,
		# so the card's bottom-left region is still empty for the proficiency readout to land in.
		var grid: GridContainer = null
		for node in _walk(card):
			if node is GridContainer:
				grid = node
		assert_object(grid).is_not_null()
		assert_float(ring.global_position.y + ring.size.y).override_failure_message(
			"the aura ring reaches into the card body that #930 reserved").is_less_equal(
			grid.global_position.y)


# --- every name on the screen is drawn whole (#944) ---

const GENERIC_FAMILY := preload("res://Resources/Weapons/MainVarieties/Carbine.tres")


# Wide enough to draw what is written in it -- measured off the font the label ACTUALLY draws with,
# so nothing here pins a pixel count and no theme or font change can make the assertion lie. This is
# the property the bug report names ("cut off instead of continuing to the right") stated in the one
# unit a feel pass cannot move.
static func _draws_in_full(label: Label) -> bool:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return true   # nothing to measure against; the width assertions below still speak
	var needed := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x
	return label.size.x + 0.5 >= needed


func _label_reading(root: Node, text: String) -> Label:
	for node in _walk(root):
		var label := node as Label
		if label != null and label.text == text:
			return label
	return null


# THE CARD. Two assertions, because either alone is blind: a short roster name might fit the portrait
# column at some font sizes, and a box wider than the column still has to hold what is in it.
func test_every_roster_card_draws_its_units_name_in_full() -> void:
	if not await _enter_phase():
		return
	var cards := _cards()
	assert_int(cards.size()).is_greater(0)

	for card in cards:
		var who := card.unit.get_unit_name()
		var label := _label_reading(card, who)
		assert_object(label).override_failure_message(
			"%s's card draws no label carrying their name" % who).is_not_null()
		# The RULE: the name is not confined to the portrait column. It used to be a child of the
		# identity VBox, where a VBox child is exactly its container's width.
		assert_float(label.size.x).override_failure_message(
			"%s's name is clipped to the %d-px portrait column" % [who, PreMissionCard.SPRITE]) \
			.is_greater(float(PreMissionCard.SPRITE))
		assert_bool(_draws_in_full(label)).override_failure_message(
			"%s's name is drawn in a box narrower than the name" % who).is_true()


# THE DEPLOYED STRIP, the same rule at the surface that answers it the other way round: these labels
# do not clip at all, because the strip WRAPS and SCROLLS where the card grid cannot. The squad title
# is the half that was visibly broken -- a solo squad's block is one 46-px slot wide, so "unsquadded"
# drew as "unsquadd".
func test_the_deployed_strip_spells_every_name_and_squad_title_in_full() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	assert_object(screen).is_not_null()

	var titles := 0
	var checked := 0
	for node in _walk(screen._squads_row):
		var label := node as Label
		if label == null or label.text == "":
			continue
		checked += 1
		if label.text == "unsquadded" or label.text.ends_with(" leads"):
			titles += 1
		assert_bool(_draws_in_full(label)).override_failure_message(
			"\"%s\" is clipped on the deployed strip" % label.text).is_true()

	# Both guards, because this case is entirely a loop: an empty strip and a strip of nameless chips
	# would each pass every assertion above without one.
	assert_int(titles).override_failure_message(
		"no squad block drew a title, so the half that was visibly broken went unchecked") \
		.is_greater(0)
	assert_int(checked).override_failure_message(
		"the strip drew no labelled chips at all").is_greater(titles)


# --- a generic weapon lists as its family (#945) ---

# An unmodified weapon carries NO display_name of its own -- the field is its optional pet name, and
# a DERIVED generic (#835) never has one. Item.shown_name() is the one door that reads the family's
# through, and every surface that read the raw field drew a blank row instead.
#
# The fixture is built rather than borrowed: a roster that happened to hold an authored VARIANT would
# pass with the bug in place, because there the field and the door agree.
func test_a_weapon_with_no_pet_name_of_its_own_lists_as_its_family() -> void:
	if not await _enter_phase():
		return
	var cards := _cards()
	assert_int(cards.size()).is_greater(0)

	var generic := WeaponInstance.make(GENERIC_FAMILY)
	assert_object(generic).is_not_null()
	# The premise, asserted rather than assumed -- if make() ever started copying the template's
	# wording, this case would be testing nothing.
	assert_str(generic.display_name).override_failure_message(
		"a freshly made instance already carries a name, so this case proves nothing").is_empty()
	assert_str(GENERIC_FAMILY.display_name).is_not_empty()

	var card: PreMissionCard = cards[0]
	card.unit.inventory[Unit.MAX_INVENTORY_SIZE - 1] = generic
	card.refresh()
	await await_idle_frame()

	assert_object(_label_reading(card, GENERIC_FAMILY.display_name)).override_failure_message(
		"the card lists the generic with a blank name instead of \"%s\""
		% GENERIC_FAMILY.display_name).is_not_null()
