# The headless enemy ranges (#46): the game's V key, through the builder game.threat_field() calls
# (ThreatField.for_viewer, pinned directly in tests/ai/test_threat_field.gd). These drive the session's
# query and the bridge's render, and read every expectation off the query's own data.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _board: Dictionary
var _session


# Both enemies HOLD with a pattern-less weapon, so each strikes its four neighbours and nothing
# further: C is out of reach by geometry, not by a tuned move range.
func before_test() -> void:
	_board = BoardBuilder.build(self)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(0, 0, 12, 12))
	_unit("P1", PLAYER, Vector2i(1, 0))    # -> A, beside a
	_unit("P2", PLAYER, Vector2i(9, 9))    # -> B, beside b
	_unit("P3", PLAYER, Vector2i(5, 5))    # -> C, beside nobody
	_unit("E1", ENEMY, Vector2i(2, 0))     # -> a
	_unit("E2", ENEMY, Vector2i(9, 10))    # -> b
	_session = PlaySession.new(_board)


func _unit(name: String, faction: Team.Faction, cell: Vector2i) -> Unit:
	var data := UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, faction)
	var unit := BoardBuilder.spawn(_board, data, cell)
	BoardBuilder.arm(unit, 4)
	unit.squad.archetype = AIArchetype.Type.HOLD
	return unit


# handle -> the handles that can hit it, off the query's own rows.
func _hitters(res: Dictionary) -> Dictionary:
	var out := {}
	for row: Dictionary in res.units:
		out[row.unit] = row.attackers
	return out


func _row(res: Dictionary, handle: String) -> Dictionary:
	for row: Dictionary in res.units:
		if row.unit == handle:
			return row
	return {}


# The overlay character the grid draws at `cell`: each cell is [actor][terrain][overlay].
func _overlay_at(text: String, cell: Vector2i) -> String:
	var bounds: Rect2i = BoardView._content_bounds(_session)
	var prefix := "y=%3d " % cell.y
	for line: String in text.split("\n"):
		if line.begins_with(prefix):
			return line.substr(prefix.length() + (cell.x - bounds.position.x) * 3 + 2, 1)
	return ""


func test_ranges_names_who_can_hit_each_unit_and_nobody_for_one_out_of_reach() -> void:
	var res: Dictionary = _session.ranges()
	assert_bool(res.ok).override_failure_message("ranges refused: %s" % str(res.get("error", ""))).is_true()
	var hitters := _hitters(res)
	var on_a: Array = hitters.get("A", [])
	var on_c: Array = hitters.get("C", ["missing"])
	assert_bool(on_a.has("a")).override_failure_message(
			"A stands beside a and the view named nobody who could hit it: %s" % str(on_a)).is_true()
	assert_int(on_c.size()).override_failure_message(
			"C is out of every enemy's reach and the view named %s" % str(on_c)).is_equal(0)
	assert_int(hitters.size()).override_failure_message(
			"the view reported a line per unit other than the three players: %s" % str(hitters.keys())).is_equal(3)


# The rows are judged where each plan leaves its unit, the board the game's field is built on.
func test_a_unit_is_judged_where_its_plan_leaves_it() -> void:
	var foes: Array[Vector2i] = [Vector2i(2, 0), Vector2i(9, 10)]
	var away := Vector2i(-99, -99)
	for cell: Vector2i in (_session.legal_moves("A").cells as Array):
		var clear := true
		for foe: Vector2i in foes:
			if absi(cell.x - foe.x) + absi(cell.y - foe.y) <= 1:
				clear = false
		if clear:
			away = cell
			break
	assert_that(away).override_failure_message(
			"fixture is vacuous: A can reach no cell clear of both enemies").is_not_equal(Vector2i(-99, -99))
	var before: Dictionary = _row(_session.ranges(), "A")
	assert_bool((before.attackers as Array).has("a")).override_failure_message(
			"fixture is vacuous: A is not in reach where it stands").is_true()

	var queued: Dictionary = _session.queue_move("A", away)
	assert_bool(queued.ok).override_failure_message("the fixture's move was refused: %s" % str(queued.get("error", ""))).is_true()
	var after: Dictionary = _row(_session.ranges(), "A")
	assert_that(after.cell).override_failure_message(
			"A's line names its live cell, not where its plan leaves it").is_equal(away)
	assert_int((after.attackers as Array).size()).override_failure_message(
			"A was judged where it stands, not where it is going: %s" % str(after.attackers)).is_equal(0)
	assert_that(_session.unit_by_handle("A").movement.cell).override_failure_message(
			"the query left A standing on its planned cell").is_equal(Vector2i(1, 0))


