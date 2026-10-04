extends RefCounted
class_name MissionState

# One mission's battle-scoped state and the rules that read it (#46): what this mission requires and
# what loses it, how far through it this battle is, and whether it has ended. Two hosts own one --
# the game's MissionController, and the headless Play API -- so a mission scores the same in both.
#
# The predicate itself is MissionRules, pure and static. This holds what a pure predicate cannot:
# the latches, the captured zones, the round clock. It never touches the HUD, the overlay, the
# telemetry log or the banner; what a host DOES about an ending stays with the host.

# The board's zone store, the one place a capture point, extraction zone or defended cargo lives.
var zones: ZoneManager

var outcome: MissionRules.Outcome = MissionRules.Outcome.ONGOING
var contested := false
# Which CAPTURE zones have been claimed, by name. Battle-scoped, which is why it lives here and
# not on ScenarioData: the zones are authored content, taking them is this battle's progress.
var captured_zones: Array[String] = []
# What THIS mission requires. Authored content that arrives with the scenario, so it is cleared by
# reset() and refilled on load -- one list for every objective kind, rather than a field per kind.
var objectives: Array[MissionRules.Objective] = []
# What LOSES it, and the clock's limit (#101). Authored, so both clear with the objectives above.
var lose_conditions: Array[MissionRules.LoseCondition] = []
var round_limit := 0
# Rounds the clock has counted. Battle-scoped like captured_zones, for the same reason: the limit
# is authored content, how far through it this battle is is progress. Advanced from ONE place.
var rounds_elapsed := 0
# Why the mission was lost, for the banner. Set beside `outcome`, so it can never name a reason for
# an ending that did not happen.
var failed_by: MissionRules.LoseCondition = MissionRules.LoseCondition.NONE
# Has a unit the mission was protecting died (#572)? A LATCH, not a board question, and it has to be:
# Unit.die() queue_frees the node, so by the time any evaluation runs the unit is simply gone --
# which is indistinguishable from one that was never placed at all. Battle-scoped, cleared by reset().
#
# It never needs saving. The mission ends on the very next evaluation after the death, which runs at
# the end of the pass the death resolved in, so no save can be taken while this is true.
var protected_lost := false


func _init(zone_store: ZoneManager = null) -> void:
	zones = zone_store


func is_over() -> bool:
	return outcome != MissionRules.Outcome.ONGOING

# The rule half of an evaluation: latch `contested`, compose this mission's progress and failure,
# and ask MissionRules. An ending is LATCHED here, with its reason, so a mission that has ended stays
# ended whatever the board does next -- the host decides what an ending looks like.
func evaluate(board: BoardContext) -> MissionRules.Outcome:
	if is_over():
		return outcome
	if not contested:
		contested = MissionRules.is_contested(board)
	var failure: MissionRules.LoseCondition = failure_for(board)
	var result: MissionRules.Outcome = MissionRules.evaluate(board, contested,
			objective_progress(board), failure)
	if result == MissionRules.Outcome.ONGOING:
		return result
	outcome = result
	if result == MissionRules.Outcome.DEFEAT:
		failed_by = failure   # set beside the outcome, so the banner cannot name a stale reason
	return result

# Mission START: the blank slate restore() writes a mid-battle snapshot back over (#87).
func reset() -> void:
	outcome = MissionRules.Outcome.ONGOING
	contested = false
	captured_zones.clear()
	objectives.clear()
	lose_conditions.clear()
	round_limit = 0
	rounds_elapsed = 0
	failed_by = MissionRules.LoseCondition.NONE
	protected_lost = false

# Runs after zones are refilled.
func restore(zone_names: Array[String], was_contested: bool, rounds := 0) -> void:
	captured_zones.assign(zone_names)
	contested = was_contested
	rounds_elapsed = rounds

# ==============================================================================
#  The capture objective (#96 slice 3)
# ==============================================================================

# The uncaptured CAPTURE zone at this cell, "" when none. Kind-filtered because zones overlap
# (2026-08-12): "the" zone at a cell stopped being a well-formed question, and every reader of the
# old zone_at was asking exactly this one. A captured zone stops matching, so where two capture
# zones overlap the second becomes capturable once the first is claimed.
func capturable_zone_at(cell: Vector2i) -> String:
	for name in zones.zone_names_of(ZoneManager.Kind.CAPTURE):
		if zones.contains(name, cell) and not captured_zones.has(name):
			return name
	return ""

# Standing anywhere in a capture zone claims the WHOLE zone -- a multi-tile objective is one
# objective, not N of them. True when this call claimed it; what follows a claim is the host's.
func capture(zone_name: String) -> bool:
	if zone_name == "" or captured_zones.has(zone_name):
		return false
	if zones.kind_of(zone_name) != ZoneManager.Kind.CAPTURE:
		return false
	captured_zones.append(zone_name)
	return true

