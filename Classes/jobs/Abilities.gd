extends Object
class_name Abilities

# The canonical ability roster + tuning knobs (docs/design/jobs.md "The ability chassis").
# Id is the ability vocabulary — our own data type: no misspelling, autocompletes. It is
# persisted in .tres (AbilityData.id), so it is APPEND-ONLY: NONE stays first, new abilities
# go on the end, never reorder. Dispatch stays hardcoded at each hook site (resolver /
# counter path / action / movement), but every site reads its id and numbers from here,
# so the roster and the balance surface both live in one place.

enum Id { NONE, IRON_WILL, INTIMIDATION, TAUNT, WATERWALK, INSULATED_SHOCK, CRISIS, BRACE }

const IRON_WILL_DAMAGE_CAP := 6      # playtest-tunable
const INTIMIDATION_WILL_DRAIN := 3   # playtest-tunable

# Guard (#414, docs/design/standing-reactions.md). Guard itself is a BASIC main action everyone has
# — the doc's working model, and the one fork it deliberately left open — so there is no GUARD
# ability id here. What KIT grants is BRACE: bonus DEF applied to the absorbed instance, the single
# block-quality knob (bleed-through to the ward was dropped, not deferred). Bare Guard blocks at +0.
# Source-agnostic by construction: it rides the ability union (innate -> jobs -> worn gear), so a
# job, a carving or a piece of armour all grant it through one door. Weapons are not an ability
# source yet; that decision opens when the first weapon-granted bonus ships, not before.
const BRACE_DEF_BONUS := 3           # playtest-tunable
const GUARD_BASE_RANGE := 1          # authored on the granting content later; adjacency today

# Crisis (#158, 2026-08-09 — a Reaction-kind ability, the Berserker job's signature): while held,
# a full-Will would-be-down ALWAYS becomes the gambit — deterministic, previewed, no prompt for any
# faction. Equipping the source IS the acceptance. The gate itself (CRISIS_WILL_GATE) lives in
# LethalityRules beside OVERKILL_CEILING — it is the lethality ladder's knob; these are the
# gambit's EFFECTS, moved here from Unit when Crisis became an ability.
const CRISIS_REVIVE_HP := 5                            # HP the unit stands back up with (placeholder)
const CRISIS_SURGE := 5                                # +this to each scaling stat while surged (placeholder)
const CRISIS_SURGE_STATS: Array[Stats.Stat] = [Stats.Stat.STR, Stats.Stat.DEX, Stats.Stat.PER]  # "scaling stats" (assumption)
const CRISIS_SURGE_SOURCE := "Crisis"                  # the StatEffect this unit's surge is filed under
const CRISIS_SURGE_TURNS := 3                          # playtest-tunable: a gambit this costly should feel powerful (2026-07-28)
# Which ability confers immunity to which element (#90). THE map — Unit.is_immune_to is its only
# reader, and gear reaches immunity by GRANTING an ability rather than declaring elements itself.
# One id per element (the ratified fork): a piece blocking two elements grants two abilities. An
# element absent here has no insulation ability authored yet, which reads as "nobody is immune."
const INSULATION: Dictionary[Elemental.Element, Id] = {
	Elemental.Element.SHOCK: Id.INSULATED_SHOCK,
}
