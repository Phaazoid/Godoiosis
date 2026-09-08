# Shared dialog teardown for suites that boot missions through the fresh-start door (#182).
# Missions can TALK now: begin_mission arms the scenario's beats, a MISSION_START intro spawns
# Dialogic's layout ON THE TREE ROOT -- outside any suite fixture, so it survives scene removal,
# eats synthesized clicks, and bleeds into the next case as orphans unless ended explicitly.
#
# #687 DID NOT MOVE IT FOR TESTS, and that is worth knowing before anyone deletes this dance: the
# layout's parent is now ScenarioDirector's game.get_viewport(), which is GameView in the shipped
# tree -- but a suite's board sits under the ROOT viewport, so here it still lands where it did.
class_name DialogFixtures


# End whatever is talking and wait for the layout to actually die. Call from after_test (and
# from before_test if the suite needs a silent board mid-case -- pair with director.disarm()).
static func end_all_dialog(suite: GdUnitTestSuite) -> void:
	if Dialogic.current_timeline != null:
		Dialogic.end_timeline(true)
		await Dialogic.timeline_ended   # end_timeline is async; ended fires after its clears
	await suite.await_idle_frame()
	await suite.await_idle_frame()      # the layout is queue_freed -- let it die before orphan accounting
