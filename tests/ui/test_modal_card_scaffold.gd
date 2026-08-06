# The ModalCard base's contract, pinned ONCE for every surface built on it rather than once per
# surface (#143 + its follow-up). The bug this replaces hit PauseMenu, MissionEndBanner and
# CrisisPrompt identically because they hand-built the same chrome: set_anchors_preset instead of
# set_anchors_and_offsets_preset left every one of them at (0,0) in the top-left corner.
#
# Three things are asserted here, and each is falsified against its own bug (see the header of each
# section): SIZING, the ModalLock FREEZE each surface declares, and the UiLayers Z-ORDER.
#
# The z-order cases exist because the modal cards previously set no z_index at all while
# HoverInfoPanelControl (a sibling under the same UILayer) authored 2 in its .tscn -- so the hover
# card drew ON TOP of the pause menu, the victory banner and the Crisis prompt.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()
	game.mission_controller._close_mission_select()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	if is_instance_valid(game):
		game.process_mode = Node.PROCESS_MODE_INHERIT
	remove_child(_main)
	_main.free()


# ModalLock freezes the game subtree, so a pausable Timer (gdUnit4's await_millis) is not a safe
# wait here -- same reason test_pause_menu.gd/test_report_flow.gd use frame counting.
func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _backdrop_of(card: ModalCard) -> ColorRect:
	for child: Node in card.get_children():
		if child is ColorRect:
			return child
	return null


# The frame's own panel: the base parents it directly under the CenterContainer it builds.
# Deliberately NOT find_children("*", "PanelContainer") -- ScrollContainer carries an INTERNAL
# PanelContainer named _focus, so a recursive type search answers "is there a panel anywhere in
# here", which is a different question and reports a frame that was never built.
func _chrome_panel(card: ModalCard) -> PanelContainer:
	for child: Node in card.get_children():
		if child is CenterContainer:
			for grandchild: Node in child.get_children():
				if grandchild is PanelContainer:
					return grandchild
	return null


# Every ModalCard fills the viewport and sits at the z-order its subclass declared. A FRAMED card
# also centres its panel; an unframed takeover has no panel to centre.
func _assert_chrome(card: ModalCard, expected_z: int) -> void:
	var viewport_size: Vector2 = card.get_viewport_rect().size
	assert_vector(card.size).is_equal(viewport_size)
	assert_int(card.z_index).is_equal(expected_z)

	var panel := _chrome_panel(card)
	if not card.framed:
		assert_object(panel).is_null()
		return

	assert_object(panel).is_not_null()
	var panel_center: Vector2 = panel.global_position + panel.size / 2.0
	# Container layout settles to whole pixels; a fractional off-by-one either way is the layout
	# engine rounding, not a mis-centred panel.
	var diff: Vector2 = (panel_center - viewport_size / 2.0).abs()
	assert_bool(diff.x <= 1.0 and diff.y <= 1.0).is_true()


# ==============================================================================
#  The four locking cards
# ==============================================================================

func test_pause_menu_fills_the_viewport_locks_and_outranks_the_hover_panel() -> void:
	var menu := PauseMenu.new()
	game.ui_layer.add_child(menu)
	menu._build(true, game)
	await _frames(4)

	_assert_chrome(menu, UiLayers.MODAL_CARD)
	assert_bool(ModalLock.any_open(get_tree())).is_true()
	assert_bool(game.can_process()).is_false()
	# The bug the z-table closes: the hover card is a sibling under this same UILayer.
	assert_bool(menu.z_index > UiLayers.HOVER_PANEL).is_true()

	menu.chosen.emit(PauseMenu.Choice.RESUME)
	menu.queue_free()
	await _frames(4)
	assert_bool(game.can_process()).is_true()


func test_mission_end_banner_fills_the_viewport_and_locks_the_board() -> void:
	var banner := MissionEndBanner.new()
	game.ui_layer.add_child(banner)
	banner._build(true, true, game)
	await _frames(4)

	_assert_chrome(banner, UiLayers.MODAL_CARD)
	assert_bool(ModalLock.any_open(get_tree())).is_true()
	assert_bool(game.can_process()).is_false()

	banner.chosen.emit(MissionEndBanner.Choice.STAY)
	banner.queue_free()
	await _frames(4)
	assert_bool(game.can_process()).is_true()


func test_crisis_prompt_fills_the_viewport_and_locks_the_board() -> void:
	var prompt := CrisisPrompt.new()
	game.ui_layer.add_child(prompt)
	prompt._build("Test Unit", game)
	await _frames(4)

	_assert_chrome(prompt, UiLayers.MODAL_CARD)
	assert_bool(ModalLock.any_open(get_tree())).is_true()
	assert_bool(game.can_process()).is_false()

	prompt.chosen.emit(false)
	prompt.queue_free()
	await _frames(4)
	assert_bool(game.can_process()).is_true()


func test_report_panel_fills_the_viewport_and_locks_the_board() -> void:
	var panel := ReportPanel.open(game, BugReporter.Kind.BUG, false, false)
	await _frames(4)

	_assert_chrome(panel, UiLayers.MODAL_CARD)
	assert_bool(ModalLock.any_open(get_tree())).is_true()
	assert_bool(game.can_process()).is_false()

	panel.queue_free()
	await _frames(4)
	assert_bool(game.can_process()).is_true()


# ==============================================================================
#  The takeover -- the ModalCard that is deliberately NOT a modal
# ==============================================================================

func test_mission_select_is_unframed_and_never_freezes_the_game() -> void:
	# The riskiest step of putting this screen on ModalCard: it must NOT inherit the lock. A Game
	# left DISABLED here would never run the mission picked next. test_pause_menu.gd's
	# test_return_to_title_lands_on_the_menu_with_the_game_thawed guards the same thing end-to-end.
	var screen := MissionSelectScreen.open(game, [] as Array[String], [] as Array[String])
	await _frames(4)

	_assert_chrome(screen, UiLayers.MENU_SCREEN)
	assert_bool(screen.claims_modal_lock).is_false()
	assert_bool(ModalLock.any_open(get_tree())).is_false()
	assert_bool(game.can_process()).is_true()

	screen.queue_free()
	await _frames(2)


func test_mission_select_backdrop_is_fully_opaque() -> void:
	# LOAD-BEARING, not styling: MissionController.abandon_mission leaves the abandoned board
	# standing on purpose and relies on this backdrop to hide it. Until now that dependency was
	# protected only by a prose comment.
	var screen := MissionSelectScreen.open(game, [] as Array[String], [] as Array[String])
	await _frames(4)

	var backdrop := _backdrop_of(screen)
	assert_object(backdrop).is_not_null()
	assert_bool(backdrop.color.a == 1.0).is_true()

	screen.queue_free()
	await _frames(2)


func test_a_card_outranks_the_menu_screen_it_can_open_over() -> void:
	# The report card is reachable FROM mission select (its Send Feedback row), so it has to draw
	# over it. That relationship used to live only in a comment on ReportPanel.PANEL_Z.
	assert_bool(UiLayers.MODAL_CARD > UiLayers.MENU_SCREEN).is_true()
	assert_bool(UiLayers.MENU_SCREEN > UiLayers.INVENTORY_POPUP).is_true()
	assert_bool(UiLayers.INVENTORY_POPUP > UiLayers.HOVER_PANEL).is_true()
