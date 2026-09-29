extends Object
class_name TurnBoundary

# The RULE half of a turn boundary (#898, first found by #110): who burns at a faction's end of turn
# and what ticks at its start. Static, and called by both game.gd and the headless Play API, so a new
# tick cannot land in one stack only. The round tick is one call and stays in each stack's handler.


# Who the end-of-turn burn is about, answered ONCE before any of it plays -- the same TileHitAction
# the queue forecasts (#419), derived here from LIVE positions and tile state instead of the plan's
# projected ones. Two derivations of one rule: a plan is per-SQUAD and this phase is per-FACTION, so
# neither can consume the other's list -- what they share is RulesService.occupant_damage_for and
# TileHitAction.make. That rule is TWO layers since #892: what the ground charges
# (Terrain.occupant_damage) and whether this unit pays it (fire insulation), and BOTH callers must
# ask the outer one or an immune unit gets a forecast that lies about it.
#
# Walks UNITS rather than burning cells, which is what keeps it symmetric with the forecast: both
# ask "what is under this unit", so a hazard family the forecast can see cannot be one this misses.
static func tile_hits(units: Array[Unit], states: TerrainStateManager,
		faction: Team.Faction) -> Array[TileHitAction]:
	var hits: Array[TileHitAction] = []
	for unit in units:
		if unit == null or not is_instance_valid(unit) or unit.get_faction() != faction:
			continue
		var cell_states := states.states_at(unit.movement.cell)
		var damage := RulesService.occupant_damage_for(unit, cell_states)
		if damage > 0:
			hits.append(TileHitAction.make(unit, Terrain.burning_state(cell_states), damage,
					LethalityRules.situation_for(unit)))
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
		unit.tick_weapon_rev()
		unit.lapse_guard()            # #414: last turn's Guard is gone BEFORE this turn's move phase
		unit.lapse_watch()            # #413: and so is last turn's untriggered watch
