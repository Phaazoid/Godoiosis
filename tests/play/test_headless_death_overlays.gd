# A unit's death clears its planning overlays on every host (#46). The game cleared them at its own
# two callers and the headless host never did, so a unit that died with a group-move ghost up left a
# FREED key in OverlayManager.projected_unit_sprites -- and every later redraw (the next AI group move)
# threw a SCRIPT ERROR on it. Found by all five playtesters of the 2026-10-05 demo sweep.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const PLAYER := Team.Faction.PLAYER


func _data(unit_name: String) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, PLAYER)


# A leader and a member with a group move queued, so each wears a planned path and a ghost.
func _moved_squad() -> Dictionary:
	var b := BoardBuilder.build(self, "DeathOverlaysRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	var leader: Unit = BoardBuilder.spawn(b, _data("Leader"), Vector2i(0, 0))
	var member: Unit = BoardBuilder.spawn(b, _data("Member"), Vector2i(1, 0))
	var sm: SquadManager = b.squad_manager
	sm.join_squad(member, leader.squad)
	var sess = PlaySession.new(b)
	var moved: Dictionary = sess.group_move(sess.handle_for(leader), Vector2i(0, 2))
	assert_bool(moved.ok).override_failure_message("fixture: the group move did not queue: %s" % str(moved.get("error", ""))).is_true()
	var overlays: OverlayManager = sm.overlay_manager
	assert_bool(overlays.projected_unit_sprites.has(member)).override_failure_message(
			"fixture: the member wears no ghost, so its death has nothing to clear").is_true()
	return {"overlays": overlays, "member": member, "session": sess}   # held: a dropped session is freed and hears no death


func test_a_headless_death_takes_the_units_ghost_and_path_with_it() -> void:
	var f := _moved_squad()
	var overlays: OverlayManager = f.overlays
	var member: Unit = f.member

	member.take_damage(member.get_current_hp() + 999)

	assert_bool(overlays.projected_unit_sprites.has(member)).override_failure_message(
			"the dead unit's ghost stayed in projected_unit_sprites").is_false()
	assert_bool(overlays.planned_move_by_unit.has(member)).override_failure_message(
			"the dead unit's planned path stayed in planned_move_by_unit").is_false()


# The other half: a ghost whose unit is freed by a path that never told the overlays still goes
# quietly on the next redraw, instead of throwing on the freed key.
func test_a_ghost_whose_unit_was_freed_drops_on_the_next_redraw() -> void:
	var f := _moved_squad()
	var overlays: OverlayManager = f.overlays
	var member: Unit = f.member
	member.get_parent().remove_child(member)
	member.free()

	overlays.redraw_projected_units()

	assert_int(overlays.projected_unit_sprites.size()).override_failure_message(
			"a ghost keyed by a freed unit survived the redraw").is_less_equal(1)
	for key: Variant in overlays.projected_unit_sprites.keys():
		assert_bool(is_instance_valid(key)).override_failure_message(
				"projected_unit_sprites still holds a freed key").is_true()
