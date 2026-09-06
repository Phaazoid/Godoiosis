extends BaseAction
class_name AttackAction

# A queued (or resolved) attack order — one instance per victim in an AoE volley (see
# create_volley), all sharing a `volley` array so a re-aim or a downed victim is derived, never
# stored twice. Carries the aim (origin/target_cell) and the chosen attack to fire (`fired_attack`
# — a carving or a specific WeaponAttackData, #72); PlanResolver fills in `resolved` each pass
# (R8) as the sole source of damage truth (Law #2 — the queue previews exactly what plays back).
# CounterAttackAction extends this for the reactive case.

var target: Unit
var resolved: ResolvedOutcome      # set by PlanResolver each pass (R8) — source of truth for damage
var attack_range: Array[Vector2i] = []
var origin_cell: Vector2i
var target_cell: Vector2i
# The cells the blast fired over, occupied or not -- stamped when the resolve builds the volley
# (create_volley), empty on an authored AIM. The tear-out stages exactly this (#754): every member
# shares ONE aim cell, so reading target_cell alone left a line's far victims and the ground under
# the beam on the board while the camera sat on the diorama.
var footprint: Array[Vector2i] = []
var target_texture: Texture2D
var target_name := "Target"
var is_secondary_hit := false
# The stored aim this was derived from (resolve_plan); null on the aim itself and on counters.
# Read by the whiff clause and the queue row's tint.
var source_aim: AttackAction = null
var volley: Array[AttackAction] = []
# The attack chosen to fire — a carving or a WeaponAttackData. Null means NO attack (bare fists),
# not the weapon's main: since #102 that fallback is gone (#30, #72).
var fired_attack: AttackData = null
# Who this hit was AIMED at, when a Guard substituted its victim (#414). Null on every ordinary hit.
# `target` is always the unit that actually takes the payload — the resolver rewrote it — so this is
# an annotation for the readouts and the block lunge, never a second answer to "who is hit".
var blocked_for: Unit = null
# This hit is a triggered OVERWATCH shot (#413), not an authored attack. Annotation only — the shot
# resolves as an ordinary derived attack in every respect; what reads this is presentation (the
# queue hangs it on the crossing move's row) and the readouts.
var is_watch_shot := false
# Who ENTERED the watched cell to set this shot off (#413) — the crosser, not necessarily the
# victim: a triggered shot is the attack, full stop, so its splash reaches bystanders too. Read by
# the queue panel, which hangs every line of one shot on the crossing move's own row.
var triggered_by: Unit = null
# WHEN this shot fired, where triggered_by says WHO set it off (#567). The order that was playing at
# the moment of the entry — the walk being stepped, or the volley whose shove threw somebody — and
# how far into it. A walk's step is an index into its `path`; -1 means "after that order finishes",
# which is what a shove landing is. Stamped over the WHOLE cascade one entry sets off, so a pinball
# chain plays at the moment that started it rather than at three moments of its own.
#
# Playback's only question, and the one thing the resolve did not already record:
# MoveAction.resolved_stop_index answers where a walk STOPPED and exists only when the shot halted
# it, so a shot the crosser walks away from has its moment nowhere else.
var triggered_during: BaseAction = null
var triggered_at_step := -1

var preview_sprites: Array[Node2D] = []

const ATTACK_ICON := preload("res://Art/Icons/ActionIcons/FightActionIcon.png")
const DOWN_ICON := preload("res://Art/Icons/StateIcons/Down.png")
const KILL_ICON := preload("res://Art/Icons/StateIcons/DedIcon.png")
const MAIM_ICON := preload("res://Art/Icons/StateIcons/DownMaim.png")
const CRISIS_ICON := preload("res://Art/Icons/ActionIcons/CrisisIcon.png")

