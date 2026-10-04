# Queue-panel section guard (action-registry refactor, 2026-07-20): the display buckets in
# ActionQueueDisplayEntry.build_for iterate BaseAction.SIDE_CHANNEL_ORDER, so every queued
# side-channel action MUST surface as a section (header = enum name) in registry order —
# regardless of queue insertion order. Before the registry, a type missed here rendered
# nowhere in the queue panel, silently.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const H := preload("res://tests/support/squad_fixtures.gd")

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
	mate.equipped_weapon = H.make_weapon()   # a chainsword in hand -> can_rev_weapon holds

	# Queue REV first, RESCUE second: section order must come from SIDE_CHANNEL_ORDER
	# (RESCUE before REV), not from queue insertion order.
	var rev := RevAction.new()
	rev.init(mate)
	assert_bool(manager.queue_action(hero.squad, rev)).is_true()
	var rescue := RescueAction.new()
	rescue.init(hero, ally, ally.movement.cell)   # dry ground: the landing IS its own cell (#116)
	assert_bool(manager.queue_action(hero.squad, rescue)).is_true()

	var context := BoardContext.new(board.grid, [hero, mate, ally], manager)
	var plan: ResolvedPlan = manager.resolve_plan(hero.squad, context)
	var entries: Array[ActionQueueDisplayEntry] = ActionQueueDisplayEntry.build_for(hero.squad, plan)

	# The hold-position fillers the squad grows when its plan opens (#46) are a MOVE section of their
	# own; this case is about the side channel, so they are read past.
	var headers: Array[String] = []
	var rows: Array = []
	for entry in entries:
		if entry.entry_type == ActionQueueDisplayEntry.EntryType.HEADER:
			if entry.label != "MOVE":
				headers.append(entry.label)
		elif entry.entry_type == ActionQueueDisplayEntry.EntryType.ACTION:
			if not H.given_orders(hero.squad).has(entry.action):
				continue
			rows.append(entry.action)

	assert_array(headers).contains_exactly(["RESCUE", "REV"])
	assert_int(rows.size()).is_equal(2)
	assert_object(rows[0]).is_same(rescue)
	assert_object(rows[1]).is_same(rev)
