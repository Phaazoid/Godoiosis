# The #325 marker-hue deal: lazy (solo churn never touches the palette), distinct while the
# palette has room, and a dead squad frees its hue. Properties of the MECHANISM only -- no case
# here pins what any hue IS (the palettes are dev-editable consts, the tuning razor applies).
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY


func _data(name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, fac)


func _pair(board: Dictionary, fac: Team.Faction, at: Vector2i, tag: String) -> Squad:
	var leader: Unit = BoardBuilder.spawn(board, _data("L" + tag, fac), at)
	var mate: Unit = BoardBuilder.spawn(board, _data("M" + tag, fac), at + Vector2i(1, 0))
	var manager: SquadManager = board.squad_manager
	manager.join_squad(mate, leader.squad)
	return leader.squad


func test_hues_deal_lazily_and_concurrent_squads_stay_distinct() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(0, 0, 12, 12))

	# A solo squad is never dealt a hue -- the palette belongs to real squads.
	var solo: Unit = BoardBuilder.spawn(board, _data("Solo", PLAYER), Vector2i(10, 10))
	assert_that(solo.squad.ring_hue).is_equal(Color.WHITE)

	var first := _pair(board, PLAYER, Vector2i(0, 0), "a")
	var second := _pair(board, PLAYER, Vector2i(0, 2), "b")
	var hostile := _pair(board, ENEMY, Vector2i(0, 4), "c")

	assert_bool(OverlayManager.SQUAD_HUES_FRIENDLY.has(first.ring_hue)).is_true()
	assert_bool(OverlayManager.SQUAD_HUES_FRIENDLY.has(second.ring_hue)).is_true()
	assert_that(first.ring_hue).is_not_equal(second.ring_hue)
	# Factions draw from their own palettes -- "whose side" survives any squad count.
	assert_bool(OverlayManager.SQUAD_HUES_ENEMY.has(hostile.ring_hue)).is_true()


func test_a_dead_squads_hue_frees_for_the_next_squad() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(0, 0, 16, 16))

	# Wear the whole friendly palette out.
	var manager: SquadManager = board.squad_manager
	var worn: Array[Squad] = []
	for i in OverlayManager.SQUAD_HUES_FRIENDLY.size():
		worn.append(_pair(board, PLAYER, Vector2i(0, i * 2), str(i)))
	var hues: Array = []
	for squad in worn:
		assert_bool(hues.has(squad.ring_hue)).override_failure_message(
				"a hue repeated while the palette still had room").is_false()
		hues.append(squad.ring_hue)

	# Disband one: its hue leaves the worn set, so the NEXT squad gets it rather than a repeat.
	var freed: Color = worn[2].ring_hue
	manager.disband_squad(worn[2])
	var next := _pair(board, PLAYER, Vector2i(10, 14), "next")
	assert_that(next.ring_hue).override_failure_message(
			"the freed hue was not re-dealt -- a dead squad still reserves its colour").is_equal(freed)
