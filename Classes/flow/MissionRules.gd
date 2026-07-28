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

# Is anyone hostile to the player still commandable? Downed counts the same as dead, on both
# sides. Hostility is Team's call, not ours -- an ALLY faction fighting beside you needs no edit.
static func has_active_hostiles(board: BoardContext) -> bool:
	for faction in board.present_factions():
		if Team.is_enemy(Team.Faction.PLAYER, faction) and board.faction_has_active_units(faction):
			return true
	return false

# Both sides commandable right now -- i.e. this board is a mission in progress and not a dev
# scratchpad. MissionController latches this; see the `contested` note on evaluate().
static func is_contested(board: BoardContext) -> bool:
	return board.faction_has_active_units(Team.Faction.PLAYER) and has_active_hostiles(board)

# A scenario that authors an objective is won by THAT and nothing else (dev call 2026-07-28):
# routing the enemy on a capture map does not win it. Locking yourself out is a level-design
# problem, solved by building the map so it can't happen -- not by adding a consolation win.
static func evaluate(board: BoardContext, contested: bool, progress: Progress = Progress.NONE) -> Outcome:
	if not contested:
		return Outcome.ONGOING
	if not board.faction_has_active_units(Team.Faction.PLAYER):
		return Outcome.DEFEAT
	if progress != Progress.NONE:
		return Outcome.VICTORY if progress == Progress.MET else Outcome.ONGOING
	# Nothing authored: a plain rout map. Every scenario saved before objectives existed lands
	# here, which is why the fallback stays rather than becoming an unwinnable board.
	if not has_active_hostiles(board):
		return Outcome.VICTORY
	return Outcome.ONGOING
