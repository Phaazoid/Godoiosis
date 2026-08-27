extends Node
class_name OrderExecutor

# Runs a squad's queued plan against the board, then settles the fallout. One pass:
# resolve -> moves (parallel) -> attacks (sequential) -> cell effects -> counters ->
# side-channel verbs -> eject whoever went down. Pulled out of game.gd 2026-07-26; holds a
# back-ref to the Game coordinator (same pattern as DevController/AIController/MainActionMenu)
# for the managers and panels it drives.
#
# Every plan resolves through execute_orders() -- the queue panel's Execute button, the action
# menu's Execute Orders entry, and AIController all land here. That single path is what keeps
# Law #2 honest (the queue previewed exactly this pass) and Law #3 cheap (the AI has no side
# channel to add).
#
# The headless Play API (play/play_session.gd) deliberately keeps its OWN twin of this
# sequence -- no animation, no awaits, no prompts. The two are documented mirrors: a phase
# added here needs the same phase added there.

var game   # the Game coordinator (Node2D); set by game._ready()

# Units downed mid-execution. Squad ejection is DEFERRED to the end of the pass -- restructuring
# squads while execute_orders sat mid-await was buggy. (A Crisis unit never lands here since #158:
# take_damage carries that rung out directly and the unit never goes DOWNED.)
var _downed_pending: Array[Unit] = []

# The plan THIS pass is playing out, non-null only while one is running. Two readers, both outside:
# battle3d._previewed_plan prefers it over the last resolve (#354), and game.refresh_action_queue
# reads it as "a pass is running, refuse to re-derive" (#361). That refusal is what now KEEPS
# SquadManager._last_resolved_plan stable across a pass -- before it, a kill mid-pass fired
# unit_died -> game._on_unit_died -> refresh_action_queue -> resolve_plan, re-resolving a queue whose
# earlier attacks had already landed. Nothing here consumes it -- execute_orders holds its own
# local -- so this is a published fact, not a second source of truth.
var executing_plan: ResolvedPlan = null

# Who the END-OF-TURN EFFECT PASS is about, non-empty only while one is running (#534). Published
# for the same reason executing_plan is, and read by the same poll: a health readout is up because
# something is ABOUT to happen to that unit (#350), and this phase is exactly that -- but it has no
# ResolvedPlan to be read out of and must not fake one. Instance ids, since the reader asks per unit
# per frame. apply_burning_tile_damage owns both ends; nothing here consumes it.
var effect_pass_subjects: Dictionary[int, bool] = {}

# ==============================================================================
#  Resolving a plan
# ==============================================================================

