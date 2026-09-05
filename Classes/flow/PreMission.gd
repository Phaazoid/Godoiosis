extends Object
class_name PreMission

# WHO the roster sends into a mission and WHERE each of them stands, before turn 1 (#737). Static
# and pure -- MissionRules' shape, and for MissionRules' reason: two hosts have to reach the same
# answer. The game deploys through game.spawn_unit; the headless Play API (#46) will deploy through
# board_builder's own spawn, and a second copy of this arithmetic living there is the shape that hid
# #714 for as long as it did.
#
# It spawns nothing and touches no board. Two things follow from that and both are contracts:
#
#   * CELLS ARRIVE ALREADY LEGAL. "May a unit stand here" is the HOST's question -- game.can_spawn_at
#     is spawn_unit's own gate, while board_builder.spawn currently refuses nothing at all -- so a
#     legality rule stated here would be a second answer that is wrong on one of the two hosts.
#     The caller filters, this pairs.
#   * NOTHING IS WRITTEN BACK ONTO AN ENTRY. RosterCatalog.resolve serves the CACHED Roster, so its
#     entries are shared sub-resources of a file on disk; filling in `cell` would edit content in
#     memory and the next roster save would write it out. The plan is a separate pairing.
#
# The pre-mission SCREEN is #740's; this is what answers the phase when nobody is there to.

# What a plan row is: an entry and the cell it deploys to. A dict per row rather than two parallel
# arrays, the {severity, text} idiom -- a pairing that cannot come apart.
const ENTRY := "entry"
const CELL := "cell"

# cap 0 = as many as fit, which is ScenarioData.deployment_cap's own default and sentinel (#736).
const NO_CAP := 0


# Entry order decides WHO (the roster file is the author's own ordering), reading order decides
# WHERE. The three limits compose: the roster cannot send more than it holds, the cap cannot send
# more than it allows, and the zone cannot take more than it has room for.
static func deployment_plan(entries: Array[ScenarioUnitEntry], cells: Array[Vector2i],
		cap: int) -> Array[Dictionary]:
	var usable: Array[ScenarioUnitEntry] = []
	for entry: ScenarioUnitEntry in entries:
		# RosterLint reports an empty entry at DEGRADES, so one can legitimately reach here in a
		# file the author has not finished. Mirrors ScenarioManager.valid_entries' rule, quietly:
		# the lint is where that gets said out loud.
		if entry == null or entry.unit_data == null:
			continue
		usable.append(entry)

	var ordered: Array[Vector2i] = cells.duplicate()
	ordered.sort_custom(_reading_order)

	var limit: int = usable.size()
	if cap > NO_CAP:
		limit = mini(limit, cap)
	limit = mini(limit, ordered.size())

	var plan: Array[Dictionary] = []
	for i in range(limit):
		plan.append({ENTRY: usable[i], CELL: ordered[i]})
	return plan


# Top-left first, rows before columns. The zone store's own order is insertion order x paint order
# -- stable for one file, but a function of the order the author happened to drag in, which is not
# something anyone can reason about while authoring. Reading order is.
static func _reading_order(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x if a.y == b.y else a.y < b.y
