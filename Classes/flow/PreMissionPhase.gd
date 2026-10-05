extends RefCounted
class_name PreMissionPhase

# The pre-mission phase's STATE and RULES (#46): the roster drawn into reserve, who stands where,
# the cap, a reposition, the restart snapshot. TWO HOSTS run one -- the game, through
# MissionController, and the headless Play API, through PlaySession -- so this lives in neither,
# for the reason PreMission's pure walk does: a second copy in play/ is the shape that hid #714.
#
# What differs per host is how a unit is put on a board, and the HOST answers that, duck-typed on
# six calls: spawn_reserve_unit(data), deploy_unit(unit, cell), undeploy_unit(unit),
# is_deployed(unit), can_spawn_at(cell) and get_unit_at_cell(cell). game.gd has all six by name.
# Everything presentational -- the screen, the HUD, the briefing, the banner -- stays with the
# game's own host, MissionController.

# The roster in ENTRY ORDER, which the restart buffer's rows are indexed by (#763). Node order cannot
# serve: deploying and undeploying REPARENT between the board and the reserve.
var units: Array[Unit] = []
# The phase's LIVE gear (#741) -- the stash as copies, so a move out of it never depletes the
# authored Roster sitting in Godot's resource cache.
var loadout: Loadout = Loadout.new()

var _host   # duck-typed: see the header
var _zones: ZoneManager
var _squads: SquadManager
# Read live rather than held, as MissionController always read scenario_manager's.
var _cap_source: Callable


func _init(host = null, zone_manager: ZoneManager = null, squad_manager: SquadManager = null,
		cap_source: Callable = Callable()) -> void:
	_host = host
	_zones = zone_manager
	_squads = squad_manager
	_cap_source = cap_source


func cap() -> int:
	return int(_cap_source.call()) if _cap_source.is_valid() else PreMission.NO_CAP


# The phase's DRAW (#737). The WHOLE roster spawns into reserve (#738) and as many as the cap allows
# stand on the DEPLOYMENT zone (#736). Returns how many stood up.
#
# TWO ENDINGS SINCE #763, and only the reserve draw is shared: the authored walk is what a mission
# opens on, and a RESTART of a mission the player has committed once replays what they chose.
# Where this is CALLED is the host's design, not this file's -- see MissionController.deploy_roster.
func draw(roster_name: String, staged: PreMissionSnapshot = null) -> int:
	# "" resolves to null: every board with no pre-mission phase. A NAMED roster that will not
	# resolve push_errors and is a BLOCKS finding on Check board.
	var roster: Roster = RosterCatalog.resolve(roster_name)
	if roster == null:
		return 0
	# RESOLVED ONCE and passed to both walks (#812): offered_entries() SYNTHESIZES entries under
	# "every character", and _stand_authored keys unit_of_entry BY THE ENTRY.
	var entries: Array[ScenarioUnitEntry] = roster.offered_entries()
	var unit_of_entry: Dictionary = _draw_reserve(roster, entries)

	var deployed := 0
	if staged != null and staged.fits(units):
		deployed = _stand_staged(staged)
		if deployed == 0:
			# Every staged cell refused -- the zone was repainted under the buffer. _stand_staged
			# bails before applying any of it, so the authored walk below is a clean second answer.
			push_warning("Pre-mission: no staged cell is open any more -- drawing the mission's own")
	if deployed == 0:
		deployed = _stand_authored(entries, unit_of_entry)
	return deployed


# The DEPLOYMENT cells a unit could actually be put on, right now -- the draw asks it once and every
# placement asks it again (#739), so "where may a unit stand" is one answer. Legality is the host's
# can_spawn_at, which is spawn_unit's own gate (RulesService.can_spawn_at on both hosts).
func open_deployment_cells() -> Array[Vector2i]:
	var open_cells: Array[Vector2i] = []
	if _zones == null:
		return open_cells
	for cell: Vector2i in _zones.cells_of_kind(ZoneManager.Kind.DEPLOYMENT):
		if _host.can_spawn_at(cell):
			open_cells.append(cell)
	return open_cells


