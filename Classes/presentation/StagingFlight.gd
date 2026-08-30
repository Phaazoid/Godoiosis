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
# `lead` delays every tile without stopping the clock, which is the difference between a pause and a
# freeze: the white-out is drawn off this same elapsed time, so a lead-in plays the flash and the
# camera cut over a sky with nothing in it yet. Passing it in rather than reading the knob here keeps
# this function answering one question, and lets the exit ask for no lead at all.
static func schedule(cells: Array[Vector2i], lead := 0.0) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if cells.is_empty():
		return plan
	var gap := 0.0
	if cells.size() > 1:
		gap = minf(Pacing.TEAR_OUT_STAGGER_MAX, Pacing.TEAR_OUT_ARRIVAL / float(cells.size() - 1))
	var flight := maxf(Pacing.TEAR_OUT_FLIGHT, 0.0)
	var opening := maxf(lead, 0.0)
	for i in cells.size():
		var start := opening + gap * float(i)
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


# --- the flash and the cut (#602 round 5) -------------------------------------------------------
#
# The white-out exists to hide the camera's CUT, so the two are ONE schedule under one rule: the
# cut sits at the flash's first full-white frame, and the flash anchors to the transition's
# cut-ward end (dev, 2026-08-29: "the white out should always be tied to the last thing that
# happens, the teleport, no matter what. Its whole purpose is to hide the teleport"). An ENTRY
# cuts UP at its start -- flash from zero, cut one ramp in, arrivals after the fade (which is why
# TEAR_OUT_EMPTY_SKY ships at the flash's full length). An EXIT cuts DOWN at its end -- the tiles
# fall bare, watched deliberately, the flash ramps once the last one is home, and the camera drops
# under full white. The exit used to borrow the entry's clock: flash at the start over nothing,
# drop bare at the end, which is exactly the report this round answers.


# Where the flash's clock starts for this transition. The travel-arm entry keeps its camera hold
# -- there is no cut to hide there, the flash covers an eased rise -- which is why the arm forks
# the ANCHOR rather than the arithmetic.
static func flash_anchor(entering: bool, cuts: bool, total_time: float) -> float:
	if not entering:
		return total_time
	return 0.0 if cuts else maxf(Pacing.TEAR_OUT_CAMERA_HOLD, 0.0)


# The flash at `elapsed` given its anchor: ramp up, full, ramp down, dark outside. Moved here from
# the 3D driver so the flash and the cut read ONE clock and cannot drift.
static func whiteout_level(elapsed: float, anchor: float) -> float:
	var since := elapsed - anchor
	var ramp := maxf(Pacing.TEAR_OUT_WHITEOUT, 0.001)
	var hold := maxf(Pacing.TEAR_OUT_HOLD, 0.0)
	if since < 0.0:
		return 0.0
	if since < ramp:
		return since / ramp
	if since < ramp + hold:
		return 1.0
	if since < ramp + hold + ramp:
		return 1.0 - (since - ramp - hold) / ramp
	return 0.0


# Whether the camera has crossed its cut at `elapsed`: one ramp past the flash's anchor, i.e. AT
# the first full-white frame. Asked by the cut-arm entry and by every exit; the travel-arm entry
# has no cut and never asks.
static func cut_over(elapsed: float, entering: bool, total_time: float) -> bool:
	var ramp := maxf(Pacing.TEAR_OUT_WHITEOUT, 0.001)
	return elapsed >= (ramp if entering else total_time + ramp)


# What each direction costs in full, awaited by the executor so the driver is never torn down with
# the flash still lit or the camera still up. An exit is the travel plus the whole flash that
# covers the drop home; an entry already contains its flash unless the knobs are tuned shorter
# than one, so the maxf is insurance rather than pacing.
static func entry_total(plan: Array[Dictionary]) -> float:
	return maxf(total(plan), _flash_length())


static func exit_total(plan: Array[Dictionary]) -> float:
	return total(plan) + _flash_length()


static func _flash_length() -> float:
	var ramp := maxf(Pacing.TEAR_OUT_WHITEOUT, 0.001)
	return ramp + maxf(Pacing.TEAR_OUT_HOLD, 0.0) + ramp
