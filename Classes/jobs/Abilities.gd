extends Object
class_name Abilities

# The canonical ability roster + tuning knobs (docs/design/jobs.md "The ability chassis").
# Id is the ability vocabulary — our own data type: no misspelling, autocompletes. It is
# persisted in .tres (AbilityData.id), so it is APPEND-ONLY: NONE stays first, new abilities
# go on the end, never reorder. Dispatch stays hardcoded at each hook site (resolver /
# counter path / action / movement), but every site reads its id and numbers from here,
# so the roster and the balance surface both live in one place.

enum Id { NONE, IRON_WILL, INTIMIDATION, TAUNT, WATERWALK }

const IRON_WILL_DAMAGE_CAP := 6      # playtest-tunable
const INTIMIDATION_WILL_DRAIN := 3   # playtest-tunable
