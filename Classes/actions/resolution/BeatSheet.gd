extends RefCounted
class_name BeatSheet

# The cinematic's reading of one resolved pass (#524, umbrella #410): "what is in this fight?"
# The cast, the cells the fight touches, and an ordered beat list -- the shot list that #519's
# timing table and #520's camera director both read. Consumes a ResolvedPlan and the squad's
# queue; computes no damage and no geometry, and if it ever needs to, that is the bug (Law #2:
# the zoom is a mirror, never an authority).
#
# The beat order MIRRORS OrderExecutor.execute_orders and its phase order rather than restating
# it: moves, attack volleys in queue order, cell effects, the counter turnover, counter volleys,
# then the side-channel tail in SIDE_CHANNEL_ORDER. A phase with nothing in it produces no beat.
# Mirroring is literal about GRANULARITY too, not just order: a volley is one beat because one
# blast is one moment, and a side-channel verb is one beat EACH because execute_orders awaits them
# one at a time. Where the two disagree, this is wrong and execution is right.
#
# Volley grouping is the RESOLVER's rule, not a second one: is_secondary_hit marks the non-lead
# members (create_volley / create_counter_volley stamp it) and PlanResolver.resolve_counters
# already walks the flat array exactly this way.
#
# A beat's WEIGHT is facts, never a duration and never a severity ranking: the lethality rungs it
# contains, whether it shoves, drops, removes, or was held by Iron Will. Collapsing those into a
# beat length is #519's table under a chosen profile, and ranking KILLED against MAIMED is that
# same table's call. Doing either here would be a second answer to a question #519 owns (Law #4).

enum Kind { MOVES, VOLLEY, CELL_EFFECTS, TURNOVER, CODA }


# One shot. A VOLLEY is one blast in one moment however many it hits (#410: an AoE striking three
# victims is a single sweep, not three cuts); the rest is the phase punctuation around them.
class Beat:
	var kind: int = Kind.VOLLEY
	var is_counter := false

	# The orders this beat PLAYS, in execution order -- a volley's members in strike order, a MOVES
	# beat's real moves, a CODA's single side-channel verb. Typed to the base so one field answers
	# for every kind; empty only on punctuation (CELL_EFFECTS, TURNOVER).
	var actions: Array[BaseAction] = []
	var actor: Unit = null

	# Aligned by index, and BOTH MAY BE EMPTY on a real beat: #47 lets a legal aim at cells with
	# no unit resolve as a cell attack (target stays null), so a swing at open ground is a beat
	# with no victim at all. Nothing may assume victims[0] exists.
	var victims: Array[Unit] = []
	var lethalities: Array[ResolvedOutcome.Lethality] = []

	var has_knockback := false
	var has_fall := false
	var has_removal := false
	var iron_will_held := false
	var has_heal := false

	# CODA only: which side-channel order this is (RESCUE, RALLY, GUARD, ...).
	var coda_type: BaseAction.ActionType = BaseAction.ActionType.ATTACK

	func has_lethality(rung: ResolvedOutcome.Lethality) -> bool:
		return lethalities.has(rung)

	# Who the camera goes to for this beat (#520). The ORDERS answer it -- BaseAction.aimed_at() --
	# because what the player needs to read is what is being done to whom, and only the order knows
	# who that is: a volley's victim, a rescue's body, a mover itself. The attacker is usually
	# already in frame, since reach is short. Falls back to the beat's actor, which is what covers
	# #47's swing at open ground. Null on a punctuation beat: the turnover holds where it looks.
	#
	# NOT read off `victims`: that list is aligned with `lethalities` for #519's table, and a beat
	# with no victims (MOVES, CODA) still has a subject.
	func subject() -> Unit:
		for action in actions:
			var who := action.aimed_at()
			if who != null and is_instance_valid(who):
				return who
		return actor if actor != null and is_instance_valid(actor) else null

	# The line the camera frames this beat ACROSS (#520): [from, to] in sim cells, empty when the
	# beat has no direction to be seen from. Only a VOLLEY has one -- the ticket's profile shot and
	# "the next pair's natural profile angle" are both about an attacker and what they are aimed at,
	# and moves, punctuation and the side-channel tail have no pair. Empty is the answer for those,
	# which is already this sheet's idiom for "the camera does not move" (see subject()).
	#
	# The cells come off the ATTACK, not off the two units: origin_cell/target_cell are the
	# resolver's own aim, so a swing at open ground (#47, target null) still has a direction, and a
	# victim freed mid-pass cannot take the angle down with them. An aim at your own cell has no
	# direction and is skipped rather than answered.
	func aim_line() -> Array[Vector2i]:
		for action in actions:
			var attack := action as AttackAction
			if attack == null:
				continue
			if attack.origin_cell == attack.target_cell:
				continue
			return [attack.origin_cell, attack.target_cell]
		return []

	# Drop this volley's no-op members and read the surviving facts off their outcomes. R7 skips a
	# counter-er, not a volley, so this runs AFTER grouping -- dropping a skipped LEAD any earlier
	# would orphan its own secondaries into a beat of their own.
	func _absorb() -> void:
		var played: Array[BaseAction] = []
		for action in actions:
			var attack := action as AttackAction
			if attack == null:
				continue
			var out := attack.resolved
			if out != null and out.skipped:
				continue
			played.append(attack)
			if attack.target != null and is_instance_valid(attack.target):
				victims.append(attack.target)
				lethalities.append(ResolvedOutcome.Lethality.NONE if out == null else out.lethality)
			if out == null:
				continue
			has_knockback = has_knockback or out.knockback_applied
			has_fall = has_fall or out.fall_levels > 0
			has_removal = has_removal or out.removed
			iron_will_held = iron_will_held or out.iron_will_held
			# The RESOLVER's own answer, like every other fact here -- never a re-read of
			# fired_attack.heals. A heal that fired reads true even if the cap ate it.
			has_heal = has_heal or out.heal_amount > 0
		actions = played