func test_naming_an_enemy_narrows_the_view_to_it() -> void:
	var every: Dictionary = _session.ranges()
	var only_a: Dictionary = _session.ranges("a")
	assert_bool(only_a.ok).override_failure_message("ranges a refused: %s" % str(only_a.get("error", ""))).is_true()
	var subjects: Array = only_a.subjects
	assert_bool(subjects.size() == 1 and subjects[0] == "a").override_failure_message(
			"naming a, the subjects were %s" % str(subjects)).is_true()
	assert_bool((every.subjects as Array).has("b")).override_failure_message(
			"fixture is vacuous: the unfiltered view never held b").is_true()

	var b_cell: Vector2i = _session.unit_by_handle("B").movement.cell
	assert_bool((every.reach as Array).has(b_cell)).override_failure_message(
			"fixture is vacuous: b's strike never reached B").is_true()
	assert_bool((only_a.reach as Array).has(b_cell)).override_failure_message(
			"the view of a alone still marked b's strike").is_false()
	assert_int((only_a.reach as Array).size()).is_less((every.reach as Array).size())

	var on_b: Array = _hitters(only_a).get("B", ["missing"])
	assert_int(on_b.size()).override_failure_message(
			"the view of a alone still named who else can hit B: %s" % str(on_b)).is_equal(0)
	var on_a: Array = _hitters(only_a).get("A", [])
	assert_bool(on_a.has("a")).override_failure_message("the view of a alone lost a's own hit on A").is_true()


func test_a_handle_that_is_not_a_hostile_unit_is_refused() -> void:
	var own: Dictionary = _session.ranges("A")
	assert_bool(own.ok).override_failure_message("a player unit was accepted as an enemy to range").is_false()
	var nobody: Dictionary = _session.ranges("zz")
	assert_bool(nobody.ok).override_failure_message("a handle naming no unit was accepted").is_false()


func test_the_render_carries_the_legend_and_both_glyphs_where_the_data_puts_them() -> void:
	var res: Dictionary = _session.ranges()
	var text: String = BoardView.render_ranges(_session)
	var strike := BoardView.STRIKE_GLYPH
	var stand := BoardView.STAND_GLYPH
	assert_str(text).contains("%s an enemy can strike here" % strike)
	assert_str(text).contains("%s an enemy can stand here but not strike" % stand)

	var reach: Array = res.reach
	var bounds: Rect2i = BoardView._content_bounds(_session)
	var drawn: Array[Vector2i] = []
	for cell: Vector2i in reach:
		if bounds.has_point(cell):
			drawn.append(cell)
	assert_int(drawn.size()).override_failure_message("fixture is vacuous: nobody can strike anywhere on the grid").is_greater(0)
	var strike_cell: Vector2i = drawn[0]
	assert_str(_overlay_at(text, strike_cell)).override_failure_message(
			"%s is a strike cell and the grid drew '%s'" % [str(strike_cell), _overlay_at(text, strike_cell)]).is_equal(strike)

	var stand_only: Array[Vector2i] = []
	for cell: Vector2i in (res.move as Array):
		if not reach.has(cell):
			stand_only.append(cell)
	assert_int(stand_only.size()).override_failure_message(
			"fixture is vacuous: every cell an enemy can stand on is also one it strikes").is_greater(0)
	assert_str(_overlay_at(text, stand_only[0])).override_failure_message(
			"%s is stand-only and the grid drew '%s'" % [str(stand_only[0]), _overlay_at(text, stand_only[0])]).is_equal(stand)

	var quiet := Vector2i(11, 0)
	assert_bool(reach.has(quiet) or (res.move as Array).has(quiet)).override_failure_message(
			"fixture is vacuous: the corner the grid should leave bare is marked").is_false()
	assert_str(_overlay_at(text, quiet)).is_equal(" ")

	for row: Dictionary in res.units:
		var attackers: Array = row.attackers
		var verdict: String = ("hit by " + ", ".join(attackers)) if not attackers.is_empty() else "out of reach"
		assert_str(text).contains("%s at (%d,%d): %s" % [row.unit, row.cell.x, row.cell.y, verdict])
