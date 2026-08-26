extends Object
class_name MissionRules

# The win/lose predicate for a mission (#96 slice 1, docs/design/missions.md). Pure and static,
# in LethalityRules' shape: it reads a BoardContext and returns an answer, holding no state, so
# the in-game MissionController, the headless Play API and the tests all ask ONE question and
# cannot drift into three.
#
# Slice 1 has exactly one objective and it is authored nowhere: wipe every hostile faction,
# lose if the player has nobody left standing. Authored objectives (slices 3-4) enter as extra
# clauses HERE, with a MissionData handed in beside the board -- never as a second evaluator.

enum Outcome { ONGOING, VICTORY, DEFEAT }

# What a mission REQUIRES, authored per-scenario (ScenarioData.objectives) and edited in the dev
# Scenario tab. Painting a zone no longer declares an objective by itself -- so a CAPTURE zone can
# be decorative, and a mis-picked Zone Kind can no longer silently rewrite the win condition.
#
# PERSISTED -> APPEND-ONLY (enums serialize as plain ints).
enum Objective {
	ROUT,      # no faction hostile to the player has an active unit left
	CAPTURE,   # every ZoneManager.Kind.CAPTURE zone claimed
	EXTRACT,   # every surviving player unit inside a Kind.EXTRACTION zone
}

# How far along the mission's requirements are, as a whole. NONE means "nothing was required",
# which is NOT the same as PENDING -- conflating them is how "no objective" becomes "instantly won".
enum Progress { NONE, PENDING, MET }

# What LOSES a mission (#101). An objective is something the player DOES; a lose condition is
# something they fail to prevent, which is why it is its own list rather than a negated objective:
# the timing differs (checked continuously, not for completion) and a failure must name a reason
# for the banner. They compose by ANY -- the first one that fires ends it.
#
# PERSISTED -> APPEND-ONLY (enums serialize as plain ints).
enum LoseCondition {
	NONE,         # sentinel: nothing fired. Never authored.
	SQUAD_LOST,   # the #96 floor: always on, never authored.
	ROUND_LIMIT,  # the objectives were not met within ScenarioData.round_limit rounds.
}

# What the Scenario tab offers. A const rather than "every enum value" so the two non-authored
# members are a decision, not an accident of a loop's shape.
const AUTHORABLE: Array[LoseCondition] = [LoseCondition.ROUND_LIMIT]

# The banner's body text for a defeat. One answer, one reader (MissionEndBanner).
static func defeat_reason(condition: LoseCondition) -> String:
	match condition:
		LoseCondition.SQUAD_LOST:
			return "Your squad has fallen."
		LoseCondition.ROUND_LIMIT:
			return "Time ran out."
	return ""

# Rounds left on the clock -- the HUD's countdown. A limit of 0 is NO limit, so it never runs out.
static func rounds_remaining(rounds_elapsed: int, round_limit: int) -> int:
	if round_limit <= 0:
		return 0
	return maxi(0, round_limit - rounds_elapsed)

# Derived from the count above so the readout and the predicate cannot drift (has_active_hostiles'
# shape). The clock expires when the LAST allowed round completes, not a round early.
static func round_limit_reached(rounds_elapsed: int, round_limit: int) -> bool:
	return round_limit > 0 and rounds_remaining(rounds_elapsed, round_limit) <= 0

# Is anyone hostile to the player still commandable? Downed counts the same as dead, on both
# sides. Hostility is Team's call, not ours -- an ALLY faction fighting beside you needs no edit.
static func has_active_hostiles(board: BoardContext) -> bool:
	return active_hostile_count(board) > 0

# How many are left -- the rout objective's "N foes remain" readout (#134). has_active_hostiles is
# derived from this so the count and the predicate cannot drift.
static func active_hostile_count(board: BoardContext) -> int:
	var count := 0
	for unit in board.units:
		if is_instance_valid(unit) and unit.is_active() \
				and Team.is_enemy(Team.Faction.PLAYER, unit.get_faction()):
			count += 1
	return count

# Both sides commandable right now -- i.e. this board is a mission in progress and not a dev
# scratchpad. MissionController latches this; see the `contested` note on evaluate().
static func is_contested(board: BoardContext) -> bool:
	return board.faction_has_active_units(Team.Faction.PLAYER) and has_active_hostiles(board)

# A scenario that authors an objective is won by THAT and nothing else (dev call 2026-07-28):
# routing the enemy on a capture map does not win it. Locking yourself out is a level-design
# problem, solved by building the map so it can't happen -- not by adding a consolation win.
#
# `failure` is handed in the way `progress` is: MissionController computes it, this stays pure.
# ORDER (#101): the squad wipe is asked FIRST, so mutual destruction stays a DEFEAT and reports
# SQUAD_LOST rather than whatever else fired that instant. Every VICTORY path is asked BEFORE an
# authored failure -- finishing on the last allowed round is finishing in time, and a clock must
# not steal a win the player earned.
static func evaluate(board: BoardContext, contested: bool, progress: Progress = Progress.NONE,
		failure: LoseCondition = LoseCondition.NONE) -> Outcome:
	if not contested:
		return Outcome.ONGOING
	if not board.faction_has_active_units(Team.Faction.PLAYER):
		return Outcome.DEFEAT
	if progress == Progress.MET:
		return Outcome.VICTORY
	# Nothing authored: a plain rout map. Every scenario saved before objectives existed lands
	# here, which is why the fallback stays rather than becoming an unwinnable board.
	if progress == Progress.NONE and not has_active_hostiles(board):
		return Outcome.VICTORY
	if failure != LoseCondition.NONE:
		return Outcome.DEFEAT
	return Outcome.ONGOING
