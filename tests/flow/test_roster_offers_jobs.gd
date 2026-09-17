# Which jobs a mission offers its pre-mission picker (#964) -- the fourth of Roster's offer lists,
# and the WIRE from the authored file to the phase object a card actually reads.
#
# Built ad hoc (tests/README.md rule 4): the curated cases name ids this suite invents, so nothing
# here asserts which jobs happen to be authored. The two cases that must touch the real catalogue ask
# it for its own answer rather than pinning a name or a count.
extends GdUnitTestSuite

const MADE_UP := "__test_job_964"


# The cache is handed out BY REFERENCE (Dictionary is a reference type), so a case can put a job in
# front of the catalogue without writing into Resources/Jobs/ -- which would leak into the live dev
# editor's job list, the reason tests/support/job_fixtures.gd borrows entries rather than adding one.
# refresh() drops the cache, so the next scan is the real folder again.
func after_test() -> void:
	JobCatalog.refresh()


func _inject_a_job() -> String:
	var made := JobData.new()
	made.id = MADE_UP
	made.display_name = "Test Job"
	var cache: Dictionary = JobCatalog.get_jobs()
	cache[MADE_UP] = made
	return MADE_UP


func _curated(ids: Array[String]) -> Roster:
	var roster := Roster.new()
	roster.offers_every_job = false
	roster.available_jobs = ids
	return roster


# --- the accessor -------------------------------------------------------------------------------

func test_a_curated_list_is_the_whole_offer() -> void:
	var ids: Array[String] = ["one", "two"]
	assert_array(_curated(ids).offered_jobs()).contains_exactly(["one", "two"])


# EMPTY MEANS NONE, and this is the case that says so at this layer. The mod list's own downstream
# reader treats an empty pool as EVERY mod (WeaponModCatalog.offerable_for), which is the collapse
# this path deliberately does not copy.
func test_an_empty_curated_list_offers_nothing_rather_than_everything() -> void:
	assert_array(_curated([]).offered_jobs()).override_failure_message(
			"a roster that offers no job handed back a list anyway -- empty has stopped meaning none"
			).is_empty()


func test_the_flag_answers_with_the_catalogue() -> void:
	var catalogued: Array = JobCatalog.get_jobs().keys()
	assert_array(catalogued).override_failure_message(
			"no jobs are authored at all, so the case below would pass vacuously").is_not_empty()

	var roster := Roster.new()   # offers_every_job defaults TRUE
	assert_array(roster.offered_jobs()).contains_exactly_in_any_order(catalogued)


# The whole reason the flag is a STORED FLAG rather than a bulk tick: it resolves at read time, so a
# roster authored today offers a job authored tomorrow. A snapshot of the catalogue could not.
func test_the_flag_picks_up_a_job_authored_after_the_roster_was() -> void:
	var roster := Roster.new()
	assert_array(roster.offered_jobs()).not_contains([MADE_UP])

	_inject_a_job()
	assert_array(roster.offered_jobs()).override_failure_message(
			"the flag answered from a snapshot -- a job added later is invisible to it"
			).contains([MADE_UP])
	assert_array(_curated(["one"]).offered_jobs()).override_failure_message(
			"a curated list grew a job nobody ticked").not_contains([MADE_UP])


# --- the wire to the phase ----------------------------------------------------------------------

# THE WIRE, not its two ends: deploy_roster resolves the Roster and DROPS it, so a card built minutes
# later reads the Loadout or reads nothing. Both halves could be right with nothing joining them.
func test_the_offer_reaches_the_phase() -> void:
	var ids: Array[String] = ["one", "two"]
	assert_array(Loadout.from_roster(_curated(ids)).available_jobs).contains_exactly(["one", "two"])


# APPENDED, never assigned. With the flag off the accessor hands back the resource's OWN array and
# load() serves the cache, so an assignment would leave the phase holding the authored file's list --
# the mutation Loadout exists to prevent, and invisible to any assertion about CONTENTS.
func test_the_phase_holds_its_own_array_and_not_the_authored_one() -> void:
	var roster := _curated(["one"])
	assert_object(Loadout.from_roster(roster).available_jobs).override_failure_message(
			"the phase is holding the roster resource's own array -- editing one edits the file"
			).is_not_same(roster.available_jobs)


func test_a_board_naming_no_roster_offers_no_job() -> void:
	assert_array(Loadout.from_roster(null).available_jobs).is_empty()
