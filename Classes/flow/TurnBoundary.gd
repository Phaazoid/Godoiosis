extends Object
class_name TurnBoundary

# The RULE half of a turn boundary (#898, first found by #110): who burns or soaks at a faction's end
# of turn, what ticks at its start, and what the hand-off decides. Static, and called by the game
# stack (game._on_turn_started, OrderExecutor.apply_end_of_turn_tiles) and the headless Play API, so
# a new tick or step cannot land in one stack only. The round tick is one call and stays in each
# stack's handler.


# Who the end-of-turn pass is about, answered ONCE before any of it plays -- the same TileHitAction
# the queue forecasts (#419), derived here from LIVE positions, tile state and gas instead of the
# plan's projected ones. Two derivations of one rule: a plan is per-SQUAD and this phase is
# per-FACTION, so neither can consume the other's list -- what they share is TileHitAction.end_of_turn,
# one unit's whole set of rows (#1331). The burn is TWO layers since #892: what the ground charges
# (Terrain.occupant_damage) and whether this unit pays it (fire insulation), and the scald the same
# two (GasRules.damage, RulesService.gas_damage_for); end_of_turn asks the outer ones, so an immune
# unit gets no forecast that lies about it.
#
# Walks UNITS rather than burning cells, which is what keeps it symmetric with the forecast: both
# ask "what is under this unit", so a hazard family the forecast can see cannot be one this misses.
# A unit's gas row comes BEFORE its burn (#508), and the burn is predicted on the HP a scald leaves,
# here and in the forecast, so the pass plays them in the order the queue lists them.
static func tile_hits(units: Array[Unit], states: TerrainStateManager, gas: GasField,
		weather: Weather.Kind, faction: Team.Faction) -> Array[TileHitAction]:
	var hits: Array[TileHitAction] = []
	for unit in units:
		if unit == null or not is_instance_valid(unit) or unit.get_faction() != faction:
			continue
		var packed := gas.packed_at(unit.movement.cell) if gas != null else 0
		hits.append_array(TileHitAction.end_of_turn(unit.state, packed, weather,
				states.states_at(unit.movement.cell)))
	return hits


# The faction's END OF TURN as it stands once `plan` has played (#1428): the plan's own rows for every
# unit it spoke for (ResolvedPlan.end_of_turn_subjects, predicted from where the pass leaves them), and
# the live rows above for the rest of the faction -- nothing the plan does reaches them, so the board
# as it stands IS their end of turn. Two derivations of one composition, declared: the plan answers for
# its subjects, the live board for everyone else. What the board's health bars read; the queue keeps
# the plan's rows alone (#1353). `plan` may be null, or another faction's, and then answers for nobody.
static func forecast(units: Array[Unit], states: TerrainStateManager, gas: GasField,
		weather: Weather.Kind, faction: Team.Faction, plan: ResolvedPlan) -> Array[TileHitAction]:
	var hits: Array[TileHitAction] = []
	# Instance ids rather than Unit keys: a plan can outlive a unit it named, and a freed Unit dies on a
	# typed key's check before any guard could run (#149).
	var settled: Dictionary[int, bool] = {}
	if plan != null:
		for unit in plan.end_of_turn_subjects:
			if is_instance_valid(unit) and unit.get_faction() == faction:
				settled[unit.get_instance_id()] = true
		for hit in plan.tile_hits:
			if is_instance_valid(hit.actor) and settled.has(hit.actor.get_instance_id()):
				hits.append(hit)
	var rest: Array[Unit] = []
	for unit in units:
		if is_instance_valid(unit) and not settled.has(unit.get_instance_id()):
			rest.append(unit)
	hits.append_array(tile_hits(rest, states, gas, weather, faction))
	return hits


# Per-unit state that decays at the owning faction's turn start (downed clocks, crisis surge,
# weapon rev, …). One pass; each tick self-guards, so no per-effect pre-filter. Add a new
# turn-start tick as one line here — both stacks call this, so it reaches each at once.
static func turn_start_ticks(units: Array[Unit], faction: Team.Faction) -> void:
	for unit in units:
		if unit.get_faction() != faction:
			continue
		unit.tick_downed_countdown()
		unit.tick_stat_effects()      # BEFORE the surge below: an effect applied this turn must not tick this turn
		unit.advance_crisis_surge()
		unit.tick_carried_revs()      # every carried weapon, not just the one in hand (#1357)
		unit.lapse_guard()            # #414: last turn's Guard is gone BEFORE this turn's move phase
		unit.lapse_watch()            # #413: and so is last turn's untriggered watch


# What a faction's turn start comes to (#1365): it plays, it is passed over, or the mission ended.
enum Start { PLAY, SKIP, OVER }

# THE HAND-OFF RULE, one for both hosts (#1365): the ticks, the squads they split, the mission check
# AFTER both (an expiring downed clock is the one death outside a pass, #96), then the empty-faction
# skip, then the action reset (#144: a hand-off resets, a menu arrival trusts the file). The headless
# stack kept its own copy of the skip and the AI loop's hand-off had none, so a downed AI faction
# took a turn there and burned. `mission_ends` is the host's own check, since the game's also raises
# its banner. On SKIP the host hands off again; the guard on has_active_units keeps an all-downed
# sandbox board inert rather than looping.
static func start_turn(faction: Team.Faction, units: Array[Unit], squad_manager: SquadManager,
		mission_ends: Callable) -> Start:
	turn_start_ticks(units, faction)
	squad_manager.enforce_contact()
	if mission_ends.call():
		return Start.OVER
	var board: BoardContext = squad_manager.board_source.call()
	if not board.faction_has_active_units(faction) and board.has_active_units():
		return Start.SKIP
	squad_manager.reset_faction_actions(faction)
	return Start.PLAY
