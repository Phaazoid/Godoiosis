# Can the player READ the pre-mission menus under either palette (#814)?
#
# WHY THIS IS NOT A CASE IN test_queue_palette.gd. That suite pins PAIRS -- this role against that
# ground -- and a pair test is structurally blind to the failure that produced this ticket: a label
# with NO font_color override at all. There is no colour to look up, so nothing can be compared, and
# five of the twelve reported sites were exactly that. The only way to see them is to build the real
# screen and ask each control what it will actually DRAW with.
#
# So this walks the live tree with tests/support/palette_contrast.gd, which reads both halves of every
# comparison off the running node (the ink through get_theme_color, the ground composited down the
# ancestor chain). The walker is shared with test_info_card_contrast since #1105.
#
# ONE CASE, MANY FINDINGS, deliberately: a failing case truncates the rest of its suite file in
# gdUnit4, and a contrast sweep whose first finding hides the other six is a sweep you have to run
# seven times. Every failure is collected and reported together, named by node path.
#
# It runs against PARCHMENT *and* slate. The element cases in test_queue_palette are parchment-only
# because their ink is derived and no knob may be constrained; every colour here is an authored
# chrome const, so a floor over both palettes constrains nothing the dev drags.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const PC := preload("res://tests/support/palette_contrast.gd")
const SCRATCH := "user://__pre_mission_814.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

# What the screens are drawn OVER. PreMissionScreen's own backdrop is opaque, so it is the bottom of
# every composite on that surface; the fitting card adds ModalCard's 70% black on top of it.
const SCREEN_BASE := Color(0.06, 0.06, 0.09)

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	PlayerSettings.reset_for_test()
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
	PlayerSettings.reset_for_test()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# --- the fixture, borrowed from test_pre_mission_screen ------------------------------------------

func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	return "" if names.is_empty() else names[0]


func _author(roster: String, cap: int) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	var scenario := sm.capture_scenario("pre_mission_814", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _screen() -> PreMissionScreen:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


# --- the law -------------------------------------------------------------------------------------

# The whole reported bug, as a property. Every palette, every label and button the two pre-mission
# surfaces build, against whatever is really painted behind it.
func test_every_word_on_the_pre_mission_menus_can_be_read_in_both_palettes() -> void:
	var roster := _a_roster()
	if roster == "":
		push_warning("no rosters are shipped, so the screens cannot be exercised")
		return

	for palette: int in [PlayerSettings.QueuePalette.DEFAULT, PlayerSettings.QueuePalette.PARCHMENT]:
		PlayerSettings.set_choice(PlayerSettings.Setting.QUEUE_PALETTE, palette)
		# The boxes are cached per palette, and the cache outlives a test -- a case that skipped this
		# would measure whichever palette ran first and agree with itself perfectly.
		QueueStyle._cache.clear()

		mc.begin_mission(_author(roster, 2))
		await await_idle_frame()
		var screen := _screen()
		assert_object(screen).override_failure_message(
			"the pre-mission phase did not open its screen, so nothing was measured").is_not_null()

		var found: Array[String] = PC.findings(screen, SCREEN_BASE, "palette %d" % palette)

		# The fitting card stacks over the screen, and carries BOTH grounds -- the engine's dark
		# frame plus parchment's cream zones -- so it is where a role picked by weight alone shows.
		var weapon := _a_stashed_weapon()
		if weapon != null:
			var card := ModFittingCard.open(game, weapon, null)
			await await_idle_frame()
			found.append_array(PC.findings(card, PC.over(Color(0, 0, 0, 0.7), SCREEN_BASE),
					"palette %d / fitting card" % palette))
			card.queue_free()
			await await_idle_frame()

		assert_array(found).override_failure_message(
			"unreadable text on the pre-mission menus:\n  %s" % "\n  ".join(found)).is_empty()

		sm.clear_board()
		await await_idle_frame()


# A PREVIEW IS A SECOND DOOR ONTO THE SAME LABELS, and the case above cannot see it: it measures the
# tree as BUILT, while #745's hover rewrites the stat grid in place and then puts it back. "Back" was
# spelled as REMOVING the font_color override, which is only the resting colour while that colour is
# the theme's -- i.e. only while the card's ground is dark in both palettes.
#
# Found by falsification, not by review: restoring that one line leaves this suite's other case, and
# all of test_pre_mission_screen, green. What a player would have seen is every number on a card
# going white-on-cream the moment they hovered a piece of gear and moved away.
func test_a_hover_puts_the_numbers_back_in_an_ink_that_can_still_be_read() -> void:
	var roster := _a_roster()
	if roster == "":
		push_warning("no rosters are shipped, so the screens cannot be exercised")
		return
	PlayerSettings.set_choice(PlayerSettings.Setting.QUEUE_PALETTE,
			PlayerSettings.QueuePalette.PARCHMENT)
	QueueStyle._cache.clear()

	mc.begin_mission(_author(roster, 2))
	await await_idle_frame()
	var screen := _screen()
	assert_object(screen).is_not_null()

	var card: PreMissionCard = null
	for node in PC.walk(screen):
		if node is PreMissionCard and not (node as PreMissionCard).unit.inventory.is_empty():
			card = node
			break
	if card == null:
		push_warning("no roster member carries anything, so no hover can be previewed")
		return

	# Through the SCREEN's own handlers rather than the card's methods: the screen is what decides
	# what a hover means, and a preview reached any other way is a preview the player cannot cause.
	var item: Item = card.unit.inventory[0]
	screen._on_gear_hovered(item, card)
	await await_idle_frame()
	screen._on_gear_unhovered(card)
	await await_idle_frame()

	var found: Array[String] = PC.findings(card, SCREEN_BASE, "after a hover")
	assert_array(found).override_failure_message(
		"a hover left the card unreadable:\n  %s" % "\n  ".join(found)).is_empty()


func _a_stashed_weapon() -> WeaponInstance:
	for item: Item in mc.loadout().stash:
		var weapon := item as WeaponInstance
		if weapon != null:
			return weapon
	for unit: Unit in mc.roster_units():
		for item: Item in unit.inventory:
			var weapon := item as WeaponInstance
			if weapon != null:
				return weapon
	return null