func init(attacker: Unit, origin: Vector2i, target_unit: Unit, target_location: Vector2i):
	actor = attacker
	target = target_unit
	target_cell = target_location
	origin_cell = origin
	action_type = BaseAction.ActionType.ATTACK

	if target_unit != null and is_instance_valid(target_unit):
		target_texture = target_unit.get_map_sprite_texture()
		target_name = target_unit.get_unit_name()
	else:
		target_name = "Tile %s" % target_location   # cell-targeted attack (#47)

func execute():
	begin_execution()
	# Actor must be live to swing. (target may be null = a cell-targeted attack, #47.)
	if actor == null or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		finish_execution()
		return

	# The watch absorbs exactly one trigger, and THIS was it (#413). The ACTOR is the watcher, and
	# only the LIVE watch is touched here — the resolver spent its own per-pass copy (R2). Placed
	# above every remaining early-out and outside the target block, because a triggered shot that
	# whiffs or lands on an empty cell has still been taken; lead volley member only.
	if is_watch_shot and not is_secondary_hit:
		actor.spend_watch()

	# A UNIT attack whose target vanished this pass — nothing to hit, no lunge (unchanged).
	# A null target is intentional (a cell attack) and falls through to the lunge.
	if target != null and (not is_instance_valid(target) or target.is_queued_for_deletion()):
		finish_execution()
		return

	if resolved != null and resolved.skipped:
		finish_execution()                          # counter-er went down/dead this pass — no lunge, no damage
		return

	var direction = GridUtils.cardinal_direction_between(actor.get_projected_destination(), target_cell)

	if not is_secondary_hit:
		await actor.visuals.play_attack_lunge(direction)

	# The block moment (#414), slice one: the bodyguard lunges toward the unit it is covering, the
	# same lunge an attack plays. The loud jump-in-front the design wants waits on the battle-zoom /
	# sprite-FX stack (#358) — no bespoke animation machinery ahead of it. Secondary volley members
	# skip it for the reason they skip the attacker's lunge: one gesture per blast.
	if blocked_for != null and not is_secondary_hit and is_instance_valid(blocked_for):
		var block_dir = GridUtils.cardinal_direction_between(target.get_projected_destination(), blocked_for.get_projected_destination())
		await target.visuals.play_attack_lunge(block_dir)

	# Pure playback of the resolved outcome (R3) — no recomputation. A cell attack (target
	# null) has no unit consequence; it still plays out and (later, #50) deposits terrain effects.
	if target != null and resolved != null:
		# The Guard absorbs exactly one trigger, and THIS was it (#414). Spent before the payload
		# lands, so a shove into the void that frees the node below cannot skip it. Only the LIVE
		# ward is touched here — the resolver spent its own per-pass copy.
		if blocked_for != null:
			target.spend_guard()
		if fired_attack != null and fired_attack.heals:
			target.heal(resolved.heal_amount)
		else:
			target.take_damage(resolved.damage)
		for s in resolved.states_removed:
			target.remove_element_state(s)
		for s in resolved.states_added:
			target.add_element_state(s, resolved.state_turns.get(s, 0))
		# Knockback (#84, animated by the #259 rework): the target SLIDES the resolver's own trail
		# to its landing, holding its facing (the mirror gates on movement.sliding). Awaited, so a
		# sequential later attack finds the body where the plan already said it lands.
		if resolved.knockback_applied and is_instance_valid(target):
			target.movement.slide_along_path(resolved.knockback_path, resolved.knockback_landing_index)
			if target.movement.sliding:
				await target.movement.movement_finished
		# A void shove (#259): the hit's own damage may be 0, so take_damage above cannot carry
		# the death -- removal is its own door. die() frees the node and tears the squad down.
		# MIRRORED in play_session._apply_attack (the hand-copied twin, per the went_downed trap) --
		# except for the plummet, which is pure spectacle: the sprite falls a long way past the lip
		# before it goes (#431, dev: it used to vanish in mid-air), and the headless twin has no
		# sprite to drop. Awaited so the removal lands after the fall, not during it.
		if resolved.removed and is_instance_valid(target):
			await target.movement.plummet()
			if is_instance_valid(target):   # the await spans frames; the board can go in them
				target.die()
	# Readiness spend (#73): the ACT of firing consumes it, hit or whiff — lead volley member
	# only (mirrors the is_secondary_hit gate PlanResolver uses for cell-effect deposits).
	# Counters run through here too: they stamp main (#72), so a family whose MAIN spends — a
	# Carbine's magazine (#84) — pays for reactive fire, while Stab/Smash mains (consumes_readiness
	# false) stay no-ops. The matching "can I even counter on empty" gate is on
	# Unit.attack_source_can_counter().
	if not is_secondary_hit and fired_attack is WeaponAttackData:
		var weapon := actor.get_equipped_weapon() as WeaponInstance
		if weapon != null:
			weapon.consume_readiness_for(fired_attack as WeaponAttackData)

	# Vial burn (#697), on readiness's own terms: same gate, same moment, hit or whiff. The
	# resolver already decided WHETHER this cast drew on the charge (it only records one when the
	# attunement changed the damage), so there is nothing to judge here -- only to spend.
	#
	# EXECUTION IS THE ONLY PLACE ANYTHING IS SPENT, which is the whole of why cancelling costs
	# nothing: re-aiming, displacing, undoing and clearing all leave the charge untouched, because
	# the plan never had it. Readiness needed no reservation for exactly this reason.
	if not is_secondary_hit and resolved != null and resolved.burned_vial != null:
		actor.attunement = null

	finish_execution()