func execute_orders(unit):
	var squad = unit.squad

	game.squad_manager.validate_squad_plan(squad)
	game.overlay_manager.redraw_planned_paths()
	game.refresh_action_queue(squad)

	if game.squad_manager.squad_has_invalid_actions(squad):
		# A human gets control BACK here: flash the bad rows, leave the plan queued, let them fix it
		# and press Execute again. An AI squad has nobody to hand control back TO -- nothing in the
		# turn cycle mutates the state that produced the plan, so the identical plan is refused every
		# turn while the board keeps its ghosts and the squad never acts (#103). It concedes instead:
		# however a plan turns out, an AI pass must reach _end_squad_turn.
		if game.ai_controller.is_ai_faction(squad.leader.get_faction()):
			push_warning("AI squad conceded its turn: %s" % _invalid_plan_summary(squad))
			_end_squad_turn(squad)
			return
		for action in squad.action_queue:
			if not action.is_valid:
				action.actor.visuals.play_invalid_flash()
		return

	game.clear_selection_icons()

	# Explicit types throughout: `game` is untyped (game.gd has no class_name), so every
	# game.* call reads as Variant and `:=` cannot infer from it.
	var plan: ResolvedPlan = game.squad_manager.resolve_plan(squad, game._board())
	executing_plan = plan
	var move_actions := []
	var side_channel: Dictionary[BaseAction.ActionType, Array] = {}

	game.overlay_manager.clear_knockback_preview()
	for action in squad.action_queue.duplicate():
		action.actor.visuals.set_projected(false)
		if action.action_type == BaseAction.ActionType.MOVE:
			move_actions.append(action)
		elif BaseAction.SIDE_CHANNEL_ORDER.has(action.action_type):
			if not side_channel.has(action.action_type):
				side_channel[action.action_type] = []
			side_channel[action.action_type].append(action)

	# The pass's own reading of itself (#524), consulted for PAUSES ONLY -- every action below still
	# executes in this function's phase order, so nothing here can reorder playback (Law #2).
	var sheet := BeatSheet.read(squad, plan)
	var profile := Pacing.active_profile()
	# Keyed on the SAME is_ai_faction read the concede above makes, so a hotseat faction with AI off
	# is a human and paces like one: an AI plan is being read for the first time, a player's was
	# authored by the person watching it. CINEMATIC ignores the fork (#410); BOARD keeps it.
	var is_ai: bool = game.ai_controller.is_ai_faction(squad.leader.get_faction())
	var beat: float = Pacing.base_for(profile, is_ai)

	# Playback owns where the camera looks for the rest of this pass (#520). SAVED and RESTORED, never
	# cleared: an AI turn claims it for the whole turn and this runs inside one, so a blind release
	# would unlock the camera mid-turn.
	var camera_was_locked: bool = game.camera_controller.playback_locked
	game.camera_controller.set_playback_locked(true)

	# The camera goes to the walk and the walk WAITS for it (#520, dev 2026-08-26). Moves are
	# parallel, so one subject is framed -- the leader when the leader is walking -- and pan_to's
	# closing follow() carries the camera along beside it for free. No hold here: the pan IS the
	# beat, and a pause would be dead air between pressing Execute and anything happening.
	var walk := sheet.moves()
	var walker: Unit = walk.subject() if walk != null else null
	if walker != null:
		await game.camera_controller.pan_to(walker, Pacing.PLAYBACK_PAN)
	await _execute_action_phase_parallel(move_actions, _retire_move_markup)
	# The shots the walk walked into (#413), in trigger order. DECLARED v1 CUT: the damage lands at
	# the crossing moment in the RESOLVE -- that is where every number comes from -- but it plays
	# back after the walk instead of interrupting it. A crosser the shot downed has already stopped
	# at the crossing cell (MoveAction.walked_path), so what trails the fiction is the ORDER OF THE
	# VISUALS, never the outcome. Interrupting the walk is its own issue.
	await _execute_action_sequence(plan.watch_shots, beat)
	await _execute_action_sequence(plan.attacks, beat, _beat_holds(sheet.volleys(false), profile, is_ai),
			_beat_subjects(sheet.volleys(false)), _beat_lines(sheet.volleys(false)))
	_apply_cell_effects(plan.cell_effects)
	# The act break, held once between the two montages rather than folded into the first counter --
	# a turnover the counters then pace on top of, not instead of.
	await Pacing.beat(self, Pacing.duration_for(sheet.turnover(), profile, is_ai) if sheet.turnover() != null else 0.0)
	await _execute_action_sequence(plan.counters, beat, _beat_holds(sheet.volleys(true), profile, is_ai),
			_beat_subjects(sheet.volleys(true)), _beat_lines(sheet.volleys(true)))
	# The tail gets the same treatment the volleys do (dev 2026-08-26): a CODA beat per ORDER, so
	# each rescue pans to the body it lifts and holds for it instead of the whole batch sharing one
	# flat beat and one camera position.
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		var batch: Array = side_channel.get(type, [])
		var codas := sheet.codas(type)
		await _execute_action_sequence(batch, beat, _beat_holds(codas, profile, is_ai), _beat_subjects(codas))
	game.camera_controller.set_playback_locked(camera_was_locked)
	# The last await has returned, so the pass is played out: released HERE rather than beside
	# _end_squad_turn because everything below is synchronous (no frame renders between them) and
	# the squad-validity bail below skips that call entirely.
	executing_plan = null
	_process_downed_pending()
	# Loss-of-contact ejection (#151), right after downed ejection and for the same reason: the
	# pass has settled, and a member a shove displaced out of its leader's path-bubble is no
	# longer commandable. The plan could not have authored this -- the validator refuses it.
	game.squad_manager.enforce_contact()
	# The pass has settled, so this is where a Guard has finished arming (side channel) or been spent
	# (an absorbed hit). One redraw for both (#414).
	game.refresh_guard_markers()
	game.refresh_watch_markers()   # a watch that fired, or one that just armed (#413)
	# The pass has settled: this is where a mission is won or lost (#96, fork E). Before the
	# squad-validity guard below -- a squad that wiped itself must not skip the check.
	game.mission_controller.check()

	if not is_instance_valid(squad):
		return

	_end_squad_turn(squad)

