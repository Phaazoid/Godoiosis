extends RefCounted
class_name AIWeaponRoutine

# Per-FAMILY AI stance (#726): what a weapon's signature mechanic asks the AI to hold back on. The
# integration contract (#78) hands the AI every verb and attack for free; nothing there says when a
# tool is worth SETTING UP rather than firing. This is that answer, one class per family, dispatched
# off WeaponData.WeaponType exactly as WeaponInstance._instance_for is -- and, like
# MAIN_ACTION_NEVER, the bare base is a legal declaration: table() names EVERY family, so a new one
# turns tests/law/test_ai_weapon_routine_coverage.gd red until somebody declares its stance, even
# when that stance is "nothing".
#
# A ROUTINE ONLY EVER SAYS NO. It refuses a preparation (allows_preparation) or defers one of its
# OWN candidates (defers_candidate). It never introduces a verb the archetype declared NEVER, never
# invents a target, never adds a score term -- the archetype table stays the authority on what a
# squad will ever do; the routine decides when it is worth doing. Both hooks are inert here.
#
# A PREPARATION IS A RULE, NOT A SCORE (dev, 2026-09-03). _score_plan prices this turn; a
# preparation pays off next turn, which no term can see. The predictability contract PREFERS the
# legible rule ("the spearman saves the spring for a line or a kill") over a multi-turn expectation
# the player cannot forecast -- so a routine is a sentence, and the score is never touched.
#
# Two families that LOOK like they want a routine and do not, recorded so nobody re-derives them:
# the Chainsword revs unconditionally when it cannot attack (a rev is free and refreshes; any
# "not yet" clause trades a refresh for idling -- dev, 2026-09-03), and the Kinetic Mace's economy
# is already priced by the score (a Blowback's shove is published before counters derive, so it
# denies the counter and wins on the reaction term; near a drop it wins on damage) -- see
# ai-tactics.md, "Weapon routines".

# Which verbs a routine may be asked about: the weapon SELF-abilities -- the Weapon Action
# submenu's own set (Unit.has_weapon_actions) -- never RESCUE/INTIMIDATE/RALLY. A family cannot
# veto a verb that is not its own.
const WEAPON_VERBS: Array[BaseAction.ActionType] = [
	BaseAction.ActionType.RELOAD, BaseAction.ActionType.REV, BaseAction.ActionType.BURROW]

static var _table: Dictionary = {}   # WeaponData.WeaponType -> AIWeaponRoutine, built on first use


# EVERY family, explicitly -- absence is the red the law suite looks for. Built lazily rather than
# in a static initializer so every subclass is certainly loaded when its .new() runs. Routines hold
# no state, so one instance per family serves every unit.
static func table() -> Dictionary:
	if _table.is_empty():
		_table = {
			WeaponData.WeaponType.NONE: AIWeaponRoutine.new(),
			WeaponData.WeaponType.CHAINSWORD: AIWeaponRoutine.new(),        # rev is unconditional (header)
			WeaponData.WeaponType.DRILL: DrillWeaponRoutine.new(),
			WeaponData.WeaponType.SPRINGSPEAR: SpringspearWeaponRoutine.new(),
			WeaponData.WeaponType.CARBINE: AIWeaponRoutine.new(),           # a dry magazine has no candidates; RELOAD follows on its own
			WeaponData.WeaponType.KINETIC_MACE: AIWeaponRoutine.new(),      # the score already prices the shove (header)
			WeaponData.WeaponType.CHEMICAL_SPITTER: AIWeaponRoutine.new(),  # no signature mechanic yet
			WeaponData.WeaponType.PROSTHETIC: AIWeaponRoutine.new(),        # no signature mechanic
		}
	return _table


# An undeclared family is a loud failure that still answers -- _instance_for's shape, softened
# because an inert stance is a correct default here where an unmapped instance class is not.
static func for_family(family: WeaponData.WeaponType) -> AIWeaponRoutine:
	var routines := table()
	if not routines.has(family):
		push_error("AIWeaponRoutine: no routine declared for weapon_type %s -- every family needs a stance (#726)" % [WeaponData.WeaponType.keys()[family]])
		family = WeaponData.WeaponType.NONE
	var routine: AIWeaponRoutine = routines[family]
	return routine


# A rune or an empty slot has no family and gets the inert base.
static func for_unit(unit: Unit) -> AIWeaponRoutine:
	var weapon := unit.equipped_weapon as WeaponInstance
	if weapon == null or weapon.template == null:
		return for_family(WeaponData.WeaponType.NONE)
	return for_family(weapon.template.weapon_type)


# Is preparing with `verb` worth it right now? Asked by AITactics.queue_main_action before the
# verb's builder runs, for WEAPON_VERBS only. A refusal is the same shape as can_reload()
# answering false: a builder gate, never a skip of the walk.
func allows_preparation(_unit: Unit, _verb: BaseAction.ActionType, _board: BoardContext) -> bool:
	return true


# Is this candidate a LAST RESORT for its own member? Asked by AITactics._best_candidate_for after
# the hypothetical is resolved and scored. A deferred candidate loses to every candidate the same
# member did not defer and is still taken when it has nothing else -- deferred, never deleted.
func defers_candidate(_unit: Unit, _candidate: AttackAction, _plan: ResolvedPlan, _score: Vector3i) -> bool:
	return false
