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

# --- CHILLED's placeholder art, and the 3D row's door (#357) -------------------------------

func test_chilled_resolves_to_art_rather_than_the_text_fallback() -> void:
	# The dev's call: the frozen-water tile stands in until a real CHILLED icon exists. It lands in
	# ICONS rather than at any one surface, so this asserts the SHARED table answered — a per-surface
	# fix would leave the other two showing a text label.
	var box: HBoxContainer = auto_free(HBoxContainer.new())
	add_child(box)

	StateIcons.populate(box, [Elemental.State.CHILLED])
	await get_tree().process_frame
	assert_int(box.get_child_count()).is_equal(1)
	assert_object(box.get_child(0)).is_instanceof(TextureRect)


func test_every_icon_is_configured_to_render_at_one_size() -> void:
	# A PROXY for "the row is uniform", asserted at the mechanism because a drawn size is not
	# observable headless. It has teeth against the revert that matters: the source art disagrees
	# (32px wet, 16px ice), so with expand/stretch left at KEEP the row shows one at half the other.
	var box: HBoxContainer = auto_free(HBoxContainer.new())
	add_child(box)

	StateIcons.populate(box, [Elemental.State.WET, Elemental.State.CHILLED])
	await get_tree().process_frame
	assert_int(box.get_child_count()).is_equal(2)
	for child in box.get_children():
		var rect := child as TextureRect
		assert_object(rect).is_not_null()
		assert_vector(rect.custom_minimum_size).is_equal(Vector2(StateIcons.ICON_SIZE))
		assert_int(rect.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
		assert_int(rect.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)


func test_textures_for_skips_none_and_keeps_the_callers_order() -> void:
	# The door the world-space row reads (#357), so UnitMirror never indexes ICONS itself.
	var textures := StateIcons.textures_for([Elemental.State.CHILLED, Elemental.State.NONE,
			Elemental.State.WET])
	assert_int(textures.size()).is_equal(2)
	assert_object(textures[0]).is_same(StateIcons.ICONS[Elemental.State.CHILLED])
	assert_object(textures[1]).is_same(StateIcons.ICONS[Elemental.State.WET])


func test_textures_for_is_empty_for_a_unit_holding_nothing() -> void:
	assert_array(StateIcons.textures_for([])).is_empty()
