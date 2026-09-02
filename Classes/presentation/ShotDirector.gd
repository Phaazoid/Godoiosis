extends RefCounted
class_name ShotDirector

# WHICH SHOT OWNS THE CAMERA (#672), and nothing else.
#
# WHY IT EXISTS. Until this, the camera's shots were implicit: there was no object called "the
# trained close-up", only five edge-driven writers of the distance channel inside
# battle3d._mirror_camera whose precedence was TEMPORAL -- whichever edge fired most recently won.
# That is the whole of the #602 arc's cost. Round 8's three hand-rolled fixes were one sentence --
# the death show outranks everything until its last cube lands -- with nowhere to be written down,
# so each channel had to learn it separately and the enumeration was a discipline rather than a
# structure.
#
# WHAT IT IS. A priority table, and the ENUM'S ORDER IS THE TABLE: a higher value outranks a lower
# one, solve() picks the highest-ranked LIVE row, and inserting a shot means choosing where in that
# list it goes -- which is the decision, made where it can be seen, and enforced rather than
# merely written (see solve). The framings themselves live at the one apply site in battle3d,
# because what a shot DOES needs the board volumes, the staged height and the rig; what it IS
# needs none of them. Two questions, two homes, along the #176 grain.
#
# THE DEFERRAL FALLS OUT rather than being maintained. Round 8's rule was a latch, a deliberately
# un-advanced subject id, and a comment explaining how the two interacted. Here it is one row
# ranked above everything a RELEASE WOULD FALL TO, with a framing that writes nothing: while the
# show holds, the solve says DEATH_SHOW; when it clears, the solve drops to whatever is next and
# the transition fires THEN. Deferred, never skipped, because a priority table cannot express
# "skipped".
#
# SCENE-FREE, not pure -- it holds the active shot and the causes that shape it, which is what an
# edge is. (frame_drop and recovered are the pure ones; this deliberately does not borrow their
# word.) What it buys is that the table is testable with no viewport, no board and no rig: every
# precedence case in tests/presentation/test_shot_director.gd is five arguments and an answer.

# Priority ASCENDING -- a higher value outranks a lower one.
#
# NONE is FIRST so it is the storage's own default: "no shot, the view is the player's" has to be
# what an un-run director already says, and a -1 sentinel beside a 0 default is the shape that
# rule exists to refuse.
enum Shot {
	NONE,         # playback does not own the camera -- the gate's answer, not a row
	WIDE,         # the director's own base: playback owns the camera and nothing narrows it
	SPAN,         # a walk, framed across both its ends
	STAGE,        # a fight's cells, framed so the whole diorama is held
	TRAINED,      # one subject: a beat's actor, a body mid-tumble
	DEATH_SHOW,   # a void death's cubes are in the air and the frame may not move
}


# The shot that owns the camera right now. Written only by update().
var active: Shot = Shot.NONE

# ...and the one before it, so a transition can name both ends. Its own field rather than a return
# value: the trace row is composed after the apply, and passing the pair through would make two
# callers responsible for keeping them in step.
var previous: Shot = Shot.NONE

# The causes as this director last saw them. These are the EDGE: a shot that has not changed can
# still need re-applying because the volume it frames has (a stage re-published over different
# cells), and the subject can change under a TRAINED shot that stays TRAINED.
var _subject_id := 0
var _cells: Array[Vector2i] = []
var _span: Array[Vector2i] = []


