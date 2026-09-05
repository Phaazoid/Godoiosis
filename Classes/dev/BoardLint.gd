extends Object
class_name BoardLint

# "Is this board actually playable?" -- the one answer to that question (#390), asked on demand from
# Scenario > Properties and again in CI over every shipped mission (tests/dev/test_board_lint.gd).
#
# Every fault here is an AUTHORING mistake, never a code bug: the game does exactly what the board
# says, and the board says something the author didn't mean. Nearly all of them are entirely silent
# (the unwinnable objective is the one that shouts, and only into the console), so before this page
# existed they were found by PLAYING the mission and noticing something wrong.
#
# This class BORROWS every rule it can rather than restating one -- objectives_missing_geometry,
# spawn_unit's walkability pair, SquadManager.contact_breaks, LookKnobs.saved_presets -- so a rule
# change lands here for free and the lint can never drift from the behaviour it warns about. The one
# rule that LIVES here is the ai_factions check, which moved out of
# tests/flow/test_scenario_load_integrity.gd the moment this file gave it a second reader. Note its
# SCOPE stayed at the caller rather than moving with it: the test only ever asked it of boards under
# missions/, and the button asks it of whatever is in your hands.
#
# It reads the LIVE BOARD, not a saved file, and for the placement check that is load-bearing:
# apply_scenario DROPS a unit whose cell spawn refuses, so a board that has been through a load has
# already lost the evidence. The file-shaped half of that question -- did this load lose anyone? --
# cannot be a finding here and is a CI case instead.

# How bad is it? BLOCKS means the mission is not the mission you authored; DEGRADES means it plays
# -- either something you set up quietly stops existing, or the board is set up a way you may not
# have meant. Two tiers rather than a flat list because a report that buries "unwinnable" under
# "wrong lighting" is a report you skim.
#
# ONLY BLOCKS REDS CI. test_every_shipped_mission_is_playable collects this tier and nothing else,
# so putting a rule here declares that no shipped board may ever be in that state. A rule the dev
# can legitimately WANT to be in belongs at DEGRADES, however loud it deserves to be -- see
# _check_ai_factions. Nothing outside the report panel reads either tier: BLOCKS refuses no save
# and gates no play, unlike AttackLint's, so the tier is a VOLUME control plus that CI gate.
enum Severity { BLOCKS, DEGRADES }


# One row per fault: {"severity": Severity, "text": String}. Empty means nothing found -- which is
# a RESULT, and the panel says so out loud.
static func check(game) -> Array[Dictionary]:
	var board: BoardContext = game._board()
	var found: Array[Dictionary] = []

	_check_objectives(game, found)
	_check_lose_conditions(game, found)
	_check_ai_factions(game, board, found)
	_check_placement(game, board, found)
	_check_cohesion(game, found)
	_check_look_preset(game, found)
	_check_roster(game, found)
	_check_deployment(game, found)
	_check_dialog(game, board, found)
	_check_repaired_content(found)

	# Ordered by severity here, not at the panel: a second reader would otherwise have to re-derive
	# the running order, and the order IS part of what the report says. Grouping by a pass over the
	# enum rather than sort_custom, which Godot does not promise to keep stable.
	var ordered: Array[Dictionary] = []
	for severity in [Severity.BLOCKS, Severity.DEGRADES]:
		for finding: Dictionary in found:
			if finding["severity"] == severity:
				ordered.append(finding)
	return ordered




# Content that only loaded because ContentRepair took a dangling reference OUT of it (#608). It is
# the one finding here that is not about the board's own authoring -- it is about the board being a
# DEGRADED copy of what was authored, which nothing else on screen would say. DEGRADES rather than
# BLOCKS on purpose: the mission is playable and, more to the point, reachable, which is the entire
# reason the repair exists. Fixing it means restoring the missing file or setting the property.
static func _check_repaired_content(found: Array[Dictionary]) -> void:
	for path: String in ContentRepair.repaired_paths():
		var lost := ContentRepair.dropped_properties(path)
		var missing := ContentRepair.missing_targets(path)
		if lost.is_empty() and missing.is_empty():
			continue
		_add(found, Severity.DEGRADES,
			"%s loaded WITHOUT %s -- %s could not be found. Saving it now writes that loss into the file."
			% [path.get_file(), ", ".join(lost), ", ".join(missing)])