# The terminal state of a squad's turn, and the ONE place it is defined: no orders queued, no
# projection or path arrows left, and the squad marked as having spent its turn. Reached at the end
# of a successful pass AND from the invalid-plan concede above (#103).
#
# set_has_acted does most of the visual work for free -- Squad._set_has_acted clears the queue, and
# every action_cancelled hop lands in game._on_unit_action_cancelled, which is what pulls a move's
# ghost and arrow. The icon clear ahead of it is for the crown/squadmate markers the squad's own
# display left; the success path also clears them before it animates, and clearing twice is
# idempotent. (It read "the TARGET markers a queued attack drew" until #346 -- TARGET was never
# drawn by an attack, only by Squad Up, and it is retired now.)
func _end_squad_turn(squad: Squad) -> void:
	game.clear_selection_icons()
	for action in squad.action_queue.duplicate():
		action.actor.visuals.set_projected(false)
		game.squad_manager.remove_action(squad, action)
	game.squad_manager.set_has_acted(squad, true)
	game.refresh_end_turn_button()
	for member in squad.members:
		game.overlay_manager.clear_move_markup(member)
	# LAST, not beside the ejection sweeps above: the clear at the top of this method would wipe an
	# earlier restore. Standing rings deliberately stand down for the WHOLE pass -- a marker sits on
	# its unit's projected destination, which during a pass is the cell the unit has not reached
	# yet, so a ring left up would jump ahead of the unit instead of travelling with it. Riding the
	# animated position is a separate build; the settled board is where they come back.
	game.refresh_squad_rings()

# Why a concede happened, for the console: an AI cannot see a red flash, so this is the only place
# the refusal is visible at all.
func _invalid_plan_summary(squad: Squad) -> String:
	var lines: Array[String] = []
	for action in squad.action_queue:
		if not action.is_valid:
			lines.append("%s: %s" % [action.actor.get_unit_name(), ", ".join(action.validation_errors)])
	return " | ".join(lines)

# on_settled, when given, fires ONCE per action at the first poll after its execution_complete
# flips -- the PER-UNIT arrival moment (#558). It is why the poll below now visits every action
# instead of breaking on the first unfinished one: this phase ends with the SLOWEST walker, so a
# phase-level hook would leave a short hop standing under its own ghost while a long one finished.
# Generic on purpose -- the phase runner still does not know what a move is.
func _execute_action_phase_parallel(actions: Array, on_settled := Callable()):
	if actions.is_empty():
		return

	for action in actions:
		action.begin_execution()

	for action in actions:
		action.execute()

	var settled: Dictionary[BaseAction, bool] = {}
	while true:
		var all_complete := true

		for action: BaseAction in actions:
			if not action.execution_complete:
				all_complete = false
				continue
			if on_settled.is_valid() and not settled.has(action):
				settled[action] = true
				on_settled.call(action)
		if all_complete:
			return

		await get_tree().process_frame

# A move's markup goes when ITS OWN unit arrives, not when the squad's pass ends (#558, dev
# 2026-08-26: "the AI ghost unit stays around for a bit after the unit already reaches its move
# destination"). Until this, nothing pulled a ghost until _end_squad_turn -- so a unit spent the rest
# of the pass standing underneath a translucent copy of itself.
func _retire_move_markup(action: BaseAction) -> void:
	game.overlay_manager.clear_move_markup(action.actor)

