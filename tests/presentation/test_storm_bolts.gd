# A storm's bolt never lands on the board (#1260, dev 2026-10-08): a bolt on a tile reads as an attack
# in a game where shock is a rule. Asked of the plan and of the shape it is redrawn in each frame, over
# many strikes, at the smallest distance the Weather page allows -- where a wandering kink is most
# likely to cross the edge.
extends GdUnitTestSuite

const RECT := Rect2i(0, 0, 12, 9)


func _assert_outside(line: PackedVector3Array, rect: Rect2i, what: String) -> void:
	for point in line:
		var inside := point.x > rect.position.x and point.x < rect.end.x \
				and point.z > rect.position.y and point.z < rect.end.y
		assert_bool(inside).override_failure_message("%s passes over the board at %s" % [what, point]).is_false()


func test_no_planned_strike_ever_crosses_the_board() -> void:
	for key in 300:
		var plan := StormBolts.plan_strike(RECT, key, 1.0, 30.0, 0.0, -60.0)
		_assert_outside(plan["path"], RECT, "strike %d" % key)


func test_the_redrawn_bolt_stays_off_the_board_too() -> void:
	for key in 60:
		var plan := StormBolts.plan_strike(RECT, key, 1.0, 30.0, 0.0, -60.0)
		var path: PackedVector3Array = plan["path"]
		for roll in 5:
			var redrawn := StormBolts.keep_outside(ArcLightning.jagged(path, hash([key, roll]),
					path.size() - 1, ArcLightning.bolt_jag * 0.15), RECT)
			_assert_outside(redrawn, RECT, "strike %d's re-roll %d" % [key, roll])


# A bolt straight through the middle comes out on the edge, and one already outside is left alone.
func test_keep_outside_pushes_in_and_leaves_out() -> void:
	var through := PackedVector3Array([Vector3(6.0, 10.0, 4.5), Vector3(-5.0, 0.0, 4.0)])
	var kept := StormBolts.keep_outside(through, RECT)
	_assert_outside(kept, RECT, "the pushed line")
	assert_vector(kept[1]).is_equal(through[1])