func get_action_icon() -> Texture2D:
	var lethal := lethality_icon(resolved)
	return lethal if lethal != null else ATTACK_ICON

func resolved_outcome() -> ResolvedOutcome:
	return resolved

# A derived row shows its AIM's validity: the panel's ATTACK rows are the resolver's copies, whose
# own is_valid is always the default true, so a refused aim could never render red. Overridden on the
# PREDICATE since #685, so the row's border and its icon tint read one answer rather than two.
func is_refused() -> bool:
	if source_aim != null:
		return source_aim.is_refused()
	return super()

# Static since #419: a derived row that is NOT an attack shows the same rung triple, and two
# spellings would let the queue disagree with itself about what a down looks like.
static func lethality_icon(outcome: ResolvedOutcome) -> Texture2D:
	if outcome != null:
		match outcome.lethality:
			ResolvedOutcome.Lethality.DOWNED:
				return DOWN_ICON
			ResolvedOutcome.Lethality.MAIMED:
				return MAIM_ICON
			ResolvedOutcome.Lethality.KILLED:
				return KILL_ICON
			ResolvedOutcome.Lethality.CRISIS:
				return CRISIS_ICON
	return null

func get_target_texture() -> Texture2D:
	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		return target.get_map_sprite_texture()

	return target_texture  #OR UNIT SPRITE IF ATTACKING SOMEONE I GUESS

# A watch shot is DERIVED (#592): the resolver makes it from a standing watch, nobody queued it, and
# it is not in action_queue at all -- so it cannot be sequenced. BaseAction answers yes by default,
# and an ordinary derived attack row IS draggable (it maps back to the aim the player authored,
# via source_aim); a watch shot has no such aim, which is what makes this its own answer.
func is_reorderable() -> bool:
	return not is_watch_shot

func actor_can_perform() -> bool:
	# Verb lock (will-and-death.md limb model) + readiness gate (#73) — an unfireable pick
	# (a sprung Spring, or Stab too if the family locks the whole weapon) can't be queued even
	# bypassing the menu (Law #3; the menu merely hides/disables what this refuses).
	return actor.can_wield_equipped() and actor.is_attack_fireable(fired_attack)

func get_description() -> String:
	# A blocked hit names BOTH ends: the row would otherwise read as an attack on a unit that was
	# never aimed at, and the whole point of Guard is that the player can see it coming (#414).
	if blocked_for != null and is_instance_valid(blocked_for):
		return "%s -> %s (guarding %s)" % [actor.get_unit_name(), get_target_name(), blocked_for.get_unit_name()]
	return "%s -> %s" % [actor.get_unit_name(), get_target_name()]

