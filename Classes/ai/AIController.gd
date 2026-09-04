extends Node
class_name AIController

# Runs archetype AI (#29) for AI-controlled factions. Orders funnel through
# SquadManager.queue_action exclusively (Law #3) -- this class only decides WHEN an
# archetype plans, then reuses OrderExecutor.execute_orders (the same path the player's
# Execute button takes) so a bot turn resolves identically to a human one.
#
# Two independent layers, and since #150 both are BOARD CONTENT. ENABLED is per-faction,
# carried by ScenarioData.ai_factions and applied on every load -- the Dev Overlay -> Scenario
# tab checkboxes are the live override, no longer the only source. ARCHETYPE (AIArchetype.Type)
# is per-squad (Squad.archetype, saved via ScenarioUnitEntry.squad_archetype on the leader's).

var game   # the Game coordinator; set by game._ready()

var _enabled: Dictionary = {}   # Faction -> bool; unset factions fall back to DEFAULT_ENABLED
const DEFAULT_ENABLED := false  # off by default -- opt in per faction from the dev console

func is_faction_ai_enabled(faction: Team.Faction) -> bool:
	return _enabled.get(faction, DEFAULT_ENABLED)

func set_faction_ai_enabled(faction: Team.Faction, enabled: bool) -> void:
	_enabled[faction] = enabled

func is_ai_faction(faction: Team.Faction) -> bool:
	return is_faction_ai_enabled(faction)

# The enabled set, in Team.all_factions() order -- deterministic, so re-saving an unchanged
# board produces no spurious .tres churn.
func ai_factions() -> Array[Team.Faction]:
	var result: Array[Team.Faction] = []
	for faction in Team.all_factions():
		if is_faction_ai_enabled(faction):
			result.append(faction)
	return result

# REPLACES the whole set, never adds to it (#150): an unlisted faction falls back to
# DEFAULT_ENABLED, so one board's flags cannot leak into the next board loaded.
func set_ai_factions(factions: Array[Team.Faction]) -> void:
	_enabled.clear()
	for faction in factions:
		_enabled[faction] = true

# WHICH SQUADS a faction still has to act with. Static and game-free because the headless Play
# API takes an AI turn too (#665), and "which squads act" must have ONE answer -- a second walk
# would drift the moment either side grew a skip condition (Law #4). What genuinely differs
# between the two callers is PRESENTATION (camera, pacing) and EXECUTION (animated orders versus
# the headless resolve), and those stay at the callers where they belong.
#
# The caller must STILL revalidate inside its loop: acting with one squad can kill another's
# leader or disband it outright, so this is the starting list, not a promise about later.
static func actable_squads(faction: Team.Faction, squad_manager: SquadManager) -> Array[Squad]:
	var out: Array[Squad] = []
	for squad: Squad in squad_manager.squads.duplicate():
		if is_squad_actable(squad, faction):
			out.append(squad)
	return out


static func is_squad_actable(squad: Squad, faction: Team.Faction) -> bool:
	if not is_instance_valid(squad) or squad.has_acted:
		return false
	if squad.leader == null or squad.leader.get_faction() != faction:
		return false
	return squad.leader.is_active()


# ONE squad's DECISION -- the archetype call, and the stale-pick reset that has to precede it.
# No camera, no pacing, no execution: the caller owns those. Orders still reach the board only
# through SquadManager.queue_action inside the archetype, so Law #3 is unaffected by the split.
static func plan_squad(squad: Squad, board: BoardContext, squad_manager: SquadManager) -> void:
	for member in squad.get_members():
		member.active_attack = null   # fresh pick each turn -- a stale winner from last turn would skew reach queries (mirrors _begin_attack's reset)
	AIArchetype.resolve(squad.archetype).call(squad, board, squad_manager)


# THE BOARD IS RE-DERIVED PER SQUAD, and it takes no board parameter for exactly that reason (#714).
# This used to build one BoardContext for the whole turn while `execute_orders` between squads spans
# frames, so a unit an earlier squad KILLED was genuinely freed by the time a later squad planned --
# and `_resolve_actions`' clear loop calls a method on every unit the board lists. Everything else it
# got wrong was quieter: for the rest of the turn the AI targeted, pathed and measured cohesion
# against a roster including the dead.
#
# `play_session._take_ai_turn` has always called `_board()` inside its own loop, which is why the
# headless API never reproduced it -- two live implementations of one walk, and the crash lived in
# whichever one was not the model. This is now the same shape.
func take_faction_turn(faction: Team.Faction) -> void:
	for squad in actable_squads(faction, game.squad_manager):
		# The mission can end mid-turn -- this squad's pass may have wiped the player. Stop
		# issuing orders behind the end-of-mission card (#96).
		if game.mission_controller.is_over():
			return
		# Revalidated per iteration, not merely filtered once above: the squad that just acted
		# may have downed this one's leader.
		if not is_squad_actable(squad, faction):
			continue

		await game.camera_controller.pan_to(squad.get_leader())
		# board_source is the wired seam for "the board as it stands", the same Callable
		# SquadManager's own validators resolve fresh per query.
		var board: BoardContext = game.squad_manager.board_source.call()
		plan_squad(squad, board, game.squad_manager)
		# The plan is on screen now -- queueing repaints the queue panel, path arrows, ghosts and
		# target markers synchronously -- so hold before resolving it (#118). Skipped when the squad
		# only holds position: there is nothing to read, and dead air per squad is the complaint.
		if not game.squad_manager.only_hold_actions(squad):
			await Pacing.beat(self, Pacing.AI_PLAN_READ)
		await game.order_executor.execute_orders(squad.get_leader())

	if game.mission_controller.is_over():
		return
	await game.end_turn()