var beats: Array[Beat] = []

# Everyone on stage: the acting squad plus every squad it strikes, all members -- #410's "everyone
# in every participating squad is on stage". Counter-ers and their victims fall inside those squads
# by construction, so they are never gathered separately.
var cast: Array[Unit] = []

# Every cell the fight touches: attacker origins, aimed cells, whole knockback flights and their
# landings, terrain deposits, and the standing cell of any cast member none of that mentions.
# Slice #521's tear-out set is exactly this, computed once here rather than again there.
var cells: Array[Vector2i] = []


# The VOLLEY beats of one phase, in order. OrderExecutor's pause schedule reads these; the
# punctuation beats around them are not things it executes.
func volleys(counter: bool) -> Array[Beat]:
	var found: Array[Beat] = []
	for beat in beats:
		if beat.kind == Kind.VOLLEY and beat.is_counter == counter:
			found.append(beat)
	return found


# The act break before the counters, or null when the defending line never answers.
func turnover() -> Beat:
	for beat in beats:
		if beat.kind == Kind.TURNOVER:
			return beat
	return null


# The walk that opens the pass, or null when nothing travels (an all-holds queue, or none at all).
func moves() -> Beat:
	for beat in beats:
		if beat.kind == Kind.MOVES:
			return beat
	return null


# One phase of the side-channel tail, in execution order -- one beat per ORDER, so a batch of
# three rescues is three. execute_orders reads these the same way it reads volleys().
func codas(type: BaseAction.ActionType) -> Array[Beat]:
	var found: Array[Beat] = []
	for beat in beats:
		if beat.kind == Kind.CODA and beat.coda_type == type:
			found.append(beat)
	return found


