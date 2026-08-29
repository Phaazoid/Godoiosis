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
	# The queued-Guard ghost goes with it (#450): both are plan-time marks, and the pass starting is
	# the moment the plan stops being a plan. The SOLID pair replaces it at the far end of this
	# function, where refresh_guard_markers runs once the ward has actually armed.
	#
	# REASONED, NOT PINNED -- deleting this line leaves the whole suite green, and that is a property
	# of the suite rather than of the line. What it protects is the stretch WHILE the pass animates,
	# where refresh_action_queue refuses to re-derive (#361) so nothing else would take the ghost
	# down; headless, Pacing collapses every beat to zero frames and execute_orders runs start to
	# finish synchronously, so that stretch does not exist to assert on (measured, #450).
	game.overlay_manager.clear_guard_preview()
	game.overlay_manager.clear_watch_preview()   # #591's ghosted footprint, same reason, same stretch
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
	# Keyed on the SAME is_ai_faction read the concede above makes, so a hotseat faction with AI off
	# is a human and paces like one: an AI plan is being read for the first time, a player's was
	# authored by the person watching it. CINEMATIC ignores the fork (#410); BOARD keeps it.
	var is_ai: bool = game.ai_controller.is_ai_faction(squad.leader.get_faction())
	# THE FALLBACK BASE, for an action the sheet has no beat for (#647). There is no pass-wide profile
	# any more -- COMBAT_ONLY gives a move and the volley after it different ones -- so this asks the
	# one collapse about NO beat rather than inventing a second rule: unclassifiable is not combat, so
	# OFF and COMBAT_ONLY both land on BOARD and ALWAYS still lands on CINEMATIC.
	var beat: float = Pacing.base_for(Pacing.profile_for(null), is_ai)

	# Playback owns where the camera looks for the rest of this pass (#520). SAVED and RESTORED, never
	# cleared: an AI turn claims it for the whole turn and this runs inside one, so a blind release
	# would unlock the camera mid-turn.
	var camera_was_locked: bool = game.camera_controller.playback_locked
	game.camera_controller.set_playback_locked(true)

	# The four schedules the volley phases read (#520), hoisted because sheet.volleys(false) is one
	# array and this asked for it five times. It now covers the TRIGGERED shots as well as the
	# authored attacks (#567), which is what retired the pair of hand-built watch schedules that used
	# to sit further down: a triggered shot gets its rung-aware hold, its linger and its push-in off
	# the same Pacing tables everything else does, instead of a flat attack's wait and no emphasis.
	var volleys := sheet.volleys(false)
	var holds := _beat_holds(volleys, is_ai)
	var subjects := _beat_subjects(volleys)
	var lines := _beat_lines(volleys)
	var lingers := _beat_lingers(volleys)
	var emphases := _beat_emphases(volleys)
	var profiles := _beat_profiles(volleys)

	# The walk, and the shots it walks INTO -- which now play AT the crossing moment rather than
	# after the whole phase (#567): the mover halts on the crossing cell, the shot fires, the walk
	# resumes, while its siblings keep walking. Still BEFORE the tear-out below, because a watch
	# fires at a crossing CELL, which the diorama's stage set does not hold -- lifting the ground
	# first would play the shot over a hole. The board is where you move, and a watch shot is the
	# tail of moving.
	await _execute_move_phase(move_actions, plan, sheet, is_ai, beat)

	# THE TEAR-OUT (#521): the ground the FIGHT happens on lifts off the board into a diorama, and
	# thuds back at the end. The cell set is the sheet's own -- computed once from the plan, so there
	# is no second answer to what is on stage -- and it holds only what MAIN ACTIONS touch, which is
	# the dev's rule: *"there have to be main actions at play. Movement by itself doesn't do it."*
	#
	# AFTER the walk, not before it, and that is forced by the same rule: an attacker's origin_cell
	# IS its post-move cell, so tearing out at the top of the pass makes it walk toward a hole and
	# pop into the sky on arrival. The board is where you move; the diorama is where you fight.
	#
	# Gated on the PROFILE too, which is what makes "displacement is provably zero with the cinematic
	# off" a property rather than a promise.
	await _stage_the_fight(sheet)

	# attack_playback(), not plan.attacks: a shot a SHOVE set off plays right after the volley that
	# threw somebody into it (#567), where the whole batch of them used to play ahead of the attacks
	# -- so the answering shot came before the blow it answered. The spliced list is built for
	# playback and never written back: a triggered shot inside plan.attacks would be counter-bait.
	await _execute_action_sequence(plan.attack_playback(), beat, holds, subjects, lines, lingers, emphases,
			profiles)
	_apply_cell_effects(plan.cell_effects)
	# The act break, held once between the two montages rather than folded into the first counter --
	# a turnover the counters then pace on top of, not instead of. It is a COMBAT beat under
	# COMBAT_ONLY (dev, 2026-08-28), so it keeps the cinematic's hold there.
	var turnover := sheet.turnover()
	await Pacing.beat(self, Pacing.duration_for(turnover, Pacing.profile_for(turnover), is_ai) \
			if turnover != null else 0.0)
	await _execute_action_sequence(plan.counters, beat, _beat_holds(sheet.volleys(true), is_ai),
			_beat_subjects(sheet.volleys(true)), _beat_lines(sheet.volleys(true)),
			_beat_lingers(sheet.volleys(true)), _beat_emphases(sheet.volleys(true)),
			_beat_profiles(sheet.volleys(true)))
	# The tail gets the same treatment the volleys do (dev 2026-08-26): a CODA beat per ORDER, so
	# each rescue pans to the body it lifts and holds for it instead of the whole batch sharing one
	# flat beat and one camera position.
	for type in BaseAction.SIDE_CHANNEL_ORDER:
		var batch: Array = side_channel.get(type, [])
		var codas := sheet.codas(type)
		await _execute_action_sequence(batch, beat, _beat_holds(codas, is_ai),
				_beat_subjects(codas), {}, _beat_lingers(codas), _beat_emphases(codas),
				_beat_profiles(codas))
	await _bring_the_board_home()   # the tiles travel back into their sockets (#521 slice B)
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

