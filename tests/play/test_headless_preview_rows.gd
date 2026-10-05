# The Play API's preview says what the game's queue panel says (#46). It was a hand-built list that
# left out every watch shot, the END OF TURN burn and what the pass leaves on the ground, so a driver
# planning a crossing could not see the threat that ended its turn. Its rows are now
# ActionQueueDisplayEntry.build_for's, and its terrain is ResolvedPlan.pending_deposits, which the
# board ghosts.
#
# Expectations are read off the plan and the seams that rule it, never numbers chosen here.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")

const BoardBuilder := preload("res://play/board_builder.gd")
const BoardView := preload("res://play/board_view.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


# A melee weapon whose one attack can also stand watch.
func _watch_weapon() -> WeaponInstance:
	var swing := WeaponAttackData.new()
	swing.display_name = "Swing"
	swing.power = 4
	swing.can_overwatch = true
	P.point(swing, 1, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = swing
	return WeaponInstance.make(t)


func _sturdy(unit: Unit) -> void:
	unit.unit_instance.stats[Stats.Stat.MHP] = 200
	unit.set_current_hp(200)


func _board(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	return b


# The rows ARE build_for's ACTION entries, one for one and in its order.
func _assert_rows_match_the_panel(sess, rows: Array) -> void:
	var squad: Squad = sess.squad_manager.active_squad
	var plan: ResolvedPlan = sess.squad_manager.resolve_plan(squad, sess._board())
	var panel: Array[BaseAction] = []
	for entry in ActionQueueDisplayEntry.build_for(squad, plan):
		if entry.entry_type == ActionQueueDisplayEntry.EntryType.ACTION:
			panel.append(entry.action)
	assert_int(rows.size()).override_failure_message("the preview has %d rows where the panel has %d:\n%s"
			% [rows.size(), panel.size(), str(rows)]).is_equal(panel.size())
	for i in mini(rows.size(), panel.size()):
		var row: Dictionary = rows[i]
		assert_str(str(row.type)).is_equal(panel[i].get_action_name())
		assert_str(str(row.actor)).is_equal(sess.handle_for(panel[i].actor))


func _row_where(rows: Array, keys: Dictionary) -> Dictionary:
	for row: Dictionary in rows:
		var hit := true
		for key in keys:
			if not row.has(key) or row[key] != keys[key]:
				hit = false
				break
		if hit:
			return row
	return {}


# A walk across a watch the enemy stands, into fire: the shot hangs under the walk that drew it and
# the burn closes the plan, as on the panel. The board is a one-wide corridor, because a move routes
# around a watch it can (#920): the crossing has to be the only way through.
func test_a_crossing_shows_its_watch_shot_and_its_end_of_turn_burn() -> void:
	var b := BoardBuilder.build(self, "CrossingPreviewRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(0, 0, 4, 1))
	BoardBuilder.paint_cell(b.grid, Vector2i(1, 1), BoardBuilder.GRASS_ATLAS)   # where the watcher stands
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var watcher: Unit = BoardBuilder.spawn(b, _data("Watcher", ENEMY), Vector2i(1, 1))
	watcher.add_item(_watch_weapon())
	_sturdy(hero)
	var watched: Array[Vector2i] = [Vector2i(1, 0)]
	watcher.arm_watch(watcher.movement.cell, watched[0], watched,
			(watcher.get_equipped_weapon() as WeaponInstance).template.main_attack)
	var fire := ResolvedCellEffect.new()
	fire.cell = Vector2i(2, 0)
	fire.states_added.assign([Terrain.TileState.BURNING])
	(b.terrain_states as TerrainStateManager).apply(fire)
	var sess = PlaySession.new(b)
	var h: String = sess.handle_for(hero)
	var w: String = sess.handle_for(watcher)
	assert_bool(sess.queue_move(h, Vector2i(2, 0)).ok).override_failure_message(
			"fixture: the walk into the fire was refused").is_true()

	var res: Dictionary = sess.preview()
	assert_bool(res.ok).override_failure_message("preview refused: %s" % str(res)).is_true()
	var rows: Array = res.plan.rows
	_assert_rows_match_the_panel(sess, rows)
	assert_bool(_row_where(rows, {"section": "MOVE", "depth": 1, "actor": w, "target": h}).is_empty()) \
		.override_failure_message("the watch shot is not under the walk that drew it:\n%s" % str(rows)).is_false()
	assert_bool(_row_where(rows, {"section": "END OF TURN", "actor": h}).is_empty()) \
		.override_failure_message("the end-of-turn burn is missing:\n%s" % str(rows)).is_false()

	var text: String = BoardView.render_preview(sess)
	assert_str(text).contains("%s -> %s (Swing)" % [w, h])
	assert_str(text).contains("END OF TURN")


# An Overwatch armed over somebody fires at once (#1003); its shot hangs under the order.
func test_a_watch_armed_over_an_enemy_shows_the_shot_it_fires() -> void:
	var b := _board("ArmShotPreviewRoot")
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	hero.add_item(_watch_weapon())
	_sturdy(hero)
	_sturdy(foe)
	var sess = PlaySession.new(b)
	var h: String = sess.handle_for(hero)
	var f: String = sess.handle_for(foe)
	assert_bool(sess.overwatch(h, foe.movement.cell).ok).override_failure_message(
			"fixture: the watch was refused").is_true()

	var res: Dictionary = sess.preview()
	assert_bool(res.ok).is_true()
	var rows: Array = res.plan.rows
	_assert_rows_match_the_panel(sess, rows)
	assert_bool(_row_where(rows, {"section": "OVERWATCH", "depth": 1, "actor": h, "target": f}).is_empty()) \
		.override_failure_message("the arm-time shot is missing:\n%s" % str(rows)).is_false()


# A heal reads as what it gives back, the way the panel's readout does.
func test_a_heal_row_reads_the_hp_it_restores() -> void:
	var b := _board("HealPreviewRoot")
	var medic: Unit = BoardBuilder.spawn(b, _data("Medic", PLAYER), Vector2i(0, 0))
	var hurt: Unit = BoardBuilder.spawn(b, _data("Hurt", PLAYER), Vector2i(1, 0))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(5, 5))
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 6
	template.main_attack.heals = true
	template.main_attack.hits_allies = true
	medic.add_item(WeaponInstance.make(template))
	hurt.set_current_hp(hurt.get_max_hp() - 2)
	var sess = PlaySession.new(b)
	assert_bool(sess.queue_attack(sess.handle_for(medic), hurt.movement.cell).ok).is_true()

	var res: Dictionary = sess.preview()
	var row := _row_where(res.plan.rows, {"section": "ATTACK", "target": sess.handle_for(hurt)})
	assert_bool(row.is_empty()).override_failure_message("no heal row: %s" % str(res.plan.rows)).is_false()
	assert_int(int(row.get("healed", -1))).is_equal(2)
	assert_str(BoardView.render_preview(sess)).contains("+2 hp")


# What the pass leaves on the ground prints as the board ghosts it: a Burrow's cover here, through
# the same deposit list a freeze or a fire would ride.
func test_the_preview_prints_what_the_pass_leaves_on_the_ground() -> void:
	var b := _board("DepositPreviewRoot")
	var digger: Unit = BoardBuilder.spawn(b, _data("Digger", PLAYER), Vector2i(1, 1))
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.DRILL
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = 3
	digger.add_item(WeaponInstance.make(t))
	var sess = PlaySession.new(b)
	assert_bool(sess.burrow(sess.handle_for(digger)).ok).is_true()

	var res: Dictionary = sess.preview()
	var cover := Terrain.tile_state_display_name(Terrain.TileState.COVER)
	var found := false
	for deposit: Dictionary in res.plan.terrain:
		if deposit.cell == digger.movement.cell and deposit.what == cover:
			found = true
	assert_bool(found).override_failure_message("the cover is not in the preview's terrain: %s"
			% str(res.plan.terrain)).is_true()
	assert_str(BoardView.render_preview(sess)).contains("%s becomes %s" % [str(digger.movement.cell), cover])
