# The AI profile catalog (#1230): a unit names its profile by file, an unassigned one plays Hard, and
# test fixtures come first. Asserts IDENTITY against the catalog's own resources, never a knob's
# value -- the bands are tuned content.
extends GdUnitTestSuite


func before_test() -> void:
	AIProfiles.use_fixtures({})   # this suite reads the shipped catalog, by identity only


func after_test() -> void:
	AIProfiles.clear_fixtures()


# A bare Unit is enough: AIProfiles.of reads the name and nothing else.
func _unit(profile_name: String) -> Unit:
	var unit: Unit = auto_free(Unit.new())
	unit.ai_profile = profile_name
	return unit


func test_every_band_resolves_by_name() -> void:
	for band: String in AIProfiles.BANDS:
		assert_object(AIProfiles.resolve(band)).override_failure_message(
			"band '%s' has no file in %s" % [band, AIProfiles.PROFILE_DIR]).is_not_null()


func test_an_unassigned_unit_plays_the_hard_band() -> void:
	assert_object(AIProfiles.of(_unit(""))).is_same(AIProfiles.resolve(AIProfiles.DEFAULT_NAME))


func test_a_named_unit_plays_its_own_profile() -> void:
	assert_object(AIProfiles.of(_unit("Easy"))).is_same(AIProfiles.resolve("Easy"))
	assert_object(AIProfiles.of(_unit("Easy"))).is_not_same(AIProfiles.of(_unit("")))


func test_a_name_that_resolves_to_nothing_plays_hard() -> void:
	assert_object(AIProfiles.resolve("NoSuchProfileEverExisted")).is_null()
	assert_object(AIProfiles.of(_unit("NoSuchProfileEverExisted"))) \
		.is_same(AIProfiles.resolve(AIProfiles.DEFAULT_NAME))


func test_the_bands_are_listed_first_and_in_order() -> void:
	var names := AIProfiles.names()
	assert_int(names.size()).is_greater_equal(AIProfiles.BANDS.size())
	for i in AIProfiles.BANDS.size():
		assert_str(names[i]).is_equal(AIProfiles.BANDS[i])


func test_a_fixture_outranks_the_disk_and_sets_what_unassigned_plays() -> void:
	var stand_in := AIProfile.new()
	var named := AIProfile.new()
	AIProfiles.use_fixtures({"": stand_in, "Easy": named})
	assert_object(AIProfiles.of(_unit(""))).is_same(stand_in)
	assert_object(AIProfiles.of(_unit("Easy"))).is_same(named)
	AIProfiles.clear_fixtures()
	assert_object(AIProfiles.of(_unit(""))).is_same(AIProfiles.resolve(AIProfiles.DEFAULT_NAME))