# The move phase: every walk starts at once and they are awaited together, which is the whole of
# "units are still shown moving together" (standing-reactions.md's presentation rule for #412).
#
# Since #567 a walk can HALT mid-path while the shot it walked into plays, and only that walk halts
# -- its siblings keep going. The shots play in the order the RESOLVE fired them, never in the order
# the crossers happen to reach their cells: which of your units crosses first is a row you dragged,
# and a playback that re-sorted by wall clock would lie about it. So only the HEAD of the pending
# list is ever looked at, and a crosser that arrives early simply stands there until its turn.
#
# The markup goes ONCE per action at the first poll after its execution_complete flips -- the
# PER-UNIT arrival moment (#558). It is why the poll visits every action instead of breaking on the
# first unfinished one: this phase ends with the SLOWEST walker, so a phase-level hook would leave a
# short hop standing under its own ghost while a long one finished. A PARKED walk is not complete,
# so its ghost and arrow correctly stay up through the interrupt.
func _execute_move_phase(actions: Array, plan: ResolvedPlan, sheet: BeatSheet,
		is_ai: bool, beat: float):
	# Framed across BOTH ENDS of the walk rather than centred on the walker (dev, scratchpad
	# 2026-08-26: "instead of just centering on the unit, it should try to show both their start and
	# end position in the initial shot"). Computed ONCE and returned to after every interrupt (#567,
	# dev 2026-08-28) -- re-reading the walker's cell mid-walk would re-frame what is LEFT of the
	# walk, so the shot would creep tighter with every shot fired.
	var walk := sheet.moves()
	var walker: Unit = walk.subject() if walk != null else null
	var span: Array[Vector2i] = []
	if walker != null:
		span = [walker.movement.cell, walker.get_projected_destination()]
	# The walk's OWN profile (#647), so the rig knows a plain move from a fought-over one. A walk is
	# not a combat beat, so COMBAT_ONLY plays it under BOARD -- which is what stops the camera swaying
	# and leaning through somebody crossing the field.
	var walk_profile := Pacing.profile_for(walk)
	await _frame_the_walk(span, walk_profile)
	if actions.is_empty():
		return

	var pending := _walk_interrupts(plan, actions)
	var volleys := sheet.volleys(false)
	var holds := _beat_holds(volleys, is_ai)
	var subjects := _beat_subjects(volleys)
	var lines := _beat_lines(volleys)
	var lingers := _beat_lingers(volleys)
	var emphases := _beat_emphases(volleys)
	var profiles := _beat_profiles(volleys)

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
			if not settled.has(action):
				settled[action] = true
				_retire_move_markup(action)

		if not pending.is_empty():
			var next: Dictionary = pending[0]
			var mover: MoveAction = next["move"]
			# all_complete is the ONLY way past a moment nobody parked for -- a walk that ended
			# without its pause because its mover was removed mid-shot. Unreachable by design, and
			# it plays the shot late rather than dropping it.
			if mover.parked_at() == int(next["step"]) or all_complete:
				await _execute_action_sequence(next["shots"], beat, holds, subjects, lines,
						lingers, emphases, profiles)
				mover.release()
				pending.pop_front()
				# The walk is still running, so the camera goes back to it (dev 2026-08-28). Skipped
				# once nothing is left to watch, where the next phase's own pan takes over. It restores
				# the walk's profile too, or the shot's cinematic would ride on through the rest of it.
				if not all_complete:
					await _frame_the_walk(span, walk_profile)
				continue

		if all_complete and pending.is_empty():
			return

		await get_tree().process_frame


