# StateIcons is the single shared builder behind every "held elemental states" surface
# (the inspect bottom bar + the hover card) — #6. These pin its contract so the two
# surfaces can never drift: one 16x16 icon per non-NONE state, NONE skipped, prior
# contents cleared each call.
#
# populate() uses queue_free() (deferred), so a re-populate's OLD children survive until
# the next idle frame — hence the `await get_tree().process_frame` before each count.
extends GdUnitTestSuite

func test_populate_adds_one_icon_per_held_state() -> void:
	var box: HBoxContainer = auto_free(HBoxContainer.new())
	add_child(box)

	StateIcons.populate(box, [Elemental.State.WET])
	await get_tree().process_frame
	assert_int(box.get_child_count()).is_equal(1)

func test_populate_skips_none() -> void:
	var box: HBoxContainer = auto_free(HBoxContainer.new())
	add_child(box)

	StateIcons.populate(box, [Elemental.State.NONE])
	await get_tree().process_frame
	assert_int(box.get_child_count()).is_equal(0)

func test_populate_clears_prior_contents() -> void:
	var box: HBoxContainer = auto_free(HBoxContainer.new())
	add_child(box)

	StateIcons.populate(box, [Elemental.State.WET])
	await get_tree().process_frame
	assert_int(box.get_child_count()).is_equal(1)

	# A second call with no states must leave the container empty, not stacked.
	StateIcons.populate(box, [])
	await get_tree().process_frame
	assert_int(box.get_child_count()).is_equal(0)
