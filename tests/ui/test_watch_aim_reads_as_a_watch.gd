# Declaring an overwatch has to LOOK different from firing a shot (#591). It did not: since #413
# `enter_overwatch_mode` has been `enter_attack_mode(unit, AimIntent.WATCH)`, and nothing read the
# intent again until the click landed — same reach fill, same footprint fill, same pulse — so the
# only way to know which verb you were committing was to remember which ring row you clicked.
#
# The dev's pick was COLOUR (2026-08-27), which puts the whole question on two layers' `modulate`.
# That is exactly why these cases can exist headlessly at all, and it is also where the two traps
# are: the aim FILL is written by three different paths (mode entry, the pulse's two endpoints, the
# pulse's restore), and the HOVER layer is shared with PICKING_TARGET, so a watch aim that does not
# clean up tints the next rescue's tile pick.
#
# Every expectation is DERIVED from the knob (`OverlayManager.attack_reach_color`/`aim_fill_color`),
# never a literal: all four colours are Game-tab rows, and pinning one here would red the suite the
# first time the dev tunes it.
#
# Fixture is #114's -- the instanced root MUST be named "Main" under /root.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

const WATCHER_CELL := Vector2i(1, 1)
const AIM_CELL := Vector2i(2, 1)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()


func _overlays() -> OverlayManager:
	return game.overlay_manager


func _reach_layer() -> CanvasItem:
	return _overlays().attack_overlay


func _fill_layer() -> CanvasItem:
	return _overlays().hover_overlay


# A pattern-less weapon (Reach falls back to Manhattan 1) on a unit that can declare either verb.
func _watcher(targets := EquippableData.TargetMode.UNIT, heals := false) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), WATCHER_CELL)
	assert_object(unit).is_not_null()   # the fixture's own setup, not the thing under test
	var weapon := H.make_weapon(3)
	weapon.template.main_attack.targets = targets
	weapon.template.main_attack.heals = heals
	unit.equipped_weapon = weapon
	return unit


func _aiming() -> AttackData:
	var unit: Unit = game.selected_unit
	return unit.get_fired_attack() if unit != null else null


# Enter the mode and aim at a cell, the way the mouse does.
func _aim(unit: Unit, watch: bool) -> void:
	if watch:
		game.enter_overwatch_mode(unit)
	else:
		game.enter_attack_mode(unit)
	game.selected_unit = unit
	game.hover_presenter._hover_attack_targeting(AIM_CELL)


func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)

# ==============================================================================
#  The fork itself
# ==============================================================================

# The big ambient read: the whole reach wash changes colour, so the verb is legible before the
# player has hovered anything in particular.
func test_the_reach_wash_says_which_verb_is_being_aimed() -> void:
	var unit := _watcher()

	_aim(unit, false)
	assert_that(_reach_layer().modulate).override_failure_message(
			"a plain attack aim is not painting the ordinary reach colour"
		).is_equal(OverlayManager.attack_reach_color(_aiming(), false))
	var firing: Color = _reach_layer().modulate

	game.exit_current_mode()
	_aim(unit, true)

	assert_that(_reach_layer().modulate).override_failure_message(
			"declaring a watch paints the same reach as firing -- the whole bug"
		).is_not_equal(firing)
	assert_that(_reach_layer().modulate).is_equal(OverlayManager.attack_reach_color(_aiming(), true))


# And the footprint on top of it, which is what the player is actually looking at while aiming.
func test_the_aim_footprint_says_it_too() -> void:
	var unit := _watcher()

	_aim(unit, false)
	var firing: Color = _fill_layer().modulate
	assert_that(firing).is_equal(OverlayManager.aim_fill_color(false))

	game.exit_current_mode()
	_aim(unit, true)

	assert_that(_fill_layer().modulate).override_failure_message(
			"the aim footprint looks identical whichever verb is being declared"
		).is_not_equal(firing)
	assert_that(_fill_layer().modulate).is_equal(OverlayManager.aim_fill_color(true))


# The RULING, not an accident: the reach fill already forks red/green on `heals`, and a watch aim
# overrides that. You know what you picked off the ring; what you cannot otherwise tell is that you
# are declaring rather than firing. Asserted here because it is a decision, so it is the thing that
# will look like a bug to whoever reads the code next.
func test_the_watch_tint_beats_the_heal_fork() -> void:
	var unit := _watcher(EquippableData.TargetMode.UNIT, true)

	_aim(unit, false)
	assert_that(_reach_layer().modulate).override_failure_message(
			"a healing attack is not painting the heal reach -- the fixture never armed heals"
		).is_equal(OverlayManager.HEAL_ATTACK_MODULATE)

	game.exit_current_mode()
	_aim(unit, true)

	assert_that(_reach_layer().modulate).override_failure_message(
			"a healing WATCH is painting heal-green, so the verb is invisible again"
		).is_equal(OverlayManager.WATCH_REACH_MODULATE)