func is_zone_captured(zone_name: String) -> bool:
	return captured_zones.has(zone_name)


# Declared objectives whose geometry was never painted. ROUT needs none, so it can never appear here.
func objectives_missing_geometry() -> Array[MissionRules.Objective]:
	var missing: Array[MissionRules.Objective] = []
	for objective: MissionRules.Objective in MissionRules.OBJECTIVE_ZONE_KIND:
		if objectives.has(objective) and zones.zone_names_of(MissionRules.OBJECTIVE_ZONE_KIND[objective]).is_empty():
			missing.append(objective)
	return missing

# Every declared objective must be met -- they compose by AND. An empty list is NONE, which sends
# MissionRules.evaluate to its rout fallback.
func objective_progress(board: BoardContext) -> MissionRules.Progress:
	if objectives.is_empty():
		return MissionRules.Progress.NONE
	for objective in objectives:
		if progress_for(objective, board) != MissionRules.Progress.MET:
			return MissionRules.Progress.PENDING
	return MissionRules.Progress.MET

# Public since #134: the mission-status HUD reads each declared objective's own progress. The
# rules stay here -- the HUD never re-derives them.
func progress_for(objective: MissionRules.Objective, board: BoardContext) -> MissionRules.Progress:
	match objective:
		MissionRules.Objective.ROUT:
			return MissionRules.Progress.MET if not MissionRules.has_active_hostiles(board) else MissionRules.Progress.PENDING
		MissionRules.Objective.CAPTURE:
			return _capture_progress()
		MissionRules.Objective.EXTRACT:
			return _extract_progress(board)
	push_error("MissionState: no progress rule for objective %s" % MissionRules.Objective.keys()[objective])
	return MissionRules.Progress.PENDING

# (captured, total painted CAPTURE zones) -- the HUD's "1/2 zones". _capture_progress derives MET
# from these same numbers so the count and the boolean cannot drift (#134).
func capture_counts() -> Vector2i:
	var targets: Array[String] = zones.zone_names_of(ZoneManager.Kind.CAPTURE)
	var done := 0
	for name in targets:
		if captured_zones.has(name):
			done += 1
	return Vector2i(done, targets.size())

# Unpainted geometry reads as PENDING, not MET: the mission really is unwinnable, and silently
# dropping the objective would quietly turn a broken map into a different, playable one.
func _capture_progress() -> MissionRules.Progress:
	var counts := capture_counts()
	if counts.y == 0:
		return MissionRules.Progress.PENDING
	return MissionRules.Progress.MET if counts.x == counts.y else MissionRules.Progress.PENDING

# (surviving player units inside an extraction zone, surviving player units) -- "surviving" is
# not-DEAD, so the DOWNED count on both sides of the fraction, per the doctrine on
# _extract_progress below.
func extract_counts(board: BoardContext) -> Vector2i:
	var extraction: Array[String] = zones.zone_names_of(ZoneManager.Kind.EXTRACTION)
	var done := 0
	var total := 0
	for unit in board.units:
		if not is_instance_valid(unit) or unit.get_faction() != Team.Faction.PLAYER or unit.is_dead():
			continue
		total += 1
		if _in_any_zone(extraction, unit.movement.cell):
			done += 1
	return Vector2i(done, total)

# "Surviving" is not-DEAD, so a DOWNED unit inside the zone counts as extracted exactly like an
# active one -- alive and in the zone means they get out. What blocks the objective is a living
# unit OUTSIDE the zone, and a downed one out there cannot walk in on its own: someone has to
# reach them with RescueAction, which revives to ACTIVE at whatever HP the body has.
func _extract_progress(board: BoardContext) -> MissionRules.Progress:
	# The zones-empty guard runs BEFORE the counts: an unpainted extraction with no player units
	# would read 0 == 0 as MET, converting the broken map _capture_progress refuses to.
	if zones.zone_names_of(ZoneManager.Kind.EXTRACTION).is_empty():
		return MissionRules.Progress.PENDING
	var counts := extract_counts(board)
	# Zero surviving players is _capture_progress's counts.y == 0 twin (missing until 2026-08-12):
	# 0 == 0 read as MET, which ticked Extract on the HUD during load, before units had spawned.
	# For evaluate() the guard never decides anything -- DEFEAT is checked first.
	if counts.y == 0:
		return MissionRules.Progress.PENDING
	return MissionRules.Progress.MET if counts.x == counts.y else MissionRules.Progress.PENDING

# Several extraction zones on one map are alternatives, not a set to split across.
func _in_any_zone(zone_names: Array[String], cell: Vector2i) -> bool:
	for name in zone_names:
		if zones.contains(name, cell):
			return true
	return false