# Where this unit could stand instead (#772): the zone's cells minus its own, keeping a FREE cell and
# one another ROSTER-DRAWN unit holds (a swap, dev 2026-09-05). Authored units are not swappable --
# they are the board's, additive to the draw (#731 ruling 2c).
func reposition_cells(unit: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if unit == null or not unit.drawn_from_roster or _zones == null:
		return cells
	for cell: Vector2i in _zones.cells_of_kind(ZoneManager.Kind.DEPLOYMENT):
		if cell == unit.movement.cell:
			continue
		if _host.can_spawn_at(cell):
			cells.append(cell)
			continue
		var occupant: Unit = _host.get_unit_at_cell(cell)
		if occupant != null and occupant.drawn_from_roster:
			cells.append(cell)   # a swap
	return cells


# Move a placed unit inside the zone, trading places with whoever is there, THEN THE SQUAD SETTLES
# (dev, 2026-09-05): the phase is a third settle point, so an ejection lands while the player is
# still looking at the board that caused it. set_cell, not deploy_unit: the unit is already on it.
func reposition(unit: Unit, cell: Vector2i) -> bool:
	if unit == null or not unit.drawn_from_roster:
		return false
	if not reposition_cells(unit).has(cell):
		return false
	var from := unit.movement.cell
	var occupant: Unit = _host.get_unit_at_cell(cell)
	unit.movement.set_cell(cell)
	if occupant != null:
		occupant.movement.set_cell(from)   # the swap: both ends move, then the squads settle ONCE
	_squads.enforce_contact()
	return true


# How many of the ROSTER are standing on the board -- what the cap counts. Authored units are not
# the roster's and never count against it (ruling 2c).
func deployed_count() -> int:
	var count := 0
	for unit: Unit in units:
		if is_instance_valid(unit) and _host.is_deployed(unit):
			count += 1
	return count


# Room under the cap for one more? `0` is the cap's own "as many as fit" sentinel (#736); the ZONE is
# the other limit and enforces itself, since a full zone offers no open cell.
func can_deploy_another() -> bool:
	var limit := cap()
	return limit == PreMission.NO_CAP or deployed_count() < limit


# Why one more cannot be placed, or "" -- the card's sentence (#743), moved here so both hosts refuse
# in the same words.
func deploy_block_reason() -> String:
	if not can_deploy_another():
		return "Your force is full — %d of %d placed. Take someone off first." % [deployed_count(), cap()]
	if open_deployment_cells().is_empty():
		return "The deployment zone has no free cell left."
	return ""


# Why the phase cannot end yet, or "" (#739): a mission cannot start with no force.
func commit_block_reason() -> String:
	return "Deploy someone first" if deployed_count() == 0 else ""


# The capture (#763), taken at the commit. EVERY DRAWN UNIT gets a row, standing or waiting, because
# who was left in reserve, carrying what, is as much a choice as where the rest are.
func capture(mission_path: String) -> PreMissionSnapshot:
	var snapshot := PreMissionSnapshot.new()
	snapshot.mission_path = mission_path
	for unit: Unit in units:
		var entry := ScenarioUnitEntry.new()
		# The character FILE, which is what fits() compares -- never unit.unit_data, a per-unit copy.
		entry.unit_data = unit.unit_data_source
		entry.capture_unit_state(unit)
		var standing: bool = _host.is_deployed(unit)
		snapshot.deployed.append(standing)
		if standing:
			# Asked ONLY of a standing unit: undeploy takes the grid and the squad away.
			entry.cell = unit.movement.cell
			entry.squad_id = _squads.squads.find(unit.squad)
			entry.is_leader = unit.is_leader()
		snapshot.entries.append(entry)
	for item: Item in loadout.stash:
		snapshot.stash.append(item.copy_for_grant())
	return snapshot


# Does the phase OPEN (#46): the mission offers the screen (ScenarioData.offers_pre_mission) and the
# draw stood somebody up. The one rule both hosts' fresh-start doors ask. Closed, the draw's authored
# placement stands and the battle begins.
static func opens(offered: bool, drawn: int) -> bool:
	return offered and drawn > 0


# The buffer, but only if it describes THIS board -- the reason no mission door has to remember to
# clear one (#763 ruling 1). Every fresh start of a mission asks, on both hosts; the answer for a
# mission not committed once in this session is null, which is the authored draw.
#
# And only if the board OFFERS the screen (#46): a loadout committed while the box was ticked would
# otherwise stand again, silently, on a board whose player can no longer see or change it. Required
# rather than defaulted, so no door can forget to ask.
static func replay_for(buffer: PreMissionSnapshot, path: String, offered: bool) -> PreMissionSnapshot:
	if not offered or buffer == null or buffer.mission_path != path or path == "":
		return null
	return buffer


# What a RESTART leaves of the buffer (#763 ruling 2): one taken from inside the phase drops it, since
# that is the player's way back to the authored draw (the pause row reads Reset Loadout there). The
# host must ask BEFORE its reload, while it still knows it was in the phase.
static func kept_by_restart(buffer: PreMissionSnapshot, from_inside_phase: bool) -> PreMissionSnapshot:
	return null if from_inside_phase else buffer


# The half BOTH endings need: the whole roster spawns into reserve (#738), so a card is a real Unit
# and every wielder-taking predicate serves it unchanged. Returns entry -> reserve Unit.
func _draw_reserve(roster: Roster, entries: Array[ScenarioUnitEntry]) -> Dictionary:
	var unit_of_entry: Dictionary = {}   # ScenarioUnitEntry -> its reserve Unit
	units.clear()
	loadout = Loadout.from_roster(roster)
	for entry: ScenarioUnitEntry in entries:
		# The same skip PreMission.deployment_plan makes, so the two loops agree about who exists.
		if entry == null or entry.unit_data == null:
			continue
		# Un-duplicated (#177): UnitFactory copies anyway, and an outer duplicate destroys the
		# resource_path a reference entry exists to keep.
		var unit: Unit = _host.spawn_reserve_unit(entry.unit_data)
		# Marked here rather than at deploy, so deploy_unit stays a pure board-entry.
		unit.drawn_from_roster = true
		if entry.state_saved:
			entry.apply_unit_state(unit)   # the snapshot half of #177's fork, same as the loader's
		unit_of_entry[entry] = unit
		units.append(unit)   # entry order, and it must survive every later reparent
	return unit_of_entry


# The mission's OWN opening position: PreMission's pure walk, on cells this host already judged.
func _stand_authored(entries: Array[ScenarioUnitEntry], unit_of_entry: Dictionary) -> int:
	var deployed := 0
	for row: Dictionary in PreMission.deployment_plan(entries, open_deployment_cells(), cap()):
		var entry: ScenarioUnitEntry = row[PreMission.ENTRY]
		var unit: Unit = unit_of_entry.get(entry)
		if unit == null:
			continue
		if not _host.deploy_unit(unit, row[PreMission.CELL]):
			continue   # the cells were filtered, so this is a bug rather than a blocked cell
		# One unit per entry: a hand-edited file listing one sub-resource twice spends a slot quietly.
		unit_of_entry.erase(entry)
		deployed += 1
	return deployed


# ...and the OTHER ending (#763). PLACEMENT FIRST, AND NOTHING ELSE UNTIL IT HAS SUCCEEDED: nobody
# standing means the buffer no longer describes this board, and the caller needs the units untouched
# to redraw. STATE, THEN SQUADS, apply_scenario's order for its reason: a join needs both ends placed.
func _stand_staged(staged: PreMissionSnapshot) -> int:
	var stood := 0
	for i in units.size():
		if not staged.deployed[i]:
			continue
		if _host.deploy_unit(units[i], staged.entries[i].cell):
			stood += 1
		else:
			push_warning("Pre-mission: %s's staged cell %s is no longer open -- left in reserve"
					% [units[i].get_unit_name(), staged.entries[i].cell])
	if stood == 0:
		return 0

	# Over the reserve too: a unit the player stripped and left behind comes back stripped and left
	# behind. apply_unit_state is safe off-board -- it touches inventory, stats and jobs, never a cell.
	for i in units.size():
		staged.entries[i].apply_unit_state(units[i])

	_rejoin_staged_squads(staged)

	# Fresh copies, not the buffer's own objects, or a second restart hands out stash items the first
	# restart's units have been carrying and editing.
	loadout.stash.clear()
	for item: Item in staged.stash:
		loadout.stash.append(item.copy_for_grant())
	return stood


# MEMBERSHIP AND NOTHING ELSE: the phase has four squad verbs and every one is membership. Leaders
# first, members after, because a member's leader may sit later in the draw order.
func _rejoin_staged_squads(staged: PreMissionSnapshot) -> void:
	var leader_of_id: Dictionary = {}    # squad_id -> the Unit that led it
	var members_of_id: Dictionary = {}   # squad_id -> Array[Unit]
	for i in units.size():
		var entry: ScenarioUnitEntry = staged.entries[i]
		# A reserve unit has no squad, so it was captured with no id; one that failed to stand
		# above must not be joined to anything either.
		if entry.squad_id == -1 or not _host.is_deployed(units[i]):
			continue
		if entry.is_leader:
			leader_of_id[entry.squad_id] = units[i]
		else:
			if not members_of_id.has(entry.squad_id):
				members_of_id[entry.squad_id] = []
			members_of_id[entry.squad_id].append(units[i])

	for squad_id: int in members_of_id:
		var leader: Unit = leader_of_id.get(squad_id)
		if leader == null:
			continue   # the leader could not stand; the members keep the solo squads they were given
		for member: Unit in members_of_id[squad_id]:
			_squads.join_squad(member, leader.squad)
