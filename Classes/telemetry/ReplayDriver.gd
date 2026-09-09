extends Node
class_name ReplayDriver

# THE HARNESS (#53 slice 4): seed a board from a recorded run, re-issue every recorded decision
# through the REAL doors, and diff the result against what was recorded. A game collaborator on the
# DevController pattern -- it holds a `game` back-ref and OWNS NO RULE: every order goes through
# SquadManager.queue_action or a game.* door, so the live rules answer and this only asks.
#
# WHY THE REPLAY IS MEASURED BY MissionLog RATHER THAN BY READING THE BOARD: MissionLog is added in
# _build_collaborators, so its turn_started handler connects BEFORE game._on_turn_started and its
# vitals are recorded PRE-TICK -- before downed clocks, stat effects and enforce_contact. Reading
# the live board after a turn hands over compares pre-tick against post-tick and reports a
# divergence on nearly every run. Recording the replay with the same function at the same signal
# position makes the two sides like-for-like by construction, and `pass.hits` then gives a per-HIT
# checksum rather than a per-turn one.
#
# THE DIFF DELIBERATELY IGNORES order_queued / gear / squad_verb: those are this driver's own INPUT,
# so comparing them only asks whether it echoed what it was handed. Comparing them would make the
# report look thorough while testing nothing.

signal progressed(finished: bool)

var game   # untyped: game.gd has no class_name, so every read off it needs an explicit local

var run: ReplayRun = null
var divergences: Array[String] = []
# Recorded ids that no live unit could be bound to -- a mid-run dev spawn is in no roster. Reported
# rather than guessed at, and this is the REAL guard rather than `dev_touched`, which is written
# only at seal and so is absent from any run whose process was killed.
var unbindable: Array[String] = []
var notes: Array[String] = []

var _by_recorded_id: Dictionary = {}   # int (recorded instance id) -> Unit
# THE SAME BINDING AS AN INT PAIR, captured while everyone is alive. A unit that DIES during the
# replay is freed, and slice 4's own law is that an id read later must be a stable VALUE rather than
# a runtime handle -- which is what `MissionLog._ref` was fixed for, and what this map failed the
# same way one file over. The diff runs after the pass, so by then the object map has holes and this
# one does not; a mapping that vanished when a unit died would also report every row naming the
# casualty as a divergence, which is the tool's one job broken quietly.
var _live_id_of: Dictionary = {}       # int (recorded instance id) -> int (live instance id)
var _cursor := 0
var _seen_first_turn := false
var _seeded := false


func is_seeded() -> bool:
	return _seeded


func is_finished() -> bool:
	return _seeded and _cursor >= run.events.size()


# ==============================================================================
#  Seeding
# ==============================================================================

# Puts the recorded board up and arms it exactly as a real mission arrival does, then binds the
# recorded ids. Returns false with a note when the run cannot be replayed at all.
func seed(replay_run: ReplayRun) -> bool:
	run = replay_run
	divergences.clear()
	unbindable.clear()
	notes.clear()
	_by_recorded_id.clear()
	_live_id_of.clear()
	_cursor = 0
	_seen_first_turn = false
	_seeded = false

	if not run.can_replay():
		for problem: String in run.problems:
			notes.append(problem)
		return false

	var scenario_manager = game.scenario_manager
	scenario_manager.apply_scenario(run.board)

	# AFTER the seed, never before: apply_scenario REPLACES the AI set from the board it loads
	# (#150), so a stand-down written first would be overwritten by it. Nothing to restore either --
	# the next board load writes the set again.
	#
	# Every faction's orders are in the log, because queue_action is the Law #3 chokepoint that
	# squad_action_queued fires from. Re-planning the enemy instead would be asking whether the AI
	# is reproducible, which is a different question and tools/replay_battle.gd's.
	var no_ai: Array[Team.Faction] = []
	game.ai_controller.set_ai_factions(no_ai)

	# The real arrival door, so the board is armed identically -- zones redrawn, faction turn
	# started. `false` records the replay IN MEMORY: like-for-like measurement, no run folder.
	var mission_controller = game.mission_controller
	mission_controller._begin_turn(false)

	_bind_units()
	_seeded = true
	return true