static func _add(found: Array[Dictionary], severity: Severity, text: String) -> void:
	found.append({"severity": severity, "text": text})


# A declared objective with nothing painted for it reads PENDING forever. MissionController owns
# the rule and shouts it once at load; the Properties page shows it live while you tick the boxes.
# This is its third reader and still not a third answer.
static func _check_objectives(game, found: Array[Dictionary]) -> void:
	var mission: MissionController = game.mission_controller
	for objective: MissionRules.Objective in mission.objectives_missing_geometry():
		_add(found, Severity.BLOCKS,
			"Objective %s is declared but no matching zone is painted -- this mission cannot be won."
				% MissionRules.Objective.keys()[objective])


# _check_objectives' twin one list over (#101): a lose condition declared with no parameter fires
# the moment the mission starts. BLOCKS for the same reason -- a board lost on round one is not the
# board that was authored. Same borrowed-rule discipline; MissionController owns it.
static func _check_lose_conditions(game, found: Array[Dictionary]) -> void:
	var mission: MissionController = game.mission_controller
	for condition: MissionRules.LoseCondition in mission.lose_conditions_missing_setup():
		_add(found, Severity.BLOCKS,
			"Lose condition %s is declared but nothing is set for it -- this mission would be lost immediately."
				% MissionRules.LoseCondition.keys()[condition])


# #150, and the one rule this file owns. Commanding is gated on faction == active faction, so a
# board that doesn't hand ENEMY to the computer doesn't stall on the enemy turn -- you play both
# sides. Scoped to ENEMY exactly as the test that used to hold this was: NEUTRAL and ALLY AI
# stances are still undecided, so there is nothing to be wrong about yet.
#
# DEGRADES, NOT BLOCKS -- playing both sides is a THING THE DEV WANTS, not a fault (2026-08-26,
# after this red-ed main on a freshly authored Level_2): "I want to be able to have levels with no
# AI. controlling both sides is important to testing. If the tests and lint are redding that out,
# they should be warnings, not hard stops." So an AI-less board must SHIP. It cannot be BLOCKS and
# it cannot be silent either: ai_factions defaults to EMPTY, so a board the dev never thought about
# and a board he chose look identical from here -- there is no flag that says "I meant it", which
# is exactly why this reports rather than decides. Say it once, in amber, and let him ignore it.
static func _check_ai_factions(game, board: BoardContext, found: Array[Dictionary]) -> void:
	var enemies := 0
	for unit: Unit in board.units:
		if is_instance_valid(unit) and unit.get_faction() == Team.Faction.ENEMY:
			enemies += 1
	if enemies == 0:
		return
	var ai_controller: AIController = game.ai_controller
	if ai_controller.ai_factions().has(Team.Faction.ENEMY):
		return
	_add(found, Severity.DEGRADES,
		("%d ENEMY unit%s on this board, but ENEMY is not computer-controlled -- you will play "
			+ "both sides. Deliberate on a hotseat or test board; if it isn't, tick it on "
			+ "Scenario > Squads & AI.")
			% [enemies, "" if enemies == 1 else "s"])


