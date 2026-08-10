# The dev Unit Editor's Down / Revive buttons (#156).
#
# The Down button is a deliberate BYPASS of the lethality ladder, not a simulated hit: it must not
# spend Will, must not maim, and must not trigger Crisis however the unit is armed. Those three are
# the cases with teeth -- the issue as FILED recommended routing through `take_damage`, which fails
# all three, so they are exactly what separates the built button from the specified one. Each of
# them first asserts what `LethalityRules.predict` WOULD have done with the same unit, so the case
# cannot quietly go vacuous if tuning moves underneath it.
#
# Every case presses the REAL Button node found in the panel rather than calling the handler. A
# handler that exists and a signal that fires are two different facts (#131 shipped a build whose
# modal buttons did nothing, on a 6-of-7 green suite).
#
# Needs the real game scene: the settle path runs through game.order_executor, and the went_downed
# connection it depends on is made in game.spawn_unit. Fixture is tests/ui/test_game_scene_smoke.gd's
# -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D
var _editor: UnitEditorTool


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	# Named + parented exactly as in production so game.gd's absolute /root/Main/DevOverlay lookup
	# resolves -- without it clear_board() nulls out on game.dev_overlay.unit_editor.
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	var overlay: DevOverlay = game.dev_overlay
	_editor = overlay.unit_editor
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(cell: Vector2i, overrides: Dictionary = {}) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(overrides, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


# The panel is rebuilt from scratch on every repaint, so a button is re-fetched by text each time
# rather than cached -- a stale reference would be a freed node after the first press.
func _button(label: String) -> Button:
	var container: Node = _editor.unit_editor_container
	for child in container.get_children():
		if child is Button and (child as Button).text == label:
			return child as Button
	return null


func _press(label: String) -> void:
	var button := _button(label)
	assert_object(button).override_failure_message("no %s button in the panel" % label).is_not_null()
	if button == null:
		return
	button.pressed.emit()


# What the LADDER would do to this unit for an exactly-lethal hit. The Down button must diverge from
# it on Will, maim and Crisis -- these cases assert that divergence, so they need the baseline.
func _ladder_verdict(unit: Unit) -> ResolvedOutcome.Lethality:
	return LethalityRules.predict(LethalityRules.situation_for(unit), unit.get_current_hp())


# ==============================================================================
#  The state transition
# ==============================================================================

func test_down_puts_the_unit_into_the_downed_state() -> void:
	var unit := _spawn(Vector2i(1, 0))
	_editor.edit_unit(unit)

	_press("Down Unit")

	assert_bool(unit.is_downed()).is_true()
	assert_int(unit.get_current_hp()).is_equal(1)
	assert_int(unit.downed_turns_remaining).is_equal(3)


func test_revive_stands_the_unit_back_up() -> void:
	var unit := _spawn(Vector2i(1, 0))
	_editor.edit_unit(unit)
	_press("Down Unit")

	_press("Revive Unit")

	assert_bool(unit.is_active()).is_true()
	assert_int(unit.downed_turns_remaining).is_equal(-1)


func test_the_buttons_track_lifecycle() -> void:
	var unit := _spawn(Vector2i(1, 0))
	_editor.edit_unit(unit)
	assert_bool(_button("Down Unit").disabled).is_false()
	assert_bool(_button("Revive Unit").disabled).is_true()

	_press("Down Unit")

	assert_bool(_button("Down Unit").disabled).is_true()
	assert_bool(_button("Revive Unit").disabled).is_false()


# ==============================================================================
#  The bypass -- what makes this button NOT a simulated hit
# ==============================================================================

func test_down_never_spends_will() -> void:
	var unit := _spawn(Vector2i(1, 0))
	var inst: UnitInstance = unit.unit_instance
	inst.set_current_will(UnitInstance.DOWN_WILL_COST)   # can afford the down: the ladder would charge it
	assert_int(_ladder_verdict(unit)).is_equal(ResolvedOutcome.Lethality.DOWNED)
	_editor.edit_unit(unit)

	_press("Down Unit")

	assert_int(inst.get_current_will()) \
		.override_failure_message("the Down button charged the down-Will cost") \
		.is_equal(UnitInstance.DOWN_WILL_COST)


func test_down_never_maims_a_unit_that_cannot_pay() -> void:
	var unit := _spawn(Vector2i(1, 0))
	var inst: UnitInstance = unit.unit_instance
	inst.set_current_will(UnitInstance.DOWN_WILL_COST - 1)   # can't pay -> the ladder takes a limb
	assert_int(inst.next_maim_slot()).is_not_equal(-1)       # and one IS available to take
	assert_int(_ladder_verdict(unit)).is_equal(ResolvedOutcome.Lethality.MAIMED)
	_editor.edit_unit(unit)

	_press("Down Unit")

	assert_bool(inst.is_maimed()) \
		.override_failure_message("the Down button maimed a unit that could not pay").is_false()
	assert_int(inst.get_current_will()).is_equal(UnitInstance.DOWN_WILL_COST - 1)
	assert_bool(unit.is_downed()).is_true()


func test_down_never_triggers_crisis_on_an_armed_unit() -> void:
	# WIL at the gate + the Berserker pool (Abilities.Id.CRISIS) is the exact input where an
	# exactly-lethal hit stands the unit back up surged instead of felling it.
	var unit := _spawn(Vector2i(1, 0), {Stats.Stat.WIL: UnitInstance.MAX_WILL})
	var inst: UnitInstance = unit.unit_instance
	inst.jobs.append("berserker")
	inst.set_current_will(inst.get_max_will())
	assert_bool(LethalityRules.crisis_armed_for(unit)).is_true()
	assert_int(_ladder_verdict(unit)).is_equal(ResolvedOutcome.Lethality.CRISIS)
	_editor.edit_unit(unit)

	_press("Down Unit")

	assert_bool(unit.in_crisis) \
		.override_failure_message("the Down button fired the Crisis gambit").is_false()
	assert_bool(unit.is_downed()).is_true()


# ==============================================================================
#  The settle -- there is no resolution pass to defer to
# ==============================================================================

# Ejection is DEFERRED to the end of execute_orders (#103), so a button press must drain the queue
# itself. Without it the body keeps its squad, its cohesion leash, and a tile its squadmates can
# still walk onto -- the exact state #156 exists to stop the dev having to work around.
func test_down_ejects_the_body_into_a_solo_squad() -> void:
	var leader := _spawn(Vector2i(1, 0))
	var member := _spawn(Vector2i(2, 0))
	await await_idle_frame()
	game.squad_manager.join_squad(member, leader.squad)
	assert_bool(leader.squad.get_members().has(member)).is_true()   # fixture guard
	_editor.edit_unit(member)

	_press("Down Unit")

	assert_bool(leader.squad.get_members().has(member)) \
		.override_failure_message("the downed body was never ejected -- the settle did not run") \
		.is_false()
	assert_int(game.order_executor._downed_pending.size()) \
		.override_failure_message("_downed_pending did not drain").is_equal(0)
	assert_bool(member.is_downed()).is_true()          # ejected, not removed from the board
	assert_that(member.movement.cell).is_equal(Vector2i(2, 0))
