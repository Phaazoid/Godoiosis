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
#   * CELLS ARRIVE ALREADY LEGAL. "May a unit stand here" is the HOST's question, asked through ONE
#     rule both hosts share since #46 (RulesService.can_spawn_at) -- so a legality rule stated here
#     would be a second answer. The caller filters, this pairs. The phase that drives this walk on
#     either host is PreMissionPhase.
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
#
# A FORCED entry is chosen before anyone else (#1456), inside the same limits: the cap counts it like
# anyone. Once chosen, everybody goes back to ENTRY order for the cells, so a VIP last in the file
# takes the last cell rather than displacing the whole line-up by one.
static func deployment_plan(entries: Array[ScenarioUnitEntry], cells: Array[Vector2i],
		cap: int) -> Array[Dictionary]:
	var usable := _usable(entries)

	var ordered: Array[Vector2i] = cells.duplicate()
	ordered.sort_custom(_reading_order)

	var limit: int = usable.size()
	if cap > NO_CAP:
		limit = mini(limit, cap)
	limit = mini(limit, ordered.size())

	# By INDEX, not by entry: a hand-edited file listing one sub-resource twice still spends two slots.
	var forced := forced_entries(usable)
	var chosen: Array[int] = []
	for i in usable.size():
		if chosen.size() < limit and forced.has(usable[i]):
			chosen.append(i)
	for i in usable.size():
		if chosen.size() >= limit:
			break
		if not chosen.has(i):
			chosen.append(i)
	chosen.sort()

	var plan: Array[Dictionary] = []
	for k in chosen.size():
		plan.append({ENTRY: usable[chosen[k]], CELL: ordered[k]})
	return plan


# WHO the roster sends no matter what (#1456): a VIP. If they fall the mission is lost, so the player
# may not leave them behind (dev: "If the VIP comes from the roster, they should be forced to be
# selected"). The ONE reading of a roster for that question -- the walk above, the protect setup
# guard and Check board all ask it. Once drawn, the same fact is the unit's own must_survive, which
# PreMissionPhase.is_forced reads.
static func forced_entries(entries: Array[ScenarioUnitEntry]) -> Array[ScenarioUnitEntry]:
	var forced: Array[ScenarioUnitEntry] = []
	for entry: ScenarioUnitEntry in _usable(entries):
		if entry.must_survive:
			forced.append(entry)
	return forced


static func _usable(entries: Array[ScenarioUnitEntry]) -> Array[ScenarioUnitEntry]:
	var usable: Array[ScenarioUnitEntry] = []
	for entry: ScenarioUnitEntry in entries:
		# RosterLint reports an empty entry at DEGRADES, so one can legitimately reach here in a
		# file the author has not finished. Mirrors ScenarioManager.valid_entries' rule, quietly:
		# the lint is where that gets said out loud.
		if entry == null or entry.unit_data == null:
			continue
		usable.append(entry)
	return usable


# Top-left first, rows before columns. The zone store's own order is insertion order x paint order
# -- stable for one file, but a function of the order the author happened to drag in, which is not
# something anyone can reason about while authoring. Reading order is.
static func _reading_order(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x if a.y == b.y else a.y < b.y