# The table: one row per shot, each stating its own liveness, and the highest-ranked live one
# wins. Static and total -- five facts in, one shot out, no state.
#
# WRITTEN AS A RANK COMPARE RATHER THAN AN IF-CASCADE, so THE ENUM'S ORDER IS THE MECHANISM: move
# a row and the answer changes. A cascade would read the same and mean less -- the order would be
# a convention nothing enforced, and reordering the enum to say something new would silently say
# nothing. (Found by asking what a mutant that swapped two rows would do: under a cascade, pass.)
#
# THE LOCK IS THE GATE AND NOT A ROW. While playback does not own the camera there is no shot at
# all -- the view is the player's, and the release must always restore it. A LOCKED row would sit
# somewhere in this order and be outranked by whatever is above it, so a death show still playing
# as the lock let go would hold the camera hostage past the end of the pass.
#
# WHAT THE DEATH SHOW ACTUALLY OUTRANKS IS THE FALLBACK, NOT THE CLOSE-UP. Its condition is "the
# show is live AND nobody is followed" and TRAINED's is "somebody is followed", so the two are
# mutually exclusive and never compete: DEATH_SHOW is what stands in TRAINED's place once the body
# is gone. The rank that matters is the one over STAGE, SPAN and WIDE -- the shots a release would
# otherwise fall to -- and that is precisely what makes the release a DEFERRAL. (#602 round 8 read
# as "the show beats the follow", which is why it took three hand-rolled fixes to say once.)
static func solve(locked: bool, subject_id: int, staged: bool, spanned: bool,
		death_show: bool) -> Shot:
	if not locked:
		return Shot.NONE
	var live := Shot.WIDE
	live = _ranked(live, Shot.SPAN, spanned)
	live = _ranked(live, Shot.STAGE, staged)
	live = _ranked(live, Shot.TRAINED, subject_id != 0)
	live = _ranked(live, Shot.DEATH_SHOW, death_show and subject_id == 0)
	return live


# The rank compare, one row at a time: a live shot takes the camera only from something it
# outranks. Absent -- and a shot that is not live -- changes nothing, which is what lets the rows
# above be read in any order and still mean what the enum says.
static func _ranked(held: Shot, candidate: Shot, is_live: bool) -> Shot:
	return candidate if is_live and candidate > held else held


# Take this frame's causes; answer whether the shot needs applying.
#
# TRUE ON A CHANGED CAUSE, not only on a changed shot. A stage re-published over different cells is
# the same STAGE shot framing a different volume, and TRAINED(A) -> TRAINED(B) is the same shot on
# a different subject -- which the trace has to name, since "which unit is the shot trained on" is
# a line in every bug report. The two are one rule: the edge is the whole input, never just its
# verdict (#308's shape, on the input side).
#
# FALSE otherwise, and that matters as much: the framings re-solve against the camera's own basis
# and re-latch the staged height, so applying one every frame would make a fit breathe as the yaw
# eased and would walk the whole shot down after any body thrown mid-fight.
func update(locked: bool, subject_id: int, cells: Array[Vector2i], span: Array[Vector2i],
		death_show: bool) -> bool:
	var next := solve(locked, subject_id, staged(cells), spanned(span), death_show)
	var changed := next != active or subject_id != _subject_id \
			or cells != _cells or span != _span
	if not changed:
		return false
	previous = active
	active = next
	_subject_id = subject_id
	_cells = cells.duplicate()
	_span = span.duplicate()
	return true


static func staged(cells: Array[Vector2i]) -> bool:
	return not cells.is_empty()


# A span frames BOTH ENDS of a walk, so one that is not a pair is not a span. The publisher's own
# rule (OrderExecutor._frame_the_walk skips a walk that goes nowhere); spelled here as well because
# this is where it decides a shot.
static func spanned(span: Array[Vector2i]) -> bool:
	return span.size() == 2


# The trace row for the transition just taken (#669's channel, #672's vocabulary). Composed here
# rather than at the call site so the shot words in a bug report cannot drift from the table that
# produced them; the subject's NAME is the one thing this cannot know and is passed in.
#
# The annotations are what a reader needs and the distances cannot show: that a hold is a hold, and
# that the release which follows it was DEFERRED rather than skipped -- the distinction eight
# rounds of screenshots could not make.
func transition_note(subject_name: String) -> String:
	var note := "shot %s -> %s" % [Shot.keys()[previous], Shot.keys()[active]]
	if active == Shot.TRAINED:
		return note + " (%s)" % subject_name
	if active == Shot.DEATH_SHOW:
		return note + " (holds)"
	if previous == Shot.DEATH_SHOW:
		return note + " (deferred release)"
	return note