# Where the camera sits for the walk (#520): the MIDPOINT of the walk's span in 2D, with the span
# itself published for the 3D rig to widen its distance to. The span goes out BEFORE the travel and
# is never awaited, exactly as a beat's angle is -- the rig widens on its own edge while the pan
# tweens, so the two are one movement. No hold: the pan IS the beat.
#
# One spelling, two call sites (#567) -- the top of the move phase, and again after each interrupt.
# An EMPTY span is "nothing walks", which is a hold-position queue or none at all.
func _frame_the_walk(span: Array[Vector2i], profile: Pacing.Profile) -> void:
	if span.is_empty():
		return
	# A hold-position order has no span to frame; the midpoint below is then the walker's own cell,
	# i.e. exactly the shot this always took. Absence means "the camera keeps its zoom", which is
	# already the idiom every other schedule here uses.
	#
	# NOT profile-gated, deliberately: framing both ends of a walk is legibility rather than drama,
	# and it has published with the zoom off since #520.
	if span[1] != span[0]:
		game.camera_controller.framed_span = span
	# ...and the walk publishes its own ZERO weight (#520's rule: every beat that frames something
	# publishes one, including zero). On the way back from an interrupt that is what pulls the camera
	# out of a kill's push-in -- absence would leave it leaning in for the rest of the walk.
	game.camera_controller.beat_emphasis = 0.0
	game.camera_controller.beat_profile = profile
	var grid: TileMapLayer = game.grid
	await game.camera_controller.pan_to_position(
			(GridUtils.cell_world(grid, span[0]) + GridUtils.cell_world(grid, span[1])) * 0.5,
			Pacing.PLAYBACK_PAN)


# The pass's mid-walk interrupts, in the order the resolve fired them (#567): one entry per moment,
# each carrying the walk to halt, the step to halt at, and every shot that one entry set off --
# a pinball chain included, since the cascade shares the moment that started it.
#
# The steps are handed to the walks here rather than stamped by the resolver: where a walk PAUSES is
# playback's question, and the resolve already answered the only one it owns (when the shot fired).
# Assigned to every mover, empty list included, so last pass's pauses can never survive into this one.
func _walk_interrupts(plan: ResolvedPlan, actions: Array) -> Array[Dictionary]:
	var moments: Array[Dictionary] = []
	var by_move: Dictionary[MoveAction, Array] = {}
	for shot in plan.mid_walk_shots():
		var mover := shot.triggered_during as MoveAction
		if mover == null or not actions.has(mover):
			continue
		var step: int = shot.triggered_at_step
		if not moments.is_empty() and moments[-1]["move"] == mover and int(moments[-1]["step"]) == step:
			(moments[-1]["shots"] as Array).append(shot)
			continue
		moments.append({"move": mover, "step": step, "shots": [shot]})
		if not by_move.has(mover):
			by_move[mover] = []
		(by_move[mover] as Array).append(step)

	for action in actions:
		var mover := action as MoveAction
		if mover == null:
			continue
		var steps: Array[int] = []
		if by_move.has(mover):
			steps.assign(by_move[mover])
		mover.interrupt_steps = steps
	return moments

