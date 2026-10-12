# Heat warms and never ignites (Deep Alchemy, 2026-10-12, dev + codev): no terrain reaction that sets
# a tile BURNING may answer to HEAT. That is the design rule, not a tuning value -- a new ignition
# reaction that lists heat would make free heat a cheaper fire. Ignition itself reads only the
# primary element (TerrainReactionCatalog.fuel_for_kind), so this guards the one door left open:
# an ignition reaction's also_triggered_by.
extends GdUnitTestSuite


func test_no_ignition_answers_to_heat() -> void:
	var heat: Array[Elemental.Element] = [Elemental.Element.HEAT]
	var ignitions := 0
	for r in TerrainReactionCatalog.get_all():
		if not r.add_tile_states.has(Terrain.TileState.BURNING):
			continue
		ignitions += 1
		assert_bool(r.fires_for(heat)) \
			.override_failure_message("%s sets a tile alight and answers to Heat" % r.resource_path).is_false()
	assert_int(ignitions).override_failure_message(
			"no authored reaction sets a tile alight, so this law checks nothing").is_greater(0)