static func read(squad: Squad, plan: ResolvedPlan) -> BeatSheet:
	var sheet := BeatSheet.new()
	if squad == null or plan == null:
		return sheet

	var walks: Array[BaseAction] = []
	var coda_orders: Dictionary[BaseAction.ActionType, Array] = {}
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.MOVE:
			var move := action as MoveAction
			# A hold-position filler is NOT a move -- nobody ordered it and nothing travels. So a
			# queue of nothing but fillers has no MOVES beat, which is the honest reading of a
			# phase in which the board does not change.
			if move != null and not move.is_hold_position and move.actor != null:
				walks.append(move)
		elif BaseAction.SIDE_CHANNEL_ORDER.has(action.action_type):
			if not coda_orders.has(action.action_type):
				coda_orders[action.action_type] = []
			coda_orders[action.action_type].append(action)

	if not walks.is_empty():
		var moves := Beat.new()
		moves.kind = Kind.MOVES
		# The LEADER opens it when it is walking: a squad's move is read from the unit the rest are
		# following, and subject() takes the first order's aim. Otherwise queue order stands.
		for i in walks.size():
			if walks[i].actor == squad.leader:
				var lead: BaseAction = walks[i]
				walks.remove_at(i)
				walks.insert(0, lead)
				break
		moves.actions.assign(walks)
		moves.actor = walks[0].actor
		sheet.beats.append(moves)

	sheet.beats.append_array(_group(plan.attacks, false))

	if not plan.cell_effects.is_empty():
		var deposits := Beat.new()
		deposits.kind = Kind.CELL_EFFECTS
		sheet.beats.append(deposits)

	# The act break exists only if the defending line actually answers -- #410's "when the
	# attacker's last swing lands, a beat, the defending line raises weapons in unison". A counter
	# phase that is entirely skipped plays nothing, so it earns no turnover either.
	var counter_beats := _group(plan.counters, true)
	if not counter_beats.is_empty():
		var turnover := Beat.new()
		turnover.kind = Kind.TURNOVER
		turnover.is_counter = true
		sheet.beats.append(turnover)
		sheet.beats.append_array(counter_beats)

	# ONE BEAT PER ORDER, not per type: execute_orders plays the side-channel tail one verb at a
	# time, each awaiting its own completion, so three rescues are three moments and not one. A
	# beat per type would leave rescuers two and three acting off-camera and unheld (#520).
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		if not coda_orders.has(type):
			continue
		var batch: Array = coda_orders[type]
		for entry in batch:
			var order := entry as BaseAction
			if order == null:
				continue
			var coda := Beat.new()
			coda.kind = Kind.CODA
			coda.coda_type = type
			coda.actor = order.actor
			coda.actions.append(order)
			sheet.beats.append(coda)

	sheet._gather_cast(squad, plan)
	sheet._gather_cells(plan)
	return sheet


# Walk a flat action list into volleys. A lead member (is_secondary_hit false) opens a beat and
# every secondary after it joins it -- the same read PlanResolver.resolve_counters makes over the
# same flat array. A beat left empty by skipped members is dropped entirely.
static func _group(actions: Array, is_counter: bool) -> Array[Beat]:
	var grouped: Array[Beat] = []
	var current: Beat = null
	for action in actions:
		var attack := action as AttackAction
		if attack == null:
			continue
		if current == null or not attack.is_secondary_hit:
			current = Beat.new()
			current.kind = Kind.VOLLEY
			current.is_counter = is_counter
			current.actor = attack.actor
			grouped.append(current)
		current.actions.append(attack)

	var played: Array[Beat] = []
	for beat in grouped:
		beat._absorb()
		if not beat.actions.is_empty():
			played.append(beat)
	return played


func _gather_cast(squad: Squad, plan: ResolvedPlan) -> void:
	var seen: Dictionary = {}
	_enlist(squad, seen)
	for list in [plan.attacks, plan.counters]:
		for action in list:
			var attack := action as AttackAction
			if attack != null and attack.target != null and is_instance_valid(attack.target):
				_enlist(attack.target.squad, seen)


func _enlist(squad: Squad, seen: Dictionary) -> void:
	if squad == null or not is_instance_valid(squad):
		return
	var roster: Array[Unit] = [squad.leader]
	roster.append_array(squad.members)
	for unit in roster:
		if unit == null or not is_instance_valid(unit):
			continue
		if seen.has(unit.get_instance_id()):
			continue
		seen[unit.get_instance_id()] = true
		cast.append(unit)


func _gather_cells(plan: ResolvedPlan) -> void:
	var seen: Dictionary = {}
	for list in [plan.attacks, plan.counters]:
		for action in list:
			var attack := action as AttackAction
			if attack == null:
				continue
			_mark(attack.origin_cell, seen)
			_mark(attack.target_cell, seen)
			var out := attack.resolved
			if out == null or not out.knockback_applied:
				continue
			# The whole flight, not just its ends: #520 pans ALONG this and #521 has to tear out
			# every cell it crosses. knockback_path is already the resolver's own route.
			for cell in out.knockback_path:
				_mark(cell, seen)
			_mark(out.knockback_from, seen)
			_mark(out.knockback_to, seen)
	for effect in plan.cell_effects:
		_mark(effect.cell, seen)
	# A squadmate who neither acts nor is hit is still on stage, so its ground is torn out too.
	for unit in cast:
		_mark(unit.get_projected_destination(), seen)


func _mark(cell: Vector2i, seen: Dictionary) -> void:
	if seen.has(cell):
		return
	seen[cell] = true
	cells.append(cell)
