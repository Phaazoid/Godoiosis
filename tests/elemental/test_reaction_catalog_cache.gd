# The reaction catalogs CACHE their folder scan (#1213), JobCatalog's shape. A cache has no behaviour a
# case can see except how often the folder is READ, so the `scans` counter is what these pin -- without
# it the no-cache mutant passes every behavioural case in the tree.
extends GdUnitTestSuite


func before_test() -> void:
	ReactionCatalog.refresh()
	TerrainReactionCatalog.refresh()


func test_two_reads_scan_each_folder_once() -> void:
	var elemental := ReactionCatalog.scans
	var terrain := TerrainReactionCatalog.scans
	var _a := ReactionCatalog.get_all()
	var _b := ReactionCatalog.get_all()
	var _c := TerrainReactionCatalog.get_all()
	var _d := TerrainReactionCatalog.get_all()
	assert_int(ReactionCatalog.scans - elemental).override_failure_message(
			"the elemental folder was read on every call").is_equal(1)
	assert_int(TerrainReactionCatalog.scans - terrain).override_failure_message(
			"the terrain folder was read on every call").is_equal(1)


func test_refresh_makes_the_next_read_scan_again() -> void:
	var _a := ReactionCatalog.get_all()
	var _b := TerrainReactionCatalog.get_all()
	var elemental := ReactionCatalog.scans
	var terrain := TerrainReactionCatalog.scans
	ReactionCatalog.refresh()
	TerrainReactionCatalog.refresh()
	var _c := ReactionCatalog.get_all()
	var _d := TerrainReactionCatalog.get_all()
	assert_int(ReactionCatalog.scans).override_failure_message(
			"a refreshed elemental catalog answered from its stale list").is_equal(elemental + 1)
	assert_int(TerrainReactionCatalog.scans).override_failure_message(
			"a refreshed terrain catalog answered from its stale list").is_equal(terrain + 1)


# The cache is shared by every resolve in the game, so a caller may append to the list it was handed
# without changing anybody else's.
func test_a_caller_appending_to_its_list_changes_nobody_elses() -> void:
	var mine := ReactionCatalog.get_all()
	var count := mine.size()
	assert_int(count).override_failure_message("fixture is vacuous: no elemental reaction is authored").is_greater(0)
	mine.append(ElementalReaction.new())
	assert_int(ReactionCatalog.get_all().size()).override_failure_message(
			"appending to one caller's list grew the elemental cache").is_equal(count)

	var ours := TerrainReactionCatalog.get_all()
	var ground := ours.size()
	assert_int(ground).override_failure_message("fixture is vacuous: no terrain reaction is authored").is_greater(0)
	ours.append(TerrainReaction.new())
	assert_int(TerrainReactionCatalog.get_all().size()).override_failure_message(
			"appending to one caller's list grew the terrain cache").is_equal(ground)
