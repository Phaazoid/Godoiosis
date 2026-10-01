extends Object
class_name LethalityRules

# The stakes ladder (docs/design/will-and-death.md): given a unit's state and an incoming damage
# number, which rung does the hit land on? Pure and static — no board, no side effects, no RNG.
#
# ONE implementation, two callers, deliberately. PlanResolver asks at PLAN time against a threaded
# hypothetical so the queue can preview the rung; Unit.take_damage asks at EXECUTION time against
# live values. Law #2 says those two answers must be identical, and the only way to guarantee that
# is for there to be one answer. Until 2026-07-27 there were two hand-synced implementations —
# Unit._select_lethal_rung (DOWN/KILL only, with the maim decision buried a level down in the
# since-retired Will spend) and PlanResolver._predict_lethality (the full ladder) — which agreed by
# inspection and nothing else.
#
# This class names the rung, and whether the blow takes a limb (#1174). It carries out neither:
# Unit still owns execution (HP, lifecycle, entering Crisis, taking the limb) and PlanResolver still
# owns threading the consequence into the next hit's hypothetical.

# Overkill ceiling: a hit exceeding remaining HP by more than this kills outright (rung 3 — so
# low-HP units aren't immortal). Stub tuning.
const OVERKILL_CEILING := 10

# A blow this big takes a limb, whether or not it downs (dev, #1174). A WOUNDED unit -- one that
# has gone down this battle -- loses one to a smaller blow. The blow is the hit after armour, any
# fall included, after Iron Will's cap: never the drowning top-up, never the ground. static var,
# not const: tuned on the Game tab.
static var LIMB_LOSS_DAMAGE := 10
static var LIMB_LOSS_DAMAGE_WOUNDED := 8

# Everything the ladder reads, and nothing else. A parameter object rather than loose args: eight
# positional params was a real call-site hazard, which is the shape PlanResolver._Hypo had already
# settled on. _Hypo EXTENDS this and adds its own threaded fields, so the resolver hands its
# hypothetical straight in with no copy and no field-mapping to keep in sync.
class Situation:
	var hp: int = 0                          # HP going into THIS hit (threaded mid-pass by the resolver)
	var start_hp: int = 0                    # HP at pass start — only the crisis-corpse case reads it
	var lifecycle: Unit.LifecycleState = Unit.LifecycleState.ACTIVE
	var in_crisis: bool = false
	var wounded: bool = false                # went down this battle (#1174): a smaller blow takes a limb
	var limb_order: Array[int] = []          # the slots successive limb losses would take; empty = none left
	var crisis_armed: bool = false           # holds the Crisis ability (#158) — the gambit fires itself

	# A detached copy of the ladder's own fields — how a caller predicts against a threaded
	# hypothetical without touching it (#419). Beside the fields, so the two cannot drift.
	func copy() -> Situation:
		var s := Situation.new()
		s.hp = hp
		s.start_hp = start_hp
		s.lifecycle = lifecycle
		s.in_crisis = in_crisis
		s.wounded = wounded
		s.limb_order = limb_order.duplicate()
		s.crisis_armed = crisis_armed
		return s

# The live, execution-time reading of a unit. start_hp == hp because at execution there is no
# "earlier in the pass" — this hit IS the pass.
static func situation_for(unit: Unit) -> Situation:
	var s := Situation.new()
	s.hp = unit.get_current_hp()
	s.start_hp = s.hp
	s.lifecycle = unit.lifecycle_state
	s.in_crisis = unit.in_crisis
	s.wounded = unit.wounded
	s.limb_order = unit.unit_instance.maim_order()
	s.crisis_armed = crisis_armed_for(unit)
	return s

# Is the gambit ARMED on this unit? One kit read, faction-blind (#158): holding the Crisis ability
# — from the Berserker job, or any source the kit knows — means an unwounded unit's would-be-down
# ALWAYS becomes Crisis. Equipping the source IS the acceptance; there is no prompt, no stance table, and
# the player previews their own Crisis like anyone else's. (Replaced accepts_crisis_by_stance,
# whose PLAYER-always-false fork existed only to keep the live prompt unpredicted.)
static func crisis_armed_for(unit: Unit) -> bool:
	return unit.has_live_ability(Abilities.Id.CRISIS)