# The recorded id is an INSTANCE id and does not survive the process, so it is re-bound by the one
# thing that is stable and already recorded: the cell each unit started on. spawn_unit refuses an
# occupied cell, so a seeded board is exactly one unit per cell and the mapping is unambiguous.
func _bind_units() -> void:
	var start := run.first("mission_start")
	for entry: Dictionary in start.get("roster", []):
		var recorded_id := int(entry.get("id", 0))
		var name_of := str(entry.get("name", "?"))
		if not bool(entry.get("deployed", false)) or entry.get("cell") == null:
			# Undeployed reserve: not on the board, cannot act, and capture_scenario never saved it
			# (it walks units_root). Not a fault -- just nothing to bind.
			continue
		var cell := _cell_of(entry.get("cell"))
		var unit: Unit = game.get_unit_at_cell(cell)
		if unit == null:
			unbindable.append("%s (recorded at %s -- no unit there on the seeded board)" % [name_of, str(cell)])
			continue
		_by_recorded_id[recorded_id] = unit
		_live_id_of[recorded_id] = unit.get_instance_id()


# Null for a unit that has since DIED, rather than a freed handle its caller would blow up on. The
# read goes through a Variant on purpose: a TYPED local has to resolve the ObjectID to type-check
# it and dies with "Trying to assign invalid previously freed instance" BEFORE any guard below it
# can answer -- CLAUDE.md's #149 sharp edge, and the reason this file crashed a real replay.
func _unit_for(ref: Variant) -> Unit:
	if ref is Dictionary:
		var id := int((ref as Dictionary).get("id", 0))
		if _by_recorded_id.has(id):
			var held: Variant = _by_recorded_id[id]
			if is_instance_valid(held):
				return held as Unit
	return null


static func _cell_of(raw: Variant) -> Vector2i:
	if raw is Array and (raw as Array).size() == 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return GridUtils.NO_CELL


# ==============================================================================
#  Stepping
# ==============================================================================

# One recorded event's worth of work. Returns false when the run is finished. Awaits, because a pass
# and a turn hand-over both do.
func step() -> bool:
	if not _seeded or is_finished():
		progressed.emit(true)
		return false
	var event: Dictionary = run.events[_cursor]
	_cursor += 1
	await _apply(event)
	var done := is_finished()
	if done:
		_seal_like_the_run()
		_compare()
	progressed.emit(done)
	return not done


func play() -> void:
	while await step():
		pass


func _apply(event: Dictionary) -> void:
	match str(event.get("event", "")):
		"turn_start":
			# The FIRST one was written by our own begin() during seeding -- turn_started never
			# fires for turn 1, which is why begin() writes it. Every later one is a hand-over.
			if not _seen_first_turn:
				_seen_first_turn = true
				return
			await game.end_turn()
		"pass":
			await _replay_pass(event)
		"gear":
			_replay_gear(event)
		"squad_verb":
			_replay_squad_verb(event)
		_:
			# Everything else is a CONSEQUENCE the rules re-derive: order_queued (the pass carries
			# the committed queue), order_cancelled, unit_downed, unit_died, turn_effects,
			# zone_captured, mission_end, summary. Replaying a consequence would be the side-channel
			# write Law #3 forbids for orders.
			pass


func _replay_pass(event: Dictionary) -> void:
	var squad_ref: Variant = event.get("squad")
	var leader: Unit = null
	if squad_ref is Dictionary:
		leader = _unit_for({"id": (squad_ref as Dictionary).get("leader", 0)})
	if leader == null:
		divergences.append("round %d: a pass names a squad whose leader could not be bound" % int(event.get("round", 0)))
		return

	# Grouped by batch id and issued in recorded order. A batch of more than one goes through
	# queue_batch -- the door queue_group_move uses -- because queue_action's plan-context gate is
	# skipped only while batching, so re-issuing a formation one order at a time would be refused
	# exactly the orders a group move exists to allow.
	var groups: Array = []           # Array[Array[Dictionary]], batches kept in first-seen order
	var index_of_batch: Dictionary = {}
	for order: Dictionary in event.get("orders", []):
		if bool(order.get("hold", false)):
			continue   # a filler nobody authored; the squad re-creates it when it activates
		var batch := int(order.get("batch", 0))
		if batch != 0 and index_of_batch.has(batch):
			(groups[index_of_batch[batch]] as Array).append(order)
		else:
			index_of_batch[batch] = groups.size()
			groups.append([order])

	for group: Array in groups:
		if group.size() > 1:
			_replay_batch(group, event)
		else:
			_replay_order(group[0] as Dictionary, event)

	await game.order_executor.execute_orders(leader)


