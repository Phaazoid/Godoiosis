# A click on the HUD never reaches the board (#929 follow-up), driven with a REAL pointer on the 3D
# scene: clicks parsed into the window the way test_objective_rows drives the zone rows, so the event
# travels the shipped path -- the window, the game's SubViewport, the HUD's picking, and only if
# nothing catches it, battle3d._unhandled_input.
#
# The reported bug was a click on the aim strip's arrow aiming the attack at the cell underneath. The
# one thing that keeps a click off the board is the control under the pointer catching it, so every
# case asks the board door directly: battle3d moves its pointer to the clicked cell before anything
# else, and a click that never arrived leaves it where it was. tests/law/test_hud_catches_its_clicks.gd
# holds the rule for every surface; this suite shows it is the right rule.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
# Not a cell and not NO_CELL: a click that reaches the board replaces it with one or the other.
const UNTOUCHED := Vector3i(-77, -77, -77)

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var game: Node2D


func before() -> void:
	await _board.open(self, _clear_the_board)


func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	game = _board.scene.game
	# The boot title screen sits over the board and, rightly, over the HUD too.
	game.mission_controller._close_mission_select()
	# A headless window is never told the mouse ENTERED it (test_objective_rows says why).
	get_tree().root.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)


func after_test() -> void:
	game.exit_current_mode()
	await _move_to(Vector2(320, 300))
	await _board.check(self)


func after() -> void:
	_board.close()


# test_input_bridge's pump: deliver everything, then let the _process reconcile see it.
func _pump() -> void:
	Input.flush_buffered_events()
	await await_idle_frame()
	Input.flush_buffered_events()
	await await_idle_frame()
	await await_idle_frame()


func _move_to(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await _pump()


# Point at the control first and only then mark the pointer, so the board's own poll (which follows
# the cursor) has nothing left to answer and only the click itself could move it.
func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	await _move_to(at)
	_scene._pointer_cell = UNTOUCHED
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
	await _pump()


func _assert_board_untouched(what: String) -> void:
	var pointer: Vector3i = _scene._pointer_cell
	assert_that(pointer).override_failure_message(
			"a click on %s reached the board (it pointed at %s)" % [what, pointer]).is_equal(UNTOUCHED)


func _attack(attack_name: String) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = attack_name
	attack.power = 3
	return attack


# A pattern-less weapon carrying `names.size()` attacks, the first its main, aimed from a free cell.
func _aim(names: Array[String]) -> Unit:
	var template := WeaponData.new()
	template.display_name = "Probe"
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = _attack(names[0])
	for i in range(1, names.size()):
		template.extra_attacks.append(_attack(names[i]))
	var unit: Unit = null
	for cell: Vector2i in [Vector2i(3, 3), Vector2i(4, 4), Vector2i(2, 2), Vector2i(5, 5)]:
		unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
		if unit != null:
			break
	assert_object(unit).override_failure_message("no free cell to stand the attacker on").is_not_null()
	unit.equipped_weapon = WeaponInstance.make(template)
	game.selected_unit = unit
	game.enter_attack_mode(unit)
	await _pump()
	return unit


func _strip() -> AimStrip:
	return game.aim_strip as AimStrip


func _aiming() -> bool:
	return game.game_state == game.GameState.ATTACK_TARGETING


func _queued(unit: Unit) -> int:
	return (unit.squad as Squad).action_queue.size()


func test_a_click_on_the_aim_strip_stays_on_the_strip() -> void:
	var unit := await _aim(["Swing"])
	var box: Control = _strip()._box
	assert_bool(box.is_visible_in_tree()).override_failure_message("the aim drew no strip").is_true()

	await _click(box)
	_assert_board_untouched("the aim strip")
	assert_bool(_aiming()).override_failure_message("the click on the strip closed the aim").is_true()
	assert_int(_queued(unit)).is_equal(0)


func test_the_strip_arrows_cycle_the_aim_like_the_keys() -> void:
	var unit := await _aim(["Swing", "Thrust"])
	var arrows := _strip().arrows()
	var back: Button = arrows[0]
	var next: Button = arrows[1]
	assert_bool(next.is_visible_in_tree()).override_failure_message(
			"two attacks, and the strip offered no arrow").is_true()

	await _click(next)
	_assert_board_untouched("the strip's next arrow")
	assert_str(unit.get_fired_attack().display_name).is_equal("Thrust")
	assert_str(_strip().shown_text()).contains("Thrust")

	await _click(back)
	_assert_board_untouched("the strip's back arrow")
	assert_str(unit.get_fired_attack().display_name).is_equal("Swing")
	assert_bool(_aiming()).is_true()
	assert_int(_queued(unit)).is_equal(0)


# The objectives header and the two signs in the top-right corner -- plain lines, caught by their box
# or by themselves. Mid-aim, the state the reported click was made in.
func test_a_click_on_the_corner_text_stays_on_the_hud() -> void:
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	game.mission_controller.set_objectives(objectives)
	game.refresh_mission_status()
	var unit := await _aim(["Swing"])
	var panel: MissionStatusPanel = game.mission_status_panel
	var lines := {
		"the objectives header": panel._rows.get_child(0) as Control,
		"the F3 sign": panel._report_hint,
		"the version stamp": panel._version_label,
	}
	for what: String in lines:
		var line: Control = lines[what]
		assert_bool(line.is_visible_in_tree()).override_failure_message(
				"%s is not on screen to click" % what).is_true()
		await _click(line)
		_assert_board_untouched(what)
		assert_bool(_aiming()).override_failure_message("a click on %s closed the aim" % what).is_true()
	assert_int(_queued(unit)).is_equal(0)