# A unit standing where spawn would refuse it. Only reachable by painting terrain UNDER a unit that
# is already there (or erasing the tile), because spawn_unit guards both halves at placement time --
# which is also why this can only be caught while authoring: the next load simply drops the unit.
#
# Asked in spawn_unit's own order (off the map first, then walkability), through the same two calls,
# so dev placement and this warning cannot disagree about which cells are legal.
static func _check_placement(game, board: BoardContext, found: Array[Dictionary]) -> void:
	var grid: BoardGrid = game.grid
	for unit: Unit in board.units:
		if not is_instance_valid(unit):
			continue
		var cell: Vector2i = unit.movement.cell
		var reason := ""
		if grid.get_cell_tile_data(cell) == null:
			reason = "off the map"
		elif not board.is_walkable(cell) and not unit.is_downed():
			# A BODY is exempt (#116), the same exception spawn_unit takes: is_walkable answers "may
			# a unit STAND here", and a drowning unit legitimately lies where nothing stands. Asked
			# through is_downed rather than a saved flag so the button reads the LIVE board, which is
			# this check's whole reason for existing.
			reason = "a cell nothing may stand on"
		if reason == "":
			continue

		var text := "%s stands %s at %s -- this unit is DROPPED every time the board loads." % [
			unit.get_unit_name(), reason, cell]
		# The leaderless-squad case, which has no separate check because it has no separate cause:
		# apply_scenario's "saved without a leader -> leave them as solos" branch is reachable ONLY
		# through a dropped leader, so it is this finding wearing its full consequence rather than
		# a sixth one that could never fire on a live board.
		if unit.is_leader() and unit.squad != null and unit.squad.members.size() > 1:
			var squad_label: String = unit.squad.squad_name if unit.squad.squad_name != "" else "its squad"
			var others: int = unit.squad.members.size() - 1
			text += " It leads %s, whose other %d member%s become solos when it goes." % [
				squad_label, others, "" if others == 1 else "s"]
		_add(found, Severity.BLOCKS, text)


# A member the leader cannot reach within COH. apply_scenario's join_squad is ungated so the board
# loads looking correct, and then the loss-of-contact sweep ejects them the first time that squad
# acts -- the squad you authored quietly stops being one, mid-playtest. contact_breaks() is the
# sweep's own predicate, which is the point: warn with the rule that will do it, not a copy.
static func _check_cohesion(game, found: Array[Dictionary]) -> void:
	var squad_manager: SquadManager = game.squad_manager
	for member: Unit in squad_manager.contact_breaks():
		var leader: Unit = member.squad.leader
		_add(found, Severity.DEGRADES,
			("%s cannot reach %s over terrain it can cross -- it is ejected into a solo squad the "
				+ "first time that squad acts.") % [member.get_unit_name(), leader.get_unit_name()])


# A named look preset that no longer resolves. The board still plays, so DEGRADES -- it just opens
# wearing the default. saved_presets() is the same question the Properties dropdown asks to decide
# whether to keep a stale name selectable; resolve() is deliberately NOT called here, since its
# whole job is to push_error and fall back and a lint must not have side effects.
static func _check_look_preset(game, found: Array[Dictionary]) -> void:
	var scenario_manager: ScenarioManager = game.scenario_manager
	var preset: String = scenario_manager.current_look_preset
	if preset == "" or LookKnobs.saved_presets().has(preset):
		return
	_add(found, Severity.DEGRADES,
		"This board names look preset '%s', which no longer exists -- it opens with the default look."
			% preset)


# A named roster that no longer resolves (#735). BLOCKS, where the look preset directly above is
# DEGRADES, and the difference is the whole reason they are separate rules: a board with no look
# wears the default and plays exactly as authored, while a board whose pool cannot be found has no
# pool -- the pre-mission phase would offer nobody. Substituting some other roster would hand the
# player a different mission, so RosterCatalog.resolve has no default to fall back to.
#
# saved_rosters() rather than resolve(), for _check_look_preset's reason one rule up: resolve's job
# is to push_error, and a lint must not have side effects. It is also the same question the
# Properties dropdown asks, so a name the row offers is always a name this accepts.
static func _check_roster(game, found: Array[Dictionary]) -> void:
	var scenario_manager: ScenarioManager = game.scenario_manager
	var roster: String = scenario_manager.current_roster
	if roster == "" or RosterCatalog.saved_rosters().has(roster):
		return
	_add(found, Severity.BLOCKS,
		("This board names roster '%s', which does not exist -- the pre-mission phase has no units "
		+ "to offer.") % roster)


