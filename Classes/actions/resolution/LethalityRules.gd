extends Object
class_name LethalityRules

# The stakes ladder (docs/design/will-and-death.md): given a unit's state and an incoming damage
# number, which rung does the hit land on? Pure and static — no board, no side effects, no RNG.
#
# ONE implementation, two callers, deliberately. PlanResolver asks at PLAN time against a threaded
# hypothetical so the queue can preview the rung; Unit.take_damage asks at EXECUTION time against
# live values. Law #2 says those two answers must be identical, and the only way to guarantee that
# is for there to be one answer. Until 2026-07-27 there were two hand-synced implementations —
# Unit._select_lethal_rung (DOWN/KILL only, with the maim decision buried a level down in
# UnitInstance.spend_will_for_down) and PlanResolver._predict_lethality (the full ladder) — which
# agreed by inspection and nothing else.
#
# This class names the rung. It decides nothing about how a rung is PAID: Unit still owns
# execution (HP, lifecycle, the Will spend, entering Crisis) and PlanResolver still owns threading
# the consequence into the next hit's hypothetical.

# Overkill ceiling: a hit exceeding remaining HP by more than this kills outright (rung 3 — so
# low-HP units aren't immortal). Stub tuning; replaced by Will math later.
const OVERKILL_CEILING := 10

# Crisis gates on a FULL Will pool — an identity gate, faction-agnostic since #57 (placeholder).
const CRISIS_WILL_GATE := UnitInstance.MAX_WILL

# Everything the ladder reads, and nothing else. A parameter object rather than loose args: eight
# positional params was a real call-site hazard, which is the shape PlanResolver._Hypo had already
# settled on. _Hypo EXTENDS this and adds its own threaded fields, so the resolver hands its
# hypothetical straight in with no copy and no field-mapping to keep in sync.
class Situation:
	var hp: int = 0                          # HP going into THIS hit (threaded mid-pass by the resolver)
	var start_hp: int = 0                    # HP at pass start — only the crisis-corpse case reads it
	var lifecycle: Unit.LifecycleState = Unit.LifecycleState.ACTIVE
	var will: int = 0
	var in_crisis: bool = false
	var can_maim: bool = false               # a limb remains to take; false = already fully maimed
	var crisis_armed: bool = false           # holds the Crisis ability (#158) — the gambit fires itself

	# A detached copy of the ladder's own fields — how a caller predicts against a threaded
	# hypothetical without touching it (#419). Beside the fields, so the two cannot drift.
	func copy() -> Situation:
		var s := Situation.new()
		s.hp = hp
		s.start_hp = start_hp
		s.lifecycle = lifecycle
		s.will = will
		s.in_crisis = in_crisis
		s.can_maim = can_maim
		s.crisis_armed = crisis_armed
		return s

# The live, execution-time reading of a unit. start_hp == hp because at execution there is no
# "earlier in the pass" — this hit IS the pass.
static func situation_for(unit: Unit) -> Situation:
	var s := Situation.new()
	s.hp = unit.get_current_hp()
	s.start_hp = s.hp
	s.lifecycle = unit.lifecycle_state
	s.will = unit.unit_instance.get_current_will()
	s.in_crisis = unit.in_crisis
	s.can_maim = unit.unit_instance.next_maim_slot() != -1
	s.crisis_armed = crisis_armed_for(unit)
	return s

# Is the gambit ARMED on this unit? One kit read, faction-blind (#158): holding the Crisis ability
# — from the Berserker job, or any source the kit knows — means a full-Will would-be-down ALWAYS
# becomes Crisis. Equipping the source IS the acceptance; there is no prompt, no stance table, and
# the player previews their own Crisis like anyone else's. (Replaced accepts_crisis_by_stance,
# whose PLAYER-always-false fork existed only to keep the live prompt unpredicted.)
static func crisis_armed_for(unit: Unit) -> bool:
	return unit.has_live_ability(Abilities.Id.CRISIS)

# The ladder itself:
#   already DEAD        -> no-op (NONE)
#   already DOWNED      -> any DAMAGING hit kills (Fork 3: downed-attack = kill)
#   damage < hp         -> survivable (NONE)
#   overkill > ceiling  -> KILLED
#   would-be-down       -> CRISIS if full-Will + the Crisis ability is held (deterministic, #158),
#                          else MAIMED if Will can't pay and a limb remains, else DOWNED
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
		return ResolvedOutcome.Lethality.KILLED if damage > 0 else ResolvedOutcome.Lethality.NONE
	if damage < s.hp:
		return ResolvedOutcome.Lethality.NONE
	if damage - s.hp > OVERKILL_CEILING:
		return ResolvedOutcome.Lethality.KILLED
	if s.will >= CRISIS_WILL_GATE and s.crisis_armed:
		return ResolvedOutcome.Lethality.CRISIS   # stands back up surged — the armed gambit is deterministic
	if s.will < UnitInstance.DOWN_WILL_COST:
		return ResolvedOutcome.Lethality.MAIMED if s.can_maim else ResolvedOutcome.Lethality.DOWNED
	return ResolvedOutcome.Lethality.DOWNED

# Which lifecycle a rung LEAVES its target in — the resolver's threading and any preview holding
# only an outcome ask the same map. What a rung SPENDS is deliberately not here: the Will cost
# differs per rung and stays beside the hypothetical it is spent from.
static func lifecycle_for(rung: ResolvedOutcome.Lethality,
		current := Unit.LifecycleState.ACTIVE) -> Unit.LifecycleState:
	match rung:
		ResolvedOutcome.Lethality.DOWNED, ResolvedOutcome.Lethality.MAIMED:
			return Unit.LifecycleState.DOWNED   # a maim IS a down — same lifecycle
		ResolvedOutcome.Lethality.KILLED:
			return Unit.LifecycleState.DEAD
	return current

# What a PREVIEW shows for HP the ladder has already sentenced. The threaded number goes NEGATIVE
# on a fatal hit — that is the ladder's arithmetic, not a readout — so every surface drawing a
# predicted HP asks here. One answer on purpose: the queue panel and the board readout showing
# different numbers for one plan is Law #2 broken at the point it is being rendered.
#
# It mirrors execution rather than inventing a convention — _go_downed clings at 1, a kill leaves
# the board. #313 read that convergence as a free teardown and #354 found it was a trap: the clamp
# flattens a sentenced unit's prediction ONTO the HP it already has, so a readout gated on "predicted
# differs from current" both put itself away mid-pass and never appeared for a unit at exactly 1 HP.
# DRAW with this number; never decide with it — PlanResolver.plan_changes is the membership answer.
static func displayed_hp(raw_hp: int, lifecycle: Unit.LifecycleState) -> int:
	match lifecycle:
		Unit.LifecycleState.DEAD:
			return 0
		Unit.LifecycleState.DOWNED:
			return 1
	return maxi(raw_hp, 0)