# A move's markup goes when ITS OWN unit arrives, not when the squad's pass ends (#558, dev
# 2026-08-26: "the AI ghost unit stays around for a bit after the unit already reaches its move
# destination"). Until this, nothing pulled a ghost until _end_squad_turn -- so a unit spent the rest
# of the pass standing underneath a translucent copy of itself.
func _retire_move_markup(action: BaseAction) -> void:
	game.overlay_manager.clear_move_markup(action.actor)

# The HOLD lands before each action and the LINGER after it -- two schedules, two moments, and they
# are different questions: a hold is anticipation and scales with the drama profile, a linger is
# matched to an animation and is flat (#520, dev 2026-08-27). The hold also spaces this phase off the
# previous one with no separate between-phases pause. An empty batch returns above, so a phase with
# nothing in it costs nothing.
#
# "Never after" was this comment's own rule until 2026-08-27, written when a beat had nothing worth
# watching on the way out; health-cube debris is what made the trailing pause a feature rather than
# dead air.
func _execute_action_sequence(actions: Array, beat: float = 0.0, holds: Dictionary = {}, subjects: Dictionary = {},
		lines: Dictionary = {}, lingers: Dictionary = {}, emphases: Dictionary = {},
		profiles: Dictionary = {}):
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
			# ...and how big the moment is, published BEFORE the pan for the reason the angle is
			# (#520 diff 2c): the rig eases the push-in in _process while pan_to tweens the travel,
			# so the camera arrives already leaning in rather than lurching once it lands.
			#
			# Assigned unconditionally rather than only when non-zero -- a quiet beat publishing its
			# own 0 is what pulls the camera back out after a kill.
			game.camera_controller.beat_emphasis = float(emphases.get(action, 0.0))
			# ...and the PROFILE this beat plays under (#647), published beside them for the same
			# reason and read by every rig channel that has no beat of its own. Defaulted to BOARD
			# rather than held: a beat that reached this line and named no profile is not one the
			# cinematic claimed, and the sway would otherwise ride in from whatever came before.
			game.camera_controller.beat_profile = profiles.get(action, Pacing.Profile.BOARD)
			await game.camera_controller.pan_to(subjects[action], Pacing.PLAYBACK_PAN)
		await Pacing.beat(self, hold)
		action.begin_execution()
		action.execute()

		while not action.execution_complete:
			await get_tree().process_frame
		# ...and the LINGER, the one pause in this file that lands AFTER (#520, dev 2026-08-27).
		# execution_complete means the lunge, the shove and the fall are done -- it does NOT mean the
		# health cubes have finished bursting, because those are thrown by UnitMirror's own HP poll
		# and fly on HealthBlockDebris's own clock with nobody holding a reference. So this is a
		# tuned wait rather than a wait ON anything: the two are matched by knob, deliberately.
		#
		# REASONED, NOT PINNED -- deleting this line leaves the whole suite green, because
		# Pacing.beat returns without awaiting in a headless run (that escape is what keeps every
		# resolve-pass test off the wall clock). Same declaration clear_guard_preview carries at the
		# top of this function, and for the same reason. What IS pinned is the schedule and the table.
		await Pacing.beat(self, float(lingers.get(action, 0.0)))

