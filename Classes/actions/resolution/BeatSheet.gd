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

	# The volley's members in strike order. Empty on a punctuation beat.
	var actions: Array[AttackAction] = []
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

	# CODA only: which side-channel order this is (RESCUE, RALLY, GUARD, ...).
	var coda_type: BaseAction.ActionType = BaseAction.ActionType.ATTACK

	func has_lethality(rung: ResolvedOutcome.Lethality) -> bool:
		return lethalities.has(rung)

	# Who the camera goes to for this beat (#520). The first VICTIM, because what the player needs
	# to read is what is being done to whom -- and the attacker is usually already in frame, since
	# reach is short. Falls back to the actor for a beat with no victim at all, which #47's swing at
	# open ground really is. Null on a punctuation beat: the turnover holds where it already looks.
	func subject() -> Unit:
		for victim in victims:
			if victim != null and is_instance_valid(victim):
				return victim
		return actor if actor != null and is_instance_valid(actor) else null

	# Drop this volley's no-op members and read the surviving facts off their outcomes. R7 skips a
	# counter-er, not a volley, so this runs AFTER grouping -- dropping a skipped LEAD any earlier
	# would orphan its own secondaries into a beat of their own.
	func _absorb() -> void:
		var played: Array[AttackAction] = []
		for attack in actions:
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


static func read(squad: Squad, plan: ResolvedPlan) -> BeatSheet:
	var sheet := BeatSheet.new()
	if squad == null or plan == null:
		return sheet

	var movers: Array[Unit] = []
	var codas: Dictionary = {}
	for action in squad.action_queue:
		if action.action_type == BaseAction.ActionType.MOVE:
			if action.actor != null:
				movers.append(action.actor)
		elif BaseAction.SIDE_CHANNEL_ORDER.has(action.action_type):
			if not codas.has(action.action_type):
				codas[action.action_type] = []
			codas[action.action_type].append(action)

	if not movers.is_empty():
		var moves := Beat.new()
		moves.kind = Kind.MOVES
		moves.victims.assign(movers)   # a MOVES beat strikes nobody; these are the movers
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

	for type in BaseAction.SIDE_CHANNEL_ORDER:
		if not codas.has(type):
			continue
		var coda := Beat.new()
		coda.kind = Kind.CODA
		coda.coda_type = type
		var batch: Array = codas[type]
		coda.actor = batch[0].actor
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
