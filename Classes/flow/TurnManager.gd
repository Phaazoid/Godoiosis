extends Node2D
class_name TurnManager

# Whose turn it is right now, tracked by VALUE (not a list index) so the live cycle can be rebuilt
# underneath us without the pointer going stale. `turn_order` is just the last cycle we computed.
var active: Team.Faction = Team.Faction.PLAYER
var turn_order: Array[Team.Faction] = []

signal turn_started(faction: Team.Faction)

func active_faction() -> Team.Faction:
	return active

# Scenario load restores whose turn it was. Pure state set — works before any cycle is built and
# independent of who's currently on the map.
func set_active_faction(faction: Team.Faction):
	active = faction

# Hand off to the next faction. The caller passes the factions currently on the board; we rebuild
# the live cycle and step past the active one. Wiped factions are absent from `present`, so they
# drop out for free; a faction that appeared this turn is included.
func end_turn(present_factions: Array[Team.Faction]):
	turn_order = _build_cycle(present_factions)
	if turn_order.is_empty():
		return
	var i := turn_order.find(active)               # -1 if the active faction was wiped on its own turn
	active = turn_order[(i + 1) % turn_order.size()]
	turn_started.emit(active)

# The live order: every declared faction (Team.all_factions, enum order) that has a unit on the
# board right now. One source of truth — the Team.Faction enum.
func _build_cycle(present_factions: Array[Team.Faction]) -> Array[Team.Faction]:
	var cycle: Array[Team.Faction] = []
	for faction in Team.all_factions():
		if present_factions.has(faction):
			cycle.append(faction)
	return cycle