# Which ground goes on stage (#521). BOARD stages nothing at all -- the tear-out is the cinematic's,
# and #410's ruling that the two profiles SHARE timings is about pacing, not about lifting the board
# into the sky. An empty cell set stages nothing either, so a pass with no fight in it is untouched.
#
# BYSTANDERS is the feels-test fork the ticket asks for, and it is one bool because the sheet has
# already decided who is in the fight: OFF stages the cells the fight touches, ON adds the ground
# every OTHER unit is standing on, so the diorama keeps its spatial context.
#
# Asked of the SHEET rather than of one beat (#647): the tear-out is once per pass, so what it wants
# to know is whether this pass has a fight in it at all. Under COMBAT_ONLY that is the same question
# as "does any beat run cinematic" -- a pass of nothing but walking stays on the board.
func _stage_the_fight(sheet: BeatSheet) -> void:
	if not _any_cinematic(sheet):
		return
	# THE GATE, and it is asked of the FIGHT's cells BEFORE any bystander is added -- an empty sheet
	# means no main actions, which is the whole rule. Asking after would let the feels-test flag put
	# a move-only pass back on stage, i.e. re-create the exact thing it is there to be judged next to.
	var cells: Array[Vector2i] = sheet.cells.duplicate()
	if cells.is_empty():
		return
	if Experiments.is_on(Experiments.Flag.DIORAMA_BYSTANDERS):
		var on_stage: Dictionary[Vector2i, bool] = {}
		for cell in cells:
			on_stage[cell] = true
		for child in game.units_root.get_children():
			var unit := child as Unit
			if unit == null:
				continue
			var cell := unit.get_projected_destination()
			if not on_stage.has(cell):
				on_stage[cell] = true
				cells.append(cell)
	# The board holds still, intact, before it comes apart. BEFORE stage(), not after: staging is
	# what puts the cells in the diorama, and a beat between that and begin_flight would hold them
	# in the sky rather than on the board.
	await Pacing.beat(self, Pacing.TEAR_OUT_BRACE)
	BoardSpace.stage(cells, BoardSpace.lift_offset())
	await _play_transition(cells, true)
	# ...and the assembled diorama holds before the first blow (dev, 2026-08-28: the action used to
	# start the moment the last tile landed).
	await Pacing.beat(self, Pacing.TEAR_OUT_SETTLE)


# The transition itself (#521 slice B): the tiles TRAVEL between their sockets and the diorama
# instead of appearing there. One spine both treatments share -- depart, white-out, arrive -- with
# the Experiments flag deciding only where the camera watches it from.
#
# THE SCHEDULE IS THE CONTRACT. This awaits StagingFlight.total() while the 3D host renders the very
# same plan, so a pass cannot resume with a tile still in the air, and the two sides cannot drift:
# they read ONE artifact rather than each deriving its own from the same knobs.
#
# The cell order is the sheet's own, which is already playback order -- so tiles arrive in the order
# their owners act. That is the ticket's quiet foreshadowing, and it cost nothing.
func _play_transition(cells: Array[Vector2i], entering: bool) -> void:
	# The entry opens on empty sky: the camera has cut ahead and nothing has arrived yet. The exit
	# asks for no lead -- the diorama is already there, and its own held beat is AFTERMATH above.
	var plan := StagingFlight.schedule(cells, Pacing.TEAR_OUT_EMPTY_SKY if entering else 0.0)
	if plan.is_empty():
		return
	var socket := -BoardSpace.lift_offset()
	BoardSpace.begin_flight(plan, socket if entering else Vector3.ZERO,
			Vector3.ZERO if entering else socket, entering)
	await Pacing.beat(self, StagingFlight.total(plan))
	# Ended HERE rather than left to the driver, and that is what makes the property hold in every
	# run: headless the await returns without a single frame, so nothing ever advanced the flight
	# and the tiles would still be sitting at their opening offsets. Every existing staging
	# assertion rests on the board being settled when this returns.
	BoardSpace.end_flight_now()


# The exit: the same travel, reversed, and THEN the staging is dropped. Dropping it first would
# teleport the board home and leave a transition animating cells nothing was displacing any more.
func _bring_the_board_home() -> void:
	var staged := BoardSpace.staged_cells()
	if not staged.is_empty():
		# The aftermath sits before the board reassembles -- SETTLE's twin at the other end, so the
		# last blow is not immediately swept away by the tiles going home.
		await Pacing.beat(self, Pacing.TEAR_OUT_AFTERMATH)
		await _play_transition(staged, false)
	BoardSpace.clear_staging()


