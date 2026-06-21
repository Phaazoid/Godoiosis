# Contract guards for the Play API core (docs/play-api.md, #46 M2).
# Locks the two laws the headless executor must honor: preview == execution (Law #2),
# and preview/look-ahead never mutates live state. Plus the player-parity gates
# (off-faction units can't be ordered; end_turn hands control over).
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _board: Dictionary
var _session

func before_test() -> void:
	_board = BoardBuilder.build(self)            # adds a PlayRoot under the suite (active tree -> _ready fires)
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(-2, -2, 12, 12))
	var p := BoardBuilder.spawn(_board, _data("P1", PLAYER), Vector2i(0, 0))   # -> handle A
	var e := BoardBuilder.spawn(_board, _data("E1", ENEMY), Vector2i(2, 0))    # -> handle a
	_arm(p, 6)
	_arm(e, 4)
	_session = PlaySession.new(_board)

func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)

func _arm(unit: Unit, power: int) -> void:
	var w := WeaponData.new()
	w.power = power
	w.scaling_stat = Stats.Stat.STR
	unit.add_item(w)

# Law #2: the HP the preview promises is exactly what execution leaves behind.
func test_preview_equals_execution() -> void:
	_session.queue_move("A", Vector2i(1, 0))
	_session.queue_attack("A", Vector2i(2, 0))
	var prev: Dictionary = _session.preview()
	assert_bool(prev.ok).is_true()
	var atk: Dictionary = prev.plan.attacks[0]
	assert_int(atk.dmg).is_greater(0)

	var target: Unit = _session.unit_by_handle("a")
	var res: Dictionary = _session.execute()
	assert_bool(res.ok).is_true()
	assert_int(target.get_current_hp()).is_equal(atk.hp_after)

# Look-ahead is pure: previewing (even twice) changes no live HP or position.
func test_preview_does_not_mutate_live_state() -> void:
	var target: Unit = _session.unit_by_handle("a")
	var attacker: Unit = _session.unit_by_handle("A")
	var hp_before: int = target.get_current_hp()
	var cell_before: Vector2i = attacker.movement.cell
	_session.queue_move("A", Vector2i(1, 0))
	_session.queue_attack("A", Vector2i(2, 0))
	_session.preview()
	_session.preview()
	assert_int(target.get_current_hp()).is_equal(hp_before)
	assert_bool(attacker.movement.cell == cell_before).is_true()

# Player parity (Law #3 spirit): you cannot order an off-faction unit.
func test_cannot_order_off_faction_unit() -> void:
	var res: Dictionary = _session.queue_move("a", Vector2i(2, 1))   # 'a' is ENEMY on the PLAYER turn
	assert_bool(res.ok).is_false()

# end_turn hands the active faction over, enabling the other side.
func test_end_turn_hands_over_control() -> void:
	assert_int(_session.active_faction()).is_equal(PLAYER)
	_session.end_turn()
	assert_int(_session.active_faction()).is_equal(ENEMY)
	var res: Dictionary = _session.queue_move("a", Vector2i(2, 1))
	assert_bool(res.ok).is_true()

# The headless scenario loader: an in-memory ScenarioData round-trips onto a fresh board
# (file-independent, so it survives scenario renames).
func test_apply_scenario_restores_units_terrain_and_turn() -> void:
	var src: Dictionary = BoardBuilder.build(self, "SrcRoot")
	auto_free(src.root)
	BoardBuilder.paint_rect(src.grid, Rect2i(0, 0, 5, 5))
	var scenario := ScenarioData.new()
	scenario.tile_data = src.grid.tile_map_data
	scenario.active_faction = ENEMY
	scenario.turn_phase = TurnManager.TurnPhase.ENEMY
	var entry := ScenarioUnitEntry.new()
	entry.unit_data = _data("Loaded", PLAYER)
	entry.cell = Vector2i(2, 3)
	scenario.unit_entries.append(entry)

	var dst: Dictionary = BoardBuilder.build(self, "DstRoot")
	auto_free(dst.root)
	var spawned: Array = await BoardBuilder.apply_scenario(dst, scenario)

	assert_int(spawned.size()).is_equal(1)
	var u: Unit = spawned[0]
	assert_bool(u.movement.cell == Vector2i(2, 3)).is_true()
	var sess = PlaySession.new(dst)
	assert_bool(sess.terrain_at(Vector2i(2, 3)).exists).is_true()
	assert_int(sess.active_faction()).is_equal(ENEMY)