func clear_preview_sprites():
	for sprite in preview_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()

	preview_sprites.clear()

# The victim. Null for a #47 cell attack, and the base's actor fallback is what covers that:
# a swing at open ground is framed on the swinger.
func aimed_at() -> Unit:
	return target

func get_target_name() -> String:
	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		return target.get_unit_name()

	return target_name

func add_preview_sprites(sprite: Node2D):
	preview_sprites.append(sprite)

static func create(attacker: Unit, origin: Vector2i, target: Unit, target_cell: Vector2i) -> AttackAction:
	var action := AttackAction.new()
	action.init(attacker, origin, target, target_cell)
	return action

# Declare-time factory (Law #2): stamps the actor's current pick so player and AI declare
# sites can't diverge -- the rune-fists bug (#78) was exactly a forgotten stamp. Bare create()
# stays for derived actions, where the resolver COPIES the stored aim's stamp instead.
static func declare(attacker: Unit, origin: Vector2i, aim_cell: Vector2i) -> AttackAction:
	var action := AttackAction.create(attacker, origin, null, aim_cell)
	action.fired_attack = attacker.get_fired_attack()
	return action

static func create_volley(attacker: Unit, origin: Vector2i, aim_cell: Vector2i, victims: Array[Unit], fired_attack: AttackData, footprint: Array[Vector2i]) -> Array[AttackAction]:
	var volley_actions: Array[AttackAction] = []

	for victim in victims:
		var attack := AttackAction.create(attacker, origin, victim, aim_cell)
		attack.fired_attack = fired_attack
		attack.footprint = footprint
		attack.is_secondary_hit = not volley_actions.is_empty()
		volley_actions.append(attack)

	for attack in volley_actions:
		attack.volley = volley_actions

	return volley_actions

func get_outcome_summary() -> String:
	if resolved == null or target == null:   # cell attack (#47) — no unit outcome to summarize
		return ""
		
	var parts: Array[String] = []

	# A heal reports its own shape and stops -- lethality/popups/states are damage-only.
	if fired_attack != null and fired_attack.heals:
		parts.append("+%d" % resolved.heal_amount)
		parts.append("(%d->%d)" % [resolved.hp_before, resolved.target_hp_after])
		if resolved.elevation_delta != 0:
			parts.append(_slope_token())
		return "   ".join(parts)

	parts.append("-%d" % resolved.damage)
	# HP context: "before -> after". A CRISIS row breaks the subtraction arithmetic (the
	# target stands back up at revive HP), so it gets its own honest form.
	if resolved.lethality == ResolvedOutcome.Lethality.CRISIS:
		parts.append("(CRISIS -> up at %d, surged)" % resolved.target_hp_after)
	else:
		parts.append("(%d->%d)" % [resolved.hp_before, resolved.target_hp_after])

	match resolved.lethality:
		ResolvedOutcome.Lethality.DOWNED:
			parts.append("DOWNS")
		ResolvedOutcome.Lethality.MAIMED:
			parts.append("MAIMS (no Will)")
		ResolvedOutcome.Lethality.KILLED:
			parts.append("KILLS")
	if resolved.brace_bonus > 0:
		parts.append("+%d brace" % resolved.brace_bonus)
	for p in resolved.popups:
		parts.append(p)
	for s in resolved.states_added:
		parts.append("+%s" % Elemental.State.keys()[s])
	for s in resolved.states_removed:
		parts.append("-%s" % Elemental.State.keys()[s])
	if resolved.elevation_delta != 0:
		parts.append(_slope_token())
	return "   ".join(parts)

# The queue row's readout of ResolvedOutcome.elevation_delta (#258): the target sat above or below
# the attacker when this hit was previewed. Wording only -- no rule reads the delta yet.
func _slope_token() -> String:
	return "uphill" if resolved.elevation_delta > 0 else "downhill"
