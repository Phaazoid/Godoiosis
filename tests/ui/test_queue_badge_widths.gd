# Every badge the action-queue row can print has to FIT THE DOCK (#685 follow-up).
#
# The bug this exists for: a consequence pill wider than the line's leftover slack does not wrap and
# does not clip -- it pushes the row, its section and the whole scroll column PAST BackgroundPanel,
# because nothing between the row and that Panel imposes a width ceiling. An HFlowContainer's
# minimum width is its WIDEST CHILD, so wrapping can only ever happen BETWEEN chips, never inside
# one.
#
# THE REFERENCE IS THE PANEL, WHICH IS FIXED. The round-3 guard compared the row against its own
# section's live width -- one of the things that GROWS when the row is too wide -- so it passed at
# 224-in-230 while the row sat outside a 216px dock. A budget that expands to fit whatever it is
# measuring cannot fail. BackgroundPanel's rect is anchored in the .tscn and is the one width here
# that does not move.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
# The widest form the hp card can take -- see _queue_one_attack.
const WIDEST_READOUT := "999->999"

var _main: Node
var game: Node2D
var _row: ActionQueueRow
var _panel: SquadActionQueueControl


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()
	await _queue_one_attack()


func after_test() -> void:
	_row = null
	_panel = null
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()


# The widest row the panel can hold: a real attack, so the line carries both unit sprites, the verb,
# the hp readout card and the cancel X -- every fixed cost a chip has to share the line with.
func _queue_one_attack() -> void:
	var attacker: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(1, 1))
	var victim: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(2, 1))
	attacker.equipped_weapon = H.make_weapon(4)
	game.squad_manager.active_squad = attacker.squad
	game.squad_manager.queue_action(attacker.squad, H.stamped_attack(attacker, victim))
	game.refresh_action_queue(attacker.squad)
	await await_idle_frame()
	_panel = game.squad_action_queue_control
	var rows: Array[ActionQueueRow] = []
	_collect(_panel, rows)
	for r in rows:
		if r.action is AttackAction:
			_row = r
	assert_object(_row).override_failure_message("no attack row to measure against").is_not_null()
	# THE WIDEST READOUT, not the one this fixture happens to produce. A badge shares the line with
	# the hp card, so sizing badges against a 5-character "20->0" leaves ~15px of budget that a real
	# three-digit exchange takes back -- and the row then overflows on exactly the hits that are
	# worth reading. Three digits each side is the widest form `%d->%d` has.
	_row.readout.text = WIDEST_READOUT
	await await_idle_frame()

func _collect(node: Node, out: Array[ActionQueueRow]) -> void:
	if node is ActionQueueRow:
		out.append(node as ActionQueueRow)
		return
	for child in node.get_children():
		_collect(child, out)


# How far past the dock's right edge a row carrying exactly this badge would reach. Negative is
# clearance. Measured on the LIVE row, so it prices the real font at the real size against the real
# fixed contents rather than any arithmetic I might get wrong.
func _overhang(badge: String) -> float:
	for c in _row.consequence.get_children():
		_row.consequence.remove_child(c)
		c.queue_free()
	await await_idle_frame()
	_row.consequence.add_child(_row._chip(QueueStyle.ink(QueueStyle.Role.EVENT_TINT), badge, "x"))
	await await_idle_frame()
	await await_idle_frame()
	return _row.get_global_rect().end.x - _panel.background_panel.get_global_rect().end.x

# A reaction's badge is authored (`short_name`, falling back to `popup`), so a content edit can break
# the dock with no code change at all -- which is exactly what a law is for.
func test_every_reaction_badge_fits_the_dock() -> void:
	var over: Array[String] = []
	for reaction: ElementalReaction in ReactionCatalog.get_all():
		var badge := reaction.badge_name()
		if badge == "":
			continue
		var past: float = await _overhang(badge)
		if past > 0.0:
			over.append("%s (+%.0fpx)" % [badge, past])
	assert_array(over).override_failure_message(
			"these reaction badges push the row out of the dock: %s -- shorten short_name, or the row overflows the panel the way \"Into the void!\" did"
			% [over]).is_empty()


# A state chip's word is Elemental's, and it is the other authored string this row can print.
func test_every_state_chip_fits_the_dock() -> void:
	var over: Array[String] = []
	for state: Elemental.State in Elemental.State.values():
		if state == Elemental.State.NONE:
			continue
		var word := Elemental.state_display_name(state)
		var past: float = await _overhang(word)
		if past > 0.0:
			over.append("%s (+%.0fpx)" % [word, past])
	assert_array(over).override_failure_message(
			"these state chips push the row out of the dock: %s" % [over]).is_empty()


# The world-event badges -- the four this bug was reported against. Two digits on the fall, because
# a plummet down a tall stack is the widest that badge can get.
func test_every_world_event_badge_fits_the_dock() -> void:
	var badges: Array[String] = [
		ActionQueueRow.BADGE_FELL % 99,
		ActionQueueRow.BADGE_DROWNED,
		ActionQueueRow.BADGE_VOID,
		ActionQueueRow.BADGE_INSULATED,
		ActionQueueRow.BADGE_VIAL,
	]
	var over: Array[String] = []
	for badge: String in badges:
		var past: float = await _overhang(badge)
		if past > 0.0:
			over.append("%s (+%.0fpx)" % [badge, past])
	assert_array(over).override_failure_message(
			"these world-event badges push the row out of the dock: %s" % [over]).is_empty()


# The case that would have caught the report, stated as the property the dev actually reported:
# a row stays inside the dock. Falsified against the shipped bug -- with the dramatic string in the
# badge slot this reads +4px and reds.
func test_the_dramatic_wording_is_what_overflowed_and_the_badge_is_not() -> void:
	var dramatic: float = await _overhang(PlanResolver.VOID_POPUP)
	assert_float(dramatic).override_failure_message(
			"\"%s\" now FITS the row -- either the dock grew or the font shrank, and this case has stopped describing the bug it was written for"
			% PlanResolver.VOID_POPUP).is_greater(0.0)
	var badge: float = await _overhang(ActionQueueRow.BADGE_VOID)
	assert_float(badge).override_failure_message(
			"the void BADGE overhangs the dock by %.0fpx" % badge).is_less_equal(0.0)