# Pause schedule for one phase: the action that OPENS each beat -> how long to hold before it.
# Keyed by the beat's first SURVIVING member, so a volley whose lead was skipped (R7 downs the
# counter-er) still pauses before the member that actually swings. Every action is executed either
# way -- a skipped one is already a no-op inside AttackAction.execute; this decides only WHEN.
# Serves the side-channel tail unchanged, where a beat holds exactly one order.
#
# THE PROFILE IS PER BEAT SINCE #647, asked here rather than threaded in: under COMBAT_ONLY a volley
# and the walk before it are paced differently, so there is nothing pass-wide left to pass down.
func _beat_holds(beats: Array[BeatSheet.Beat], is_ai: bool) -> Dictionary:
	var holds: Dictionary = {}
	for beat in beats:
		if not beat.actions.is_empty():
			holds[beat.actions[0]] = Pacing.duration_for(beat, Pacing.profile_for(beat), is_ai)
	return holds


# ...and which profile each beat plays under, keyed identically -- the FIFTH schedule (#647), and the
# one the 3D rig reads for every channel that has no beat of its own: the sway, the push-in's scale
# and the directed yaw's strength.
#
# It is a schedule rather than a read at the publish site for the reason all four of its siblings are:
# every question this phase will ask is answered before the pass starts, so playback only spends the
# answers. See CameraController.beat_profile.
#
# THIS IS THE WHOLE GATE, and the lines and weights beside it are deliberately NOT filtered. Every
# rig channel already scales through Pacing's own *_of(profile) pair, and all four BOARD values ship
# at 0.0 -- so a plain beat publishes its angle and its weight and they land at zero strength. That
# keeps the fork in ONE place, and it keeps the BOARD knobs reachable: dial BOARD_SWAY up and a plain
# beat sways, which is the "the shape exists but is dialled out rather than absent" rule Pacing
# already states. Filtering the schedules instead would make those four sliders move nothing.
func _beat_profiles(beats: Array[BeatSheet.Beat]) -> Dictionary:
	var profiles: Dictionary = {}
	for beat in beats:
		if not beat.actions.is_empty():
			profiles[beat.actions[0]] = Pacing.profile_for(beat)
	return profiles


# Does anything in this pass run cinematic? The tear-out's gate, and the only question about a whole
# sheet the profile fork raises -- everything else is per beat.
func _any_cinematic(sheet: BeatSheet) -> bool:
	for beat in sheet.beats:
		if Pacing.profile_for(beat) == Pacing.Profile.CINEMATIC:
			return true
	return false

# ...and how long to STAY once it has played (#520, dev 2026-08-27). A fourth schedule beside the
# three above, built the same way and read the same way -- but keyed on the beat's LAST surviving
# member where they key on its FIRST, and that difference is the whole of "one blast is one moment
# however many it hits": a volley pans and holds at its opening action, plays every member, and
# lingers once after the final one. A beat's `actions` are already absorbed down to what really
# fired (BeatSheet.Beat._absorb), so [-1] can never be a skipped member.
#
# No profile and no is_ai, unlike _beat_holds: a linger is flat. See Pacing's LINGER table.
func _beat_lingers(beats: Array[BeatSheet.Beat]) -> Dictionary:
	var lingers: Dictionary = {}
	for beat in beats:
		if not beat.actions.is_empty():
			lingers[beat.actions[-1]] = Pacing.linger_for(beat)
	return lingers


# Who the camera frames for each beat, keyed the same way the hold schedule is (#520): the action
# that OPENS the beat. A beat whose subject has already been freed is simply left out -- absence
# means "don't move", which is the right answer when there is nothing left to look at.
#
# A triggered shot's own subject is the CROSSER, and that rule now lives in BeatSheet.Beat.subject()
# with every other one (#567). It used to be a hand-built dictionary here, beside a hand-built
# linger that could only ever say LINGER_ATTACK -- both retired the moment the sheet learned to
# read the watch shots.
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


# How big each beat is, keyed on its OPENING action like the holds and the subjects (#520 diff 2c).
# One blast is one moment however many it hits, so the weight belongs to the action that opens the
# beat -- the same key the pan and the hold use, and deliberately not [-1] like the linger, which
# lands after the last hit rather than framing the first.
#
# Built for every beat with actions, INCLUDING the ones that weigh nothing: publishing a 0 is what
# lets the camera relax between kills. See CameraController.beat_emphasis.
func _beat_emphases(beats: Array[BeatSheet.Beat]) -> Dictionary:
	var emphases: Dictionary = {}
	for beat in beats:
		if not beat.actions.is_empty():
			emphases[beat.actions[0]] = Pacing.emphasis_for(beat)
	return emphases