# ==============================================================================
#  Lose conditions (#101)
# ==============================================================================

# Asked once per death by each host's one death handler. Unit.die() emits once and is idempotent,
# so this is never re-asked about a corpse.
func note_unit_died(unit: Unit) -> void:
	if unit != null and unit.must_survive:
		protected_lost = true

# Who this mission is protecting, still standing -- the HUD's readout.
func protected_units(board: BoardContext) -> Array[Unit]:
	return MissionRules.protected_units(board)

# The cargo this mission is holding -- every painted Kind.DEFEND zone. ONE answer, and both readers
# are downstream of it: the lose condition asks whether a hostile is standing in any of them, and
# the HUD names them. There is no owner and no progress to hold, which is why this is a pass-through
# to the zone store rather than a battle-scoped field like captured_zones: a defended point is
# authored geometry that either still holds or has ended the mission.
func defend_zone_names() -> Array[String]:
	return zones.zone_names_of(MissionRules.LOSE_ZONE_KIND[MissionRules.LoseCondition.POINT_LOST])

# Who is standing on the cargo right now, null while it holds. The HUD's readout and the predicate
# both come off MissionRules, so the row and the rule cannot disagree.
func breaching_unit(board: BoardContext) -> Unit:
	return MissionRules.breaching_unit(board, defend_zone_names(), zones)

# Declared lose conditions with no usable parameter -- objectives_missing_geometry's twin, and the
# same doctrine: the mission really is broken, so say so loudly rather than dropping the clause.
func lose_conditions_missing_setup(board: BoardContext) -> Array[MissionRules.LoseCondition]:
	var missing: Array[MissionRules.LoseCondition] = []
	if lose_conditions.has(MissionRules.LoseCondition.ROUND_LIMIT) and round_limit <= 0:
		missing.append(MissionRules.LoseCondition.ROUND_LIMIT)
	# #571's geometry half, and it is objectives_missing_geometry's rule rather than the clock's:
	# the cargo IS the painted zone, so a declared POINT_LOST with nothing painted has nothing to
	# lose and the mission is simply not the mission that was authored.
	if lose_conditions.has(MissionRules.LoseCondition.POINT_LOST) and defend_zone_names().is_empty():
		missing.append(MissionRules.LoseCondition.POINT_LOST)
	# #572's twin, with one extra clause that is not decoration: once the VIP has died there is
	# genuinely nobody flagged on the board, and without `not protected_lost` the row would flip to
	# "not set" at the exact moment the condition FIRED -- reporting a broken board for the one
	# thing that worked.
	if lose_conditions.has(MissionRules.LoseCondition.PROTECTED_UNIT_LOST) and not protected_lost \
			and protected_units(board).is_empty():
		missing.append(MissionRules.LoseCondition.PROTECTED_UNIT_LOST)
	return missing

# The ONE increment point, called from each host's round handler. TurnManager emits round_completed
# before turn_started, so the very next evaluation -- turn start, after the downed clocks tick -- is
# the one that sees it. No new evaluation seam.
func advance_round() -> void:
	rounds_elapsed += 1

# Rounds left on the clock, for the HUD. 0 when no clock is authored.
func rounds_remaining() -> int:
	return MissionRules.rounds_remaining(rounds_elapsed, round_limit)

# WHY this mission is lost, NONE while it is not. The reason only; whether the mission ends is
# MissionRules.evaluate's answer, which is handed this and keeps its own wipe branch for callers
# that pass nothing. Both read the one faction predicate below.
#
# The wipe outranks an authored condition, matching evaluate's own order: a squad lost on the round
# the clock expires reports the squad, which is the more concrete thing that happened.
func failure_for(board: BoardContext) -> MissionRules.LoseCondition:
	if not board.faction_has_active_units(Team.Faction.PLAYER):
		return MissionRules.LoseCondition.SQUAD_LOST
	for condition in lose_conditions:
		if _condition_fired(condition, board):
			return condition   # ANY, not all -- the first one that fires ends it
	return MissionRules.LoseCondition.NONE

func _condition_fired(condition: MissionRules.LoseCondition, board: BoardContext) -> bool:
	match condition:
		MissionRules.LoseCondition.ROUND_LIMIT:
			return MissionRules.round_limit_reached(rounds_elapsed, round_limit)
		MissionRules.LoseCondition.POINT_LOST:
			return MissionRules.defend_zone_breached(board, defend_zone_names(), zones)
		MissionRules.LoseCondition.PROTECTED_UNIT_LOST:
			return protected_lost
		MissionRules.LoseCondition.NONE, MissionRules.LoseCondition.SQUAD_LOST:
			return false   # never authored; the wipe is answered above, not from the list
	push_error("MissionState: no rule for lose condition %s" % MissionRules.LoseCondition.keys()[condition])
	return false