func _replay_batch(group: Array, event: Dictionary) -> void:
	# Every move is BUILT before any is queued, exactly as GroupMoveSolver plans the whole formation
	# first: queueing one changes the projected positions the next would path against.
	var moves: Array[MoveAction] = []
	var squad: Squad = null
	for order: Dictionary in group:
		var unit := _unit_for(order.get("unit"))
		if unit == null:
			divergences.append("round %d: a batched move names a unit that could not be bound" % int(event.get("round", 0)))
			return
		var move := _build_move(unit, _cell_of(order.get("to")))
		if move == null:
			divergences.append("round %d: %s cannot reach %s any more" % [
				int(event.get("round", 0)), unit.get_unit_name(), str(_cell_of(order.get("to")))])
			return
		moves.append(move)
		squad = unit.squad
	if squad != null and not game.squad_manager.queue_batch(squad, moves):
		divergences.append("round %d: a recorded formation of %d was refused" % [
			int(event.get("round", 0)), moves.size()])


func _build_move(unit: Unit, dest: Vector2i) -> MoveAction:
	if dest == GridUtils.NO_CELL:
		return null
	# PlaySession.queue_move's exact shape, rather than a second answer to "how is a move built".
	var board = game._board()
	var range_info: Dictionary = RulesService.compute_move_range(unit, board)
	var reachable: Dictionary = range_info.reachable
	if not reachable.has(dest):
		return null
	var path: Array[Vector2i] = RulesService.reconstruct_path(range_info.came_from, unit.movement.cell, dest)
	var move := MoveAction.new()
	move.init(unit, path, GridUtils.get_terrain_icon_at_cell(game.grid, dest))
	return move


func _replay_order(order: Dictionary, event: Dictionary) -> void:
	var unit := _unit_for(order.get("unit"))
	var round_no := int(event.get("round", 0))
	if unit == null:
		divergences.append("round %d: an order names a unit that could not be bound" % round_no)
		return
	var refused := false
	match str(order.get("type", "")):
		"MOVE":
			var move := _build_move(unit, _cell_of(order.get("to")))
			if move == null:
				divergences.append("round %d: %s cannot reach %s any more" % [
					round_no, unit.get_unit_name(), str(_cell_of(order.get("to")))])
				return
			refused = not game.squad_manager.queue_action(unit.squad, move)
		"ATTACK":
			_arm_attack(unit, str(order.get("attack", "")), round_no)
			var attack := AttackAction.declare(unit, unit.get_projected_destination(), _cell_of(order.get("at")))
			refused = not game.squad_manager.queue_action(unit.squad, attack)
		"OVERWATCH":
			_arm_attack(unit, str(order.get("attack", "")), round_no)
			game.queue_overwatch(unit, _cell_of(order.get("at")))
		"RESCUE":
			var body := _unit_for(order.get("target"))
			if body == null:
				divergences.append("round %d: a rescue names a body that could not be bound" % round_no)
				return
			# The haul is the cell the PLAYER picked (#116). PlaySession.rescue would re-pick it,
			# which is why this takes the game door: replaying a decision, not re-deriving one.
			var haul: Vector2i = _cell_of(order.get("haul_to")) if order.get("haul_to") != null else body.movement.cell
			game.queue_rescue(unit, body, haul)
		"GUARD":
			var ward := _unit_for(order.get("target"))
			if ward != null:
				game.queue_guard(unit, ward)
		"INTIMIDATE":
			var victim := _unit_for(order.get("target"))
			if victim != null:
				game.queue_intimidate(unit, victim)
		"CAPTURE":
			game.queue_capture(unit)
		"RALLY", "RELOAD", "REV", "BURROW":
			var type_name := str(order.get("type", ""))
			game.queue_simple_action(unit, BaseAction.ActionType[type_name])
		_:
			notes.append("round %d: no replay door for a %s order" % [round_no, str(order.get("type", ""))])
	if refused:
		divergences.append("round %d: %s's recorded %s was refused" % [
			round_no, unit.get_unit_name(), str(order.get("type", ""))])


