# Contract guards for the Play API core (docs/play-api.md, #46 M2).
# Locks the two laws the headless executor must honor: preview == execution (Law #2),
# and preview/look-ahead never mutates live state. Plus the player-parity gates
# (off-faction units can't be ordered; end_turn hands control over).
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

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

# #33 lifecycle: a would-be-fatal hit UNDER the overkill ceiling DOWNS (not kills) — preview
# must say DOWNED and execution must leave the target alive at 1 HP, with its counter skipped.
# This is the exact gap the view layer had: it read hp<=0 as "DIES".
func test_sub_ceiling_lethal_hit_downs_and_skips_counter() -> void:
	var target: Unit = _session.unit_by_handle("a")
	target.take_damage(target.get_current_hp() - 5)   # whittle to 5 HP (survivable -> stays ACTIVE)
	assert_int(target.get_current_hp()).is_equal(5)
	assert_bool(target.is_active()).is_true()

	_session.queue_move("A", Vector2i(1, 0))           # adjacent to 'a' at (2,0)
	_session.queue_attack("A", Vector2i(2, 0))         # 11 dmg vs 5 HP: overkill 6 <= ceiling -> DOWN
	var prev: Dictionary = _session.preview()
	assert_bool(prev.ok).is_true()
	assert_int(prev.plan.attacks[0].lethality).is_equal(ResolvedOutcome.Lethality.DOWNED)
	assert_int(prev.plan.counters.size()).is_greater(0)
	assert_bool(prev.plan.counters[0].skipped).is_true()   # a downed target can't strike back

	# the rendered view must say DOWNED (not "DIES") and label the skipped counter, not show junk
	var pv: String = BoardView.render_preview(_session)
	assert_str(pv).contains("DOWNED")
	assert_str(pv).contains("none (")

	var attacker: Unit = _session.unit_by_handle("A")
	var attacker_hp: int = attacker.get_current_hp()
	var res: Dictionary = _session.execute()
	assert_bool(res.ok).is_true()
	assert_bool(target.is_downed()).is_true()              # NOT dead
	assert_int(target.get_current_hp()).is_equal(1)        # clings at 1 HP
	assert_int(attacker.get_current_hp()).is_equal(attacker_hp)   # counter was skipped — no reprisal
	assert_str(BoardView.render_overview(_session)).contains("[DOWNED]")   # legend flags the body

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

# #33 rescue loop: a unit picks up an ADJACENT DOWNED ally (a main action). After execute the
# ally is ACTIVE again at 1 HP — the other half of the down/rescue cycle the bridge now exposes.
func test_rescue_revives_adjacent_downed_ally() -> void:
	var b: Dictionary = BoardBuilder.build(self, "RescueRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 0))
	_arm(hero, 3)
	var sess = PlaySession.new(b)
	ally.take_damage(ally.get_current_hp())   # damage == HP: overkill 0 <= ceiling -> DOWNED at 1 hp
	assert_bool(ally.is_downed()).is_true()
	sess._process_downed_pending()            # eject to solo, as a prior turn's post-pass would
	var hero_h: String = sess.handle_for(hero)
	var ally_h: String = sess.handle_for(ally)

	var res: Dictionary = sess.rescue(hero_h, ally_h)
	assert_bool(res.ok).is_true()
	var exe: Dictionary = sess.execute()
	assert_bool(exe.ok).is_true()
	assert_bool(ally.is_active()).is_true()
	assert_int(ally.get_current_hp()).is_equal(1)

# Rescue rejects a healthy (non-downed) target — only bodies get picked up.
func test_rescue_rejects_a_healthy_target() -> void:
	var b: Dictionary = BoardBuilder.build(self, "RescueRoot2")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 0))
	var sess = PlaySession.new(b)
	var res: Dictionary = sess.rescue(sess.handle_for(hero), sess.handle_for(ally))
	assert_bool(res.ok).is_false()

# Squad management through the same SquadManager the player uses: join, then leave.
func test_join_and_leave_squad() -> void:
	var b: Dictionary = BoardBuilder.build(self, "SquadRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 8, 8))
	var lead: Unit = BoardBuilder.spawn(b, _data("Lead", PLAYER), Vector2i(0, 0))
	var mate: Unit = BoardBuilder.spawn(b, _data("Mate", PLAYER), Vector2i(1, 0))
	var sess = PlaySession.new(b)
	var lead_h: String = sess.handle_for(lead)
	var mate_h: String = sess.handle_for(mate)

	var joined: Dictionary = sess.join(mate_h, lead_h)
	assert_bool(joined.ok).is_true()
	assert_object(mate.squad).is_same(lead.squad)
	assert_bool(mate.has_squad()).is_true()

	var left: Dictionary = sess.leave(mate_h)
	assert_bool(left.ok).is_true()
	assert_bool(mate.has_squad()).is_false()
