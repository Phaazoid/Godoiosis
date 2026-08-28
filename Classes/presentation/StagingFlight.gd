class_name StagingFlight
extends Object

# WHEN each torn-out tile leaves its socket and when it lands (#521 slice B). Pure and static: it is
# handed a cell list and answers with times, touching no node, no clock and no board.
#
# THIS IS THE ARTIFACT THE TWO SIDES AGREE THROUGH, and that is the whole reason it exists as a
# thing rather than as arithmetic inside the driver. OrderExecutor has no path to the 3D host -- it
# publishes facts and the mirror polls them -- so the executor awaits `total()` while the driver
# renders `progress_at()`, both off the SAME schedule. Two sides computing their own timings from
# the same knobs would agree until one of them was edited.
#
# It is also the only part of this slice a headless test can watch. The motion itself is invisible
# without frames (Pacing.beat returns instantly headless, and so does everything built on it), so
# the cases pin the SCHEDULE and the driver's decisions; the travel is a play-check. Same split this
# arc has used since #519, said out loud rather than implied by a green suite.
#
# ORDER IS THE CALLER'S, AND IT IS ALREADY THE RIGHT ONE: BeatSheet._gather_cells appends in
# playback order -- attacks, then counters, then cell effects, then the side channel -- so "tiles
# arrive in queue order, quietly foreshadowing who acts first" needs no sorting here and no second
# enumeration of who acts when.


# One entry per cell, in the order given. `start`/`land` are seconds from the transition's opening.
#
# THE STAGGER IS DERIVED, NOT AUTHORED, and that is a pacing decision rather than a tidy one: a
# fixed per-tile gap reads well on a four-cell skirmish and costs three seconds on a twenty-cell
# brawl, and this plays on EVERY Execute. So the arrival is given a total it must fit inside, and
# the gap is whatever fits -- capped, so a small fight still gets a punchy one-two-three rather
# than smearing three tiles over the whole window.
static func schedule(cells: Array[Vector2i]) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if cells.is_empty():
		return plan
	var gap := 0.0
	if cells.size() > 1:
		gap = minf(Pacing.TEAR_OUT_STAGGER_MAX, Pacing.TEAR_OUT_ARRIVAL / float(cells.size() - 1))
	var flight := maxf(Pacing.TEAR_OUT_FLIGHT, 0.0)
	for i in cells.size():
		var start := gap * float(i)
		plan.append({"cell": cells[i], "start": start, "land": start + flight})
	return plan


# When the last tile is home. The executor awaits exactly this, so a transition can never return
# with a tile still in the air.
static func total(plan: Array[Dictionary]) -> float:
	var last := 0.0
	for entry: Dictionary in plan:
		last = maxf(last, float(entry["land"]))
	return last


# How far along its flight this tile is at `elapsed`: 0 = still in its socket, 1 = home.
#
# LINEAR ON PURPOSE -- this class answers about TIME. The slam's acceleration is a shape applied by
# whoever draws it, because a curve is a look and this is a schedule; keeping them apart is what
# lets a case assert "the third tile has not left yet" without knowing what easing looks like.
static func progress_at(entry: Dictionary, elapsed: float) -> float:
	var start := float(entry["start"])
	var land := float(entry["land"])
	if elapsed <= start:
		return 0.0
	if land <= start or elapsed >= land:
		return 1.0
	return (elapsed - start) / (land - start)


# The slam: progress bent so a tile accelerates into its landing instead of drifting to it. Exponent
# 1 is constant speed; higher lands harder. Separate from progress_at above so the two can be
# reasoned about -- and tested -- one at a time.
static func slam(progress: float) -> float:
	return pow(clampf(progress, 0.0, 1.0), maxf(Pacing.TEAR_OUT_SLAM, 0.05))
