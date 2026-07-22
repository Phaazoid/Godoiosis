# Pins JobCatalog's scan cache (added after the Waterwalk hover crawl: the per-call disk
# scan measured ~5ms, and movement_cost's ability check runs per water cell in the move-range
# fill). get_jobs() must return the SAME dictionary until refresh() invalidates it — a future
# runtime job-authoring tool that forgets refresh() will trip the staleness half of this suite.
extends GdUnitTestSuite


func test_get_jobs_returns_the_cached_dictionary() -> void:
	var first := JobCatalog.get_jobs()
	var second := JobCatalog.get_jobs()
	assert_bool(is_same(first, second)).is_true()


func test_refresh_triggers_a_rescan() -> void:
	var before := JobCatalog.get_jobs()
	JobCatalog.refresh()
	var after := JobCatalog.get_jobs()
	assert_bool(is_same(before, after)).is_false()   # a fresh scan, not the stale dict
	assert_array(after.keys()).contains_same_exactly_in_any_order(before.keys())


func test_cached_lookup_resolves_authored_jobs() -> void:
	# The cache must serve the real authored roster, same objects on every lookup.
	var scout := JobCatalog.get_job("scout")
	assert_object(scout).is_not_null()
	assert_object(JobCatalog.get_job("scout")).is_same(scout)