# The roster's other half (#736): a board that offers a pool has to say where that pool may stand,
# and how much of it may come. Both faults are one rule because they are one question asked at two
# depths, and the roster gate is what makes either mean anything -- a cap on a board with no pool
# caps nothing, so it is not a finding.
#
# The no-zone half is BLOCKS as of #737, raised from the DEGRADES #736 filed it at -- and the tier
# moving is the rule working, not a reversal of it. A tier is judged against WHAT THE CODE IN THIS
# TREE DOES with the board, and #736's tree read no roster at all, so such a board booted with its
# authored cast and played exactly as before. Now the draw is real: no zone means nobody deploys,
# and a board whose player force IS the roster then opens on a turn with nothing to command --
# _on_turn_started's auto-skip bounces PLAYER to ENEMY forever, and MissionRules.is_contested never
# latches because it needs an active player unit, so there is no defeat either. No win, no loss,
# only Quit. That is _check_objectives' own shape: declared, with no geometry to satisfy it.
#
# The cap half stays DEGRADES: fewer units deploy than the author asked for, and the board plays.
#
# The tier the SIBLING sits at is a different question, and _check_roster above stays BLOCKS on a
# distinction worth keeping written down: a dangling NAME is never a state anyone authors on
# purpose -- it is a typo or a deletion -- where a roster named before its zone is painted is a
# state every authoring session passes through. That is _check_ai_factions' "a thing the dev WANTS"
# argument, and it is why the two were ever at different tiers.
#
# Note the interaction: this asks only whether a roster is NAMED, so a board naming a missing
# roster reports both findings. That is correct -- they are different faults and each needs fixing.
static func _check_deployment(game, found: Array[Dictionary]) -> void:
	var scenario_manager: ScenarioManager = game.scenario_manager
	if scenario_manager.current_roster == "":
		return
	var zones: ZoneManager = game.zone_manager
	# The DEDUPED union, not a sum over the zones: deployment areas may overlap like any others,
	# and a cap compared against a double-counted total is a cap compared against nothing.
	var cells: Array[Vector2i] = zones.cells_of_kind(ZoneManager.Kind.DEPLOYMENT)
	if cells.is_empty():
		_add(found, Severity.BLOCKS,
			("This board offers roster '%s' but paints no Deployment zone -- nobody deploys, so if "
			+ "the roster IS this mission's force it opens with nothing to command. Paint one on "
			+ "the Tile Brush tab.") % scenario_manager.current_roster)
		return
	var cap: int = scenario_manager.current_deployment_cap
	if cap > 0 and cap > cells.size():
		_add(found, Severity.DEGRADES,
			("This board lets %d units deploy into a zone of %d cells -- only %d of them can "
			+ "actually stand there.") % [cap, cells.size(), cells.size()])


# #397, the two checks deferred from #390. Both read the SAME stores the director reads
# (ScenarioManager's current_dialog_beats/current_tutorial_steps), so every fault here is
# reachable from the surface that misbehaves -- a check against a saved file would miss the
# unsaved edits the dev-tools page makes.
static func _check_dialog(game, board: BoardContext, found: Array[Dictionary]) -> void:
	for beat: DialogBeat in game.scenario_manager.current_dialog_beats:
		if beat.timeline == null:
			_add(found, Severity.DEGRADES,
				"A dialog beat (%s) has no timeline -- it fires into nothing."
					% DialogBeat.Trigger.keys()[beat.trigger])

	# The name check is authored-time advice: mid-battle, a named unit may legitimately be gone
	# (dead, extracted), so past the opening turn of an ARMED battle it stays quiet (dev call,
	# #397). An un-armed board is an authoring session and always gets checked -- the dev-tools
	# Load path never arms.
	if game.scenario_director.past_opening_turn():
		return
	var names: Dictionary = {}
	for unit: Unit in board.units:
		if is_instance_valid(unit) and unit.unit_data != null:
			names[unit.unit_data.display_name] = true
	for step: TutorialStep in game.scenario_manager.current_tutorial_steps:
		if step.unit_name != "" and not names.has(step.unit_name):
			_add(found, Severity.BLOCKS,
				("A tutorial step names '%s', but no unit on this board carries that name -- "
					+ "the step can never complete and the lesson stalls there.") % step.unit_name)