# ==============================================================================
#  The pulse, which is the trap
# ==============================================================================
# A MAP-hitting attack pulses its footprint tiles, and Pulse holds the two endpoints it was STARTED
# with. Read off the constants -- which is how this code looked before #591 -- a watch aim breathes
# back to the shot's yellow twice a second, and the fix on the entry path alone would look right in
# a screenshot and be wrong in motion.

func test_the_footprint_pulse_swings_toward_the_watchs_colour_and_not_the_shots() -> void:
	var unit := _watcher(EquippableData.TargetMode.MAP)
	_aim(unit, true)

	var pulse: Tween = _overlays()._tile_pulse
	assert_object(pulse).override_failure_message(
			"no tile pulse is running -- the fixture's attack does not hit MAP"
		).is_not_null()

	# Deterministic rather than frame-timed: step the tween half a swing and see which end it is
	# heading for. Both endpoints are derived, so tuning either colour moves the expectation too.
	pulse.custom_step(Pulse.PERIOD * 0.5)
	var landed: Color = _fill_layer().modulate

	assert_bool(_distance(landed, OverlayManager.aim_pulse_color(true))
			< _distance(landed, OverlayManager.aim_pulse_color(false))
		).override_failure_message(
			"the footprint pulse is swinging toward the SHOT's colour while a watch is being aimed"
		).is_true()


# The other end of the same trap: Pulse.stop RESTORES a value, and restoring the constant repaints
# the watch aim yellow the moment the player hovers a cell the attack cannot reach.
func test_the_pulse_stopping_restores_the_watchs_fill() -> void:
	var unit := _watcher(EquippableData.TargetMode.MAP)
	_aim(unit, true)
	assert_object(_overlays()._tile_pulse).is_not_null()

	_overlays().set_target_pulse([], false)

	assert_that(_fill_layer().modulate).override_failure_message(
			"stopping the pulse put the SHOT's fill back under a watch aim"
		).is_equal(OverlayManager.aim_fill_color(true))

# ==============================================================================
#  Cleaning up after itself
# ==============================================================================

# The HOVER layer is shared with PICKING_TARGET (HoverPresenter draws a rescue's candidate cells on
# it), so a watch aim that leaves its tint standing colours the next pick. Driven through the real
# exit rather than by resetting the flag, because the flag is the thing under test.
func test_leaving_a_watch_aim_puts_the_shots_colours_back() -> void:
	var unit := _watcher()
	_aim(unit, true)

	game.exit_current_mode()

	assert_that(_fill_layer().modulate).override_failure_message(
			"the watch tint outlived its aim and will paint the next tile pick"
		).is_equal(OverlayManager.aim_fill_color(false))
	assert_that(_reach_layer().modulate).is_equal(OverlayManager.attack_reach_color(null, false))

# ==============================================================================
#  The queued watch, which had no board presence at all
# ==============================================================================
# _preview_plan_effects previews terrain ignites, knockback shoves and pending Guards -- Guard got
# its ghost in #450 part 2 precisely because it was "visible only as a queue row until you pressed
# Execute", and a declared watch was still exactly that.

func test_a_queued_watch_ghosts_the_cells_it_will_cover() -> void:
	var unit := _watcher()
	game.queue_overwatch(unit, AIM_CELL)

	var ghosts: Array[Sprite2D] = _overlays().watch_preview_sprites
	assert_int(ghosts.size()).override_failure_message(
			"a queued overwatch drew nothing on the board -- the #450 gap, still open for watches"
		).is_greater(0)

	var marked: Array[Vector2i] = []
	for sprite in ghosts:
		marked.append(game.grid.local_to_map(sprite.position))
	assert_array(marked).override_failure_message(
			"the ghost is not on the cell the watch was aimed at"
		).contains([AIM_CELL])

	# GHOSTED, not solid: drawing a plan identically to a standing threat would tell the player they
	# are covered before the order has run.
	assert_that(ghosts[0].modulate).override_failure_message(
			"the queued watch's mark is drawn as loud as an armed one"
		).is_not_equal(OverlayManager.WATCH_MARK_COLOR)


# One mark per cell. A watch already standing on a cell outranks one that is merely promised, so the
# preview skips it rather than stacking a ghost under the solid mark.
#
# Asserted as a BEFORE and AFTER on the same cell rather than by scanning the ghosts for it: a scan
# passes over an empty list, which is exactly the state a broken preview would also be in.
func test_a_cell_an_armed_watch_already_marks_is_not_ghosted_underneath() -> void:
	var unit := _watcher()
	game.queue_overwatch(unit, AIM_CELL)
	assert_int(_overlays().watch_preview_sprites.size()).override_failure_message(
			"nothing was promised with the cell unmarked, so the skip below proves nothing"
		).is_equal(1)

	var footprint: Array[Vector2i] = [AIM_CELL]
	unit.arm_watch(WATCHER_CELL, AIM_CELL, footprint, unit.get_fired_attack())
	game.refresh_watch_markers()
	assert_array(_overlays().watch_cells).contains([AIM_CELL])
	game.refresh_action_queue(unit.squad)

	assert_int(_overlays().watch_preview_sprites.size()).override_failure_message(
			"a promised mark is stacked under the armed one on the same cell"
		).is_equal(0)