# The beat lands BEFORE each action, never after: that also spaces this phase off the previous one
# (the parallel move phase, then each side-channel batch) with no separate between-phases pause, and
# leaves no trailing pause before the squad's turn ends. An empty batch returns above, so a phase
# with nothing in it costs nothing.
func _execute_action_sequence(actions: Array, beat: float = 0.0, holds: Dictionary = {}, subjects: Dictionary = {},
		lines: Dictionary = {}):
	if actions.is_empty():
		return

	for action in actions:
		# With a hold schedule, only the action that OPENS a beat pauses -- one blast is one moment
		# however many it hits (#410), so a three-victim volley holds once instead of three times.
		# Without one (the side-channel tail) every action takes the flat base beat, as before.
		var hold: float = float(holds.get(action, 0.0)) if not holds.is_empty() else beat
		# The camera goes FIRST and the action WAITS for it (#520, dev 2026-08-26) -- a blow that
		# lands off-screen may as well not have happened. Same door AIController has always used, so
		# the pan is one seam and one duration; headless it lands instantly like every other beat.
		# Only a beat's OPENING action carries a subject, so a volley pans once and then plays.
		if subjects.has(action):
			# The ANGLE is published BEFORE the pan and never awaited (#520): the rig eases its yaw
			# in _process while pan_to tweens the travel, so the spin and the approach are one
			# movement rather than a turn followed by a walk.
			if lines.has(action):
				game.camera_controller.directed_line = lines[action]
			await game.camera_controller.pan_to(subjects[action], Pacing.PLAYBACK_PAN)
		await Pacing.beat(self, hold)
		action.begin_execution()
		action.execute()

		while not action.execution_complete:
			await get_tree().process_frame

# Pause schedule for one phase: the action that OPENS each beat -> how long to hold before it.
# Keyed by the beat's first SURVIVING member, so a volley whose lead was skipped (R7 downs the
# counter-er) still pauses before the member that actually swings. Every action is executed either
# way -- a skipped one is already a no-op inside AttackAction.execute; this decides only WHEN.
# Serves the side-channel tail unchanged, where a beat holds exactly one order.
func _beat_holds(beats: Array[BeatSheet.Beat], profile: Pacing.Profile, is_ai: bool) -> Dictionary:
	var holds: Dictionary = {}
	for beat in beats:
		if not beat.actions.is_empty():
			holds[beat.actions[0]] = Pacing.duration_for(beat, profile, is_ai)
	return holds

# Who the camera frames for each beat, keyed the same way the hold schedule is (#520): the action
# that OPENS the beat. A beat whose subject has already been freed is simply left out -- absence
# means "don't move", which is the right answer when there is nothing left to look at.
func _beat_subjects(beats: Array[BeatSheet.Beat]) -> Dictionary:
	var subjects: Dictionary = {}
	for beat in beats:
		var who := beat.subject()
		if who != null and not beat.actions.is_empty():
			subjects[beat.actions[0]] = who
	return subjects


# ...and from which SIDE, keyed identically (#520). A third schedule rather than one map to the Beat
# itself, because what this hands the executor is plain data: three questions (how long, who, from
# where), each answered before the pass starts. A beat with no direction is simply left out, the
# same way a subjectless one is -- absence means the camera keeps the angle it has.
func _beat_lines(beats: Array[BeatSheet.Beat]) -> Dictionary:
	var lines: Dictionary = {}
	for beat in beats:
		var line := beat.aim_line()
		if not line.is_empty() and not beat.actions.is_empty():
			lines[beat.actions[0]] = line
	return lines

# Play the resolved terrain deposits into the live store, then redraw the board (#50). Runs after
# the attack phase that produced them.
func _apply_cell_effects(cell_effects: Array[ResolvedCellEffect]) -> void:
	for effect in cell_effects:
		game.terrain_states.apply(effect)
	game.overlay_manager.redraw_terrain_live(game.terrain_states)

# ==============================================================================
#  End-of-phase damage
# ==============================================================================