# A declared attack stamps whatever get_fired_attack() answers, which reads the live `active_attack`
# PICK -- so replaying an attack without re-making that pick fires the unit's default and silently
# resolves a different attack. This is the player's own menu pick, replayed.
func _arm_attack(unit: Unit, attack_name: String, round_no: int) -> void:
	unit.active_attack = null
	if attack_name == "":
		return
	for candidate: AttackData in unit.get_selectable_attacks():
		if candidate != null and candidate.display_name == attack_name:
			unit.active_attack = candidate
			return
	notes.append("round %d: %s no longer has an attack named '%s' -- fired its default" % [
		round_no, unit.get_unit_name(), attack_name])


func _replay_gear(event: Dictionary) -> void:
	var unit := _unit_for(event.get("unit"))
	if unit == null:
		return
	var index := int(event.get("index", -1))
	# The same Unit doors inventory_panel calls -- the ACT, replayed, never a state blob written in
	# (which would be the side-channel write Law #3 forbids).
	match str(event.get("verb", "")):
		"equip": unit.equip_weapon_from_inventory(index)
		"unequip": unit.unequip_weapon()
		"wear": unit.wear_armor(index)
		"remove_armor": unit.remove_armor()
		"use": unit.use_vial(index)
		"toss": unit.remove_item(index)


func _replay_squad_verb(event: Dictionary) -> void:
	var unit := _unit_for(event.get("unit"))
	if unit == null:
		return
	var squad_manager = game.squad_manager
	match str(event.get("verb", "")):
		"join":
			var squad_ref: Variant = event.get("squad")
			var leader: Unit = null
			if squad_ref is Dictionary:
				leader = _unit_for({"id": (squad_ref as Dictionary).get("leader", 0)})
			if leader != null and leader.squad != null:
				squad_manager.join_squad(unit, leader.squad)
		"leave":
			squad_manager.leave_squad(unit)
		"disband":
			if unit.squad != null:
				squad_manager.disband_squad(unit.squad)


# ==============================================================================
#  The verdict
# ==============================================================================

# What is COMPARED: the records that assert an OUTCOME the rules produced.
#
# order_queued / gear / squad_verb are deliberately absent -- they are this driver's own input, so
# diffing them asks only whether it echoed what it was handed. Including them would pad the report
# with rows that cannot fail.
const COMPARED := ["turn_start", "pass", "turn_effects", "unit_downed", "unit_died",
	"zone_captured", "mission_end"]


# The run's LAST outcome record is its mission_end, and the replay has to produce one too or the
# final vitals -- the frame that says who was left standing -- are compared against nothing. Sealed
# with the ending the RUN reported rather than a re-derived one: how a mission ended is a fact the
# recorder already wrote down, and re-deciding it here would be a second answer to it.
func _seal_like_the_run() -> void:
	var end := run.first("mission_end")
	if end.is_empty():
		return   # an unsealed run has no final frame to compare against either
	var outcome := str(end.get("outcome", ""))
	var failure := str(end.get("failed_by", ""))
	if not MissionLog.Ending.keys().has(outcome):
		notes.append("the run ended as '%s', which is no longer an ending this build knows" % outcome)
		return
	var ending: MissionLog.Ending = MissionLog.Ending[outcome]
	var failed_by: MissionRules.LoseCondition = MissionRules.LoseCondition.NONE
	if MissionRules.LoseCondition.keys().has(failure):
		failed_by = MissionRules.LoseCondition[failure]
	game.mission_log.seal(ending, failed_by)


func _compare() -> void:

	var mine: Array[Dictionary] = game.mission_log.events()
	var theirs: Array[Dictionary] = run.events
	var a := _outcomes(theirs, true)    # recorded: ids mapped onto live units
	var b := _outcomes(mine, false)     # the replay: already live ids

	if a.size() != b.size():
		divergences.append("the replay produced %d outcome records where the run had %d" % [b.size(), a.size()])
	for i in mini(a.size(), b.size()):
		_diff_record(a[i], b[i], i)


