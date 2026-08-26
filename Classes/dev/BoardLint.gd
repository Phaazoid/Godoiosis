extends Object
class_name BoardLint

# "Is this board actually playable?" -- the one answer to that question (#390), asked on demand from
# Scenario > Properties and again in CI over every shipped mission (tests/dev/test_board_lint.gd).
#
# Every fault here is an AUTHORING mistake, never a code bug: the game does exactly what the board
# says, and the board says something the author didn't mean. Four of the five are entirely silent
# and the fifth only shouts into the console, so all of them were previously found by PLAYING the
# mission and noticing something wrong.
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
# but something you set up quietly stops existing. Two tiers rather than a flat list because a
# report that buries "unwinnable" under "wrong lighting" is a report you skim.
enum Severity { BLOCKS, DEGRADES }


# One row per fault: {"severity": Severity, "text": String}. Empty means nothing found -- which is
# a RESULT, and the panel says so out loud.
static func check(game) -> Array[Dictionary]:
	var board: BoardContext = game._board()
	var found: Array[Dictionary] = []

	_check_objectives(game, found)
	_check_ai_factions(game, board, found)
	_check_placement(game, board, found)
	_check_cohesion(game, found)
	_check_look_preset(game, found)
	_check_dialog(game, board, found)

	# Ordered by severity here, not at the panel: a second reader would otherwise have to re-derive
	# the running order, and the order IS part of what the report says. Grouping by a pass over the
	# enum rather than sort_custom, which Godot does not promise to keep stable.
	var ordered: Array[Dictionary] = []
	for severity in [Severity.BLOCKS, Severity.DEGRADES]:
		for finding: Dictionary in found:
			if finding["severity"] == severity:
				ordered.append(finding)
	return ordered


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


# #150, and the one rule this file owns. Commanding is gated on faction == active faction, so a
# board that doesn't hand ENEMY to the computer doesn't stall on the enemy turn -- it hands the
# player its own enemies. Scoped to ENEMY exactly as the test that used to hold this was: NEUTRAL
# and ALLY AI stances are still undecided, so there is nothing to be wrong about yet.
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
	_add(found, Severity.BLOCKS,
		("%d ENEMY unit%s on this board, but ENEMY is not computer-controlled -- the player is "
			+ "handed its own enemies. Tick it on Scenario > Squads & AI.")
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
