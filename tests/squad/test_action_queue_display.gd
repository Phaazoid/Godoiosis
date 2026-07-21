# Queue-panel section guard (action-registry refactor, 2026-07-20): the display buckets in
# get_display_entries_for_squad iterate BaseAction.SIDE_CHANNEL_ORDER, so every queued
# side-channel action MUST surface as a section (header = enum name) in registry order —
# regardless of queue insertion order. Before the registry, a type missed here rendered
# nowhere in the queue panel, silently.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER

func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)

func test_side_channel_sections_follow_registry_order() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(board, _data("Hero", PLAYER), Vector2i(0, 0))
	var mate: Unit = BoardBuilder.spawn(board, _data("Mate", PLAYER), Vector2i(0, 1))
	var ally: Unit = BoardBuilder.spawn(board, _data("Ally", PLAYER), Vector2i(1, 0))
	var manager: SquadManager = board.squad_manager
	manager.join_squad(mate, hero.squad)

	ally.take_damage(ally.get_current_hp())   # overkill 0 <= ceiling -> DOWNED, rescuable
	assert_bool(ally.is_downed()).is_true()
	mate.unit_instance.set_current_will(1)    # room to restore -> can_rally holds

	# Queue RALLY first, RESCUE second: section order must come from SIDE_CHANNEL_ORDER
	# (RESCUE before RALLY), not from queue insertion order.
	var rally := RallyAction.new()
	rally.init(mate)
	assert_bool(manager.queue_action(hero.squad, rally)).is_true()
	var rescue := RescueAction.new()
	rescue.init(hero, ally)
	assert_bool(manager.queue_action(hero.squad, rescue)).is_true()

	var context := BoardContext.new(board.grid, [hero, mate, ally], manager)
	var entries: Array[ActionQueueDisplayEntry] = manager.get_display_entries_for_squad(hero.squad, context)

	var headers: Array[String] = []
	var rows: Array = []
	for entry in entries:
		if entry.entry_type == ActionQueueDisplayEntry.EntryType.HEADER:
			headers.append(entry.label)
		elif entry.entry_type == ActionQueueDisplayEntry.EntryType.ACTION:
			rows.append(entry.action)

	assert_array(headers).contains_exactly(["RESCUE", "RALLY"])
	assert_int(rows.size()).is_equal(2)
	assert_object(rows[0]).is_same(rescue)
	assert_object(rows[1]).is_same(rally)