# The ladder itself:
#   already DEAD        -> no-op (NONE)
#   already DOWNED      -> a DAMAGING hit kills once it meets the HP the body holds (Fork 3 as
#                          amended by #1002; a body nothing healed clings at 1, so any hit does)
#   damage < hp         -> survivable (NONE)
#   overkill > ceiling  -> KILLED
#   would-be-down       -> CRISIS if the Crisis ability is held and the unit is not wounded
#                          (deterministic, #158; the gate since #1174), else DOWNED
#
# Whether the blow ALSO takes a limb is not a rung: severs() answers it beside this, for any rung
# the unit survives (#1174).
#
# Crisis-in-progress is special (dev call 2026-06-26): it never downs/maims (a would-be-down is
# death), and EVERY independently-lethal hit stays flagged KILLED even after the unit "dies"
# earlier in the pass — the player must see that dodging one fatal counter won't save them.
# "Independently lethal" = the hit alone would fell the unit at pass-start HP. Execution ignores
# that flag on an already-dead unit; it exists for the preview.
static func predict(s: Situation, damage: int) -> ResolvedOutcome.Lethality:
	if s.in_crisis:
		if s.lifecycle == Unit.LifecycleState.DEAD:
			return ResolvedOutcome.Lethality.KILLED if damage >= s.start_hp else ResolvedOutcome.Lethality.NONE
		if damage >= s.hp:
			return ResolvedOutcome.Lethality.KILLED
		return ResolvedOutcome.Lethality.NONE
	if s.lifecycle == Unit.LifecycleState.DEAD:
		return ResolvedOutcome.Lethality.NONE
	if s.lifecycle == Unit.LifecycleState.DOWNED:
		# A hit that deals nothing cannot finish a body (#126) — that is what makes a 0-damage shove
		# REPOSITION a downed unit instead of executing it (PlanResolver._resolve_knockback skips a
		# KILLED target). Amends the 0-damage rider (stats.md): a 0-damage hit still COUNTS as a hit
		# — states, deposits and on-hit effects all still fire — it just no longer finishes.
		# Keyed on the damage number, not on the attack, because both callers already hold it and
		# neither holds the attack: Unit.take_damage(0) reaches the same answer with no new argument.
		#
		# HP-BASED since #1002 — a body holds real health once something heals it, and the dev's
		# ruling is that it is then "not necessarily dead in one hit anymore". `>=` is the ACTIVE
		# rung's own spelling four lines down, so there is one threshold in this file rather than
		# two; a body at 1 HP (every body nothing has healed) is unchanged by construction. No Crisis
		# branch: a body already paid that going down.
		if damage <= 0:
			return ResolvedOutcome.Lethality.NONE
		return ResolvedOutcome.Lethality.KILLED if damage >= s.hp else ResolvedOutcome.Lethality.NONE
	if damage < s.hp:
		return ResolvedOutcome.Lethality.NONE
	if damage - s.hp > OVERKILL_CEILING:
		return ResolvedOutcome.Lethality.KILLED
	if s.crisis_armed and not s.wounded:
		return ResolvedOutcome.Lethality.CRISIS   # stands back up surged — the armed gambit is deterministic
	return ResolvedOutcome.Lethality.DOWNED

# Does this blow take a limb (#1174)? Any rung the unit survives: a standing hit, a down, a Crisis
# entry, a hit on a body that holds. A kill takes nothing. `blow` is the hit alone -- the caller
# leaves out what is not a blow (the drowning top-up, the ground), which is why it is a parameter
# rather than the damage predict() read. The threshold is read off the PRE-hit state, so the hit
# that wounds a unit is still judged as a fresh one.
static func severs(s: Situation, blow: int, rung: ResolvedOutcome.Lethality) -> bool:
	if rung == ResolvedOutcome.Lethality.KILLED or s.limb_order.is_empty():
		return false
	if s.lifecycle == Unit.LifecycleState.DEAD:
		return false
	return blow >= limb_threshold(s)

static func limb_threshold(s: Situation) -> int:
	return LIMB_LOSS_DAMAGE_WOUNDED if s.wounded else LIMB_LOSS_DAMAGE

# Which lifecycle a rung LEAVES its target in — the resolver's threading and any preview holding
# only an outcome ask the same map.
static func lifecycle_for(rung: ResolvedOutcome.Lethality,
		current := Unit.LifecycleState.ACTIVE) -> Unit.LifecycleState:
	match rung:
		ResolvedOutcome.Lethality.DOWNED:
			return Unit.LifecycleState.DOWNED
		ResolvedOutcome.Lethality.KILLED:
			return Unit.LifecycleState.DEAD
	return current

# What HP a rung LEAVES its target at — lifecycle_for's sibling, answering the other half of "what
# does this rung do". Every writer of ResolvedOutcome.target_hp_after calls it (#1002), which is
# what makes the threaded number mean what execution will land on rather than the ladder's raw
# arithmetic. KILLED deliberately keeps the subtraction: it goes negative, nothing reads it as a
# quantity, and displayed_hp still clamps DEAD to 0 for the surfaces that draw it.
#
# It existed as a display clamp until #1002 and could not stay one: a body holds real HP now, so
# "DOWNED means 1" is true of the TRANSITION and false of the STATE, and only the rung knows which
# of those a number is. Two divergences closed with the move, neither about healing — a tile burn
# that triggers Crisis (TileHitAction threaded its own subtraction and previewed 0 against an
# execution that stands the unit up), and a heal on an ally felled earlier in the same pass
# (threading from a negative, so the queue read -5->1 while execution healed the clinging body).
static func hp_after(rung: ResolvedOutcome.Lethality, hp: int, damage: int) -> int:
	match rung:
		ResolvedOutcome.Lethality.DOWNED:
			return 1                             # _go_downed clings here
		ResolvedOutcome.Lethality.CRISIS:
			return Abilities.CRISIS_REVIVE_HP    # the gambit stands back up (enter_crisis)
	return hp - damage

# What a PREVIEW shows for HP the ladder has already sentenced. Since #1002 the threaded number is
# already what execution lands on (hp_after above), so the only clamp left is the dead: a kill
# threads NEGATIVE — the ladder's arithmetic, not a readout — and every surface drawing it asks
# here. One answer on purpose: the queue panel and the board readout showing different numbers for
# one plan is Law #2 broken at the point it is being rendered.
#
# #313 read the old DOWNED clamp as a free teardown and #354 found it was a trap: it flattened a
# sentenced unit's prediction ONTO the HP it already has, so a readout gated on "predicted differs
# from current" both put itself away mid-pass and never appeared for a unit at exactly 1 HP. That
# collision survives the move (the hypo now threads the 1 instead), which is why the rule stands:
# DRAW with this number; never decide with it — PlanResolver.plan_changes is the membership answer.
static func displayed_hp(raw_hp: int, lifecycle: Unit.LifecycleState) -> int:
	if lifecycle == Unit.LifecycleState.DEAD:
		return 0
	return maxi(raw_hp, 0)
