# A gas whose state is HELD only while a unit stands in it (#1335, GasRules.while_standing -- smoke
# blinds whoever is in the cloud) is stored on nobody, so it is read only where something asks where a
# unit stands: the leash (SquadCohesion.reach_at) and the world-space status row. Everything else
# reads a unit's stats with no board at all.
#
# So such a state may carry only a COH change -- any other stat would be a value nothing reads, a dead
# knob -- and it never grows an END OF TURN row, since there is nothing for the unit to keep.
extends GdUnitTestSuite


func _standing_kinds() -> Array[Gas.Kind]:
	var kinds: Array[Gas.Kind] = []
	for kind: Gas.Kind in Gas.Kind.values():
		var rules := GasRules.for_kind(kind)
		if rules != null and rules.while_standing and rules.state != Elemental.State.NONE:
			kinds.append(kind)
	return kinds


func test_a_state_held_while_standing_changes_only_cohesion() -> void:
	var kinds := _standing_kinds()
	assert_bool(kinds.is_empty()).override_failure_message(
			"no gas is held while standing, so nothing here is checked").is_false()
	var unread: Array[String] = []
	for kind in kinds:
		var state := GasRules.for_kind(kind).state
		for stat: Stats.Stat in Elemental.paired_stat_mods(state):
			if stat != Stats.Stat.COH:
				unread.append("%s's %s changes %s" % [Gas.display_name(kind),
						Elemental.state_display_name(state), Stats.Stat.keys()[stat]])
	assert_array(unread).override_failure_message(
			"only the leash reads a state held while standing: %s" % [unread]).is_empty()


func test_a_gas_held_while_standing_grows_no_end_of_turn_row() -> void:
	var held: Array[Elemental.State] = []
	for kind in _standing_kinds():
		var hits := TileHitAction.gas_hits(null, held, Gas.with_level(0, kind, Gas.Level.THICK))
		assert_array(hits).override_failure_message(
				"thick %s grew an END OF TURN row for a state it gives only while standing" % Gas.display_name(kind)
				).is_empty()