# End-of-phase burn: a unit standing in fire when ITS faction's turn ends takes damage. Routed
# through take_damage so downs/kills/Crisis apply, then the same ejection sweep the attack pass
# uses. No is_active() filter (#191): LethalityRules.predict already rules DOWNED-plus-any-damage
# as KILLED (Fork 3, #33) -- burn is a damage source like any other and take_damage no-ops safely
# on an already-DEAD unit, so nothing upstream needs to ask the question again.
#
# SHOWN rather than settled in one frame (#534, dev 2026-08-26: "a quick post turn effect zoom to
# show all post turn effects... double speed camera zoom to an unit, unit takes fire damage, next").
# Until then this whole phase resolved between frames, so a unit could burn, go down and be ejected
# from its squad with nothing on screen between any of it.
#
# ONE list, walked once, so there is structurally no second answer to "who is about to be hit" --
# and deliberately NOT a BeatSheet: that reads a Squad and a ResolvedPlan, and this phase has
# neither, so using it would mean faking a plan. It reuses #520's camera seam at a shorter
# duration rather than growing one of its own.
func apply_burning_tile_damage(faction: Team.Faction) -> void:
	var burned := _units_standing_in_fire(faction)
	# Claim NOTHING for a phase with nothing to show: the release is what hands the player their
	# view back (#520 follow-up), so claiming here would fire a camera return at the end of every
	# turn, burning or not.
	if burned.is_empty():
		_process_downed_pending()
		return

	var camera_was_locked: bool = game.camera_controller.playback_locked
	game.camera_controller.set_playback_locked(true)
	# The SAME list the loop walks, published so the health readouts are up for it. Raised for the
	# WHOLE phase rather than one unit at a time, matching how a plan raises a bar over everyone it
	# will touch -- so the units still to come are already readable when the camera reaches them.
	for unit in burned:
		effect_pass_subjects[unit.get_instance_id()] = true
	for unit in burned:
		await game.camera_controller.pan_to(unit, Pacing.ENVIRONMENT_PAN)
		# The hit lands BEFORE the hold (dev, 2026-08-26: "the point of the linger is to show that
		# something happened"). The other way round, the pause watched a unit at full health and the
		# camera left as the cubes burst. It is also what keeps the mission banner off a kill that is
		# not on screen yet -- game.end_turn calls mission_controller.check the moment this returns.
		unit.take_damage(Terrain.BURNING_TILE_DAMAGE)
		await Pacing.beat(self, Pacing.ENVIRONMENT_HOLD)
	effect_pass_subjects.clear()
	game.camera_controller.set_playback_locked(camera_was_locked)
	_process_downed_pending()

# Who this phase is about, answered ONCE before any of it plays -- the whole set is knowable up
# front, being a pure query over the burning cells and the acting faction.
func _units_standing_in_fire(faction: Team.Faction) -> Array[Unit]:
	var burned: Array[Unit] = []
	for cell in game.terrain_states.burning_cells():
		var unit: Unit = game.get_unit_at_cell(cell)
		if unit != null and unit.get_faction() == faction:
			burned.append(unit)
	return burned

# ==============================================================================
#  Downed units
# ==============================================================================

func on_unit_downed(unit: Unit) -> void:
	# The down fires INSIDE AttackAction.execute(). The unit's state (DOWNED, 1 HP) is already
	# set in _go_downed; defer the squad/overlay cleanup until the execution pass settles, so
	# we never mutate squads while execute_orders is mid-await.
	if not _downed_pending.has(unit):
		_downed_pending.append(unit)

func _process_downed_pending() -> void:
	if _downed_pending.is_empty():
		return
	for unit in _downed_pending:
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			continue   # finished off later in the same pass -- the death path already cleaned it up
		game.overlay_manager.handle_unit_death(unit)   # clear its planning overlays (not its board presence)
		game.squad_manager.handle_unit_downed(unit)    # eject into a solo squad -- safe now, execution is over
		# A unit standing again at sweep time was rescued in the SAME pass (#124) -- Crisis accepts
		# were erased from the list above. It is still ejected (the rule stands either way), and it
		# is still SPENT the turn it's rescued -- but its solo squad only exists as of the eject, so
		# the mark lands here rather than in RescueAction.execute.
		if unit.is_active():
			unit.squad.has_acted = true
	_downed_pending.clear()
	game.refresh_action_queue(game.squad_manager.active_squad)