# The comparable projection: outcome records only, volatile envelope dropped, every recorded id
# mapped to the live unit it was bound to. Without the mapping every row differs and the report is
# noise; without dropping seq/t_ms every row differs for a second reason.
func _outcomes(events: Array[Dictionary], map_ids: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if not COMPARED.has(str(e.get("event", ""))):
			continue
		var row: Dictionary = _normalize(e, map_ids)
		row.erase("seq")
		row.erase("t_ms")
		row.erase("seconds")   # mission_end's wall clock: never the same twice, never a finding
		_renumber_batches(row)
		out.append(row)
	return out


# Walks the whole nested shape, because an id sits at several depths (a hit's actor, a vitals row, a
# squad's member list) and a per-field list would go stale the next time a field is added.
func _normalize(value: Variant, map_ids: bool) -> Variant:
	if value is Dictionary:
		var src := value as Dictionary
		var out := {}
		for key in src:
			if map_ids and (key == "id" or key == "leader"):
				out[key] = _mapped_id(int(src[key]))
			elif map_ids and key == "members":
				# A BARE ARRAY OF IDS -- no key on the elements to match, so a walker keyed on field
				# names alone slides straight past it and every squad row reads as different.
				var ids: Array = []
				for member in (src[key] as Array):
					ids.append(_mapped_id(int(member)))
				out[key] = ids
			else:
				out[key] = _normalize(src[key], map_ids)
		return out
	if value is Array:
		var list: Array = []
		for item in (value as Array):
			list.append(_normalize(item, map_ids))
		return list
	return value


# A batch id comes off a monotonic counter that has counted a different number of things by the time
# a replay runs, so the raw value can never match. What actually carries meaning is which orders
# SHARE one -- did the formation stay a formation -- so the ids are renumbered to their order of
# first appearance within the record. 0 is left alone: it is the hold-filler marker, not an id.
static func _renumber_batches(row: Dictionary) -> void:
	if not row.has("orders"):
		return
	var seen: Dictionary = {}
	for order in (row["orders"] as Array):
		if not (order is Dictionary) or not (order as Dictionary).has("batch"):
			continue
		var raw := int((order as Dictionary)["batch"])
		if raw == 0:
			continue
		if not seen.has(raw):
			seen[raw] = seen.size() + 1
		(order as Dictionary)["batch"] = seen[raw]


# INTS ONLY -- see _live_id_of. This used to read the unit out of the object map and ask
# is_instance_valid, which cannot work: the typed assignment resolves the ObjectID first and throws
# on a unit the replay has killed, so the diff crashed on any run with a casualty in it.
func _mapped_id(recorded: int) -> int:
	if _live_id_of.has(recorded):
		return int(_live_id_of[recorded])
	return recorded   # unbindable ids are already reported; leaving them alone keeps the row honest


func _diff_record(a: Dictionary, b: Dictionary, index: int) -> void:
	var kind_a := str(a.get("event", "?"))
	var kind_b := str(b.get("event", "?"))
	var where := "record %d (round %s)" % [index, str(a.get("round", "?"))]
	if kind_a != kind_b:
		divergences.append("%s: the run has %s where the replay has %s" % [where, kind_a, kind_b])
		return
	_diff_value(where + " %s" % kind_a, a, b)


func _diff_value(path: String, a: Variant, b: Variant) -> void:
	if divergences.size() >= 40:
		return   # a diverged replay can produce thousands; the first 40 are the ones anyone reads
	if a is Dictionary and b is Dictionary:
		var da := a as Dictionary
		var db := b as Dictionary
		for key in da:
			if not db.has(key):
				divergences.append("%s.%s: missing from the replay" % [path, str(key)])
			else:
				_diff_value("%s.%s" % [path, str(key)], da[key], db[key])
		return
	if a is Array and b is Array:
		var la := a as Array
		var lb := b as Array
		if la.size() != lb.size():
			divergences.append("%s: %d entries in the run, %d in the replay" % [path, la.size(), lb.size()])
			return
		for i in la.size():
			_diff_value("%s[%d]" % [path, i], la[i], lb[i])
		return
	# JSON HAS ONE NUMBER TYPE. A run read back off disk comes through JSON.parse_string as floats
	# while the live replay holds real ints, so a string compare reports every single number as a
	# difference -- 9 against 9.0 -- and buries any real one. Compare numerically when both sides
	# are numbers; everything else compares as text.
	if _is_number(a) and _is_number(b):
		if absf(float(a) - float(b)) > 0.00001:
			divergences.append("%s: run says %s, replay says %s" % [path, str(a), str(b)])
		return
	if str(a) != str(b):
		divergences.append("%s: run says %s, replay says %s" % [path, str(a), str(b)])


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


# Everything the tool prints, in the order a person reads it.
func report() -> Dictionary:
	return {
		"seeded": _seeded,
		"finished": is_finished(),
		"at": _cursor,
		"of": run.events.size() if run != null else 0,
		"divergences": divergences.duplicate(),
		"unbindable": unbindable.duplicate(),
		"notes": notes.duplicate(),
	}
