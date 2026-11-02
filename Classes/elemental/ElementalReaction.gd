extends Resource
class_name ElementalReaction

# A data rule: when an attack carrying `incoming_element` hits a target holding
# `required_state`, the reaction fires — changing damage and/or adding/removing
# states. docs/design/elemental-system.md ("Reactions as data").
#
# Resolution collects EVERY matching reaction and composes them per E8:
#   final = round(base * Π(damage_mult) + Σ(damage_bonus))   (state-deltas union)
#
# One primary element per reaction, plus `also_triggered_by` for the other elements it answers to
# (Heat, 2026-10-12: heat dries and melts what fire does). The primary is what the equation and
# ReactionLint explain; the extras are lore ("flame decays to heat"). A reaction fires at most ONCE
# per hit however many of its elements the hit carries, which is why the extras are a list here and
# never a second file (a second file would fire twice). Matching asks fires_for, never the field.
# Stacking ACROSS reactions (E8) works regardless.
#
# `required_state = NONE` means "no pre-existing state needed" — the reaction fires
# on the element alone. That's the SETUP half of a combo (e.g. WATER -> WET).

@export var incoming_element: Elemental.Element = Elemental.Element.NONE
@export var required_state: Elemental.State = Elemental.State.NONE
@export var also_triggered_by: Array[Elemental.Element] = []

# Deterministic damage change (Law #1 — no chance).
@export var damage_mult: float = 1.0
@export var damage_bonus: int = 0

# State changes applied when the reaction fires.
@export var add_states: Array[Elemental.State] = []
@export var remove_states: Array[Elemental.State] = []   # omit to NOT consume the state

# Optional duration override for `add_states` entries that expire (paired states — see
# Elemental.STATE_DEFAULT_TURNS). Absent/0 = the state's default. When several fired reactions
# add the same state, the LONGEST authored duration wins — max is commutative, so E8's
# order-independence holds.
@export var add_state_turns: Dictionary[Elemental.State, int] = {}

# Gas the reaction RELEASES on the cell the target was hit on (#1329): fire drying a wet unit boils
# its water off as steam. TerrainReaction's `gases`, one spelling for all three holders. Read through
# Gas.released.
@export var gases: Dictionary[Gas.Kind, Gas.Level] = {}

# The reaction as Deep Alchemy writes it, e.g. `F2 + W2 -> 2FW` (deep-alchemy.md). Read by
# ReactionLint only; nothing in play reads it yet. Empty = not written yet, a gap the lint's
# pending ledger declares.
@export_placeholder("F2 + W2 -> 2FW") var equation: String = ""

# Feedback. `popup` is read: the resolver lifts it onto the outcome. `vfx_tag` and `icon` are
# authored but read by nothing yet (#1443); TerrainReaction's `icon` is a separate field, and read.
@export var popup: String = ""        # e.g. "Electrocuted!"
@export var vfx_tag: String = ""
@export var icon: Texture2D           # e.g. the spark


# A COMBO needs a state already on the target; a NONE-requirement reaction is the SETUP half that
# deposits one (see the header). The queue row asks this to decide whether a fired reaction earns its
# own named line, or is already fully said by the state chip it produced (#685).
func is_combo() -> bool:
	return required_state != Elemental.State.NONE

# Does a hit carrying `elements` set this reaction off? The one question both resolver sites ask.
func fires_for(elements: Array[Elemental.Element]) -> bool:
	return Elemental.triggered(incoming_element, also_triggered_by, elements)

# The BADGE word, for a surface with no room for the dramatic one. A DECLARED second representation
# (Law #4): `popup` is what a reaction SHOUTS -- the glossary's composed interaction line and the bug
# report read it -- and this is what fits a ~40px chip in the action queue's row, measured. Blank
# means the popup already fits, so a reaction needs this only when its word is long.
@export var short_name: String = ""

func badge_name() -> String:
	return short_name if short_name != "" else popup


# The dev tools' form (Project > Alchemy > Reactions), section by section, AttackData.property_sections'
# shape: every exported field sits in exactly one section (tests/dev/test_alchemy_editor.gd).
static func property_sections() -> Array[Dictionary]:
	return [
		{"title": "When it fires", "fields": PackedStringArray(["incoming_element", "also_triggered_by", "required_state"])},
		{"title": "What it does", "fields": PackedStringArray(["damage_mult", "damage_bonus", "add_states", "remove_states", "add_state_turns"])},
		{"title": "What it releases", "fields": PackedStringArray(["gases"])},
		{"title": "Chemistry", "fields": PackedStringArray(["equation"])},
		{"title": "How it shows", "fields": PackedStringArray(["popup", "short_name", "vfx_tag", "icon"])},
	]


# Per-field text for that form (#473), beside the @export each one describes.
static func property_tips() -> Dictionary:
	return {
		"incoming_element": "The element a hit must carry to set this off. The one the equation and the lint explain.",
		"also_triggered_by": "Other elements that set it off too, e.g. Heat, which dries and melts what fire does. It still fires at most once per hit.",
		"required_state": "A state the target must already hold. None = the element alone sets it off: the SETUP half of a combo, which leaves a state for a later one.",
		"damage_mult": "Multiplies the hit's damage. Every matching reaction multiplies in, then the bonuses add: round(base x every mult + every bonus).",
		"damage_bonus": "Added to the hit's damage after every multiplier. Negative takes some away.",
		"add_states": "States the target gains when this fires.",
		"remove_states": "States it loses, e.g. a quick-dry takes Wet. Leave the required state unticked to keep it.",
		"add_state_turns": "How long an added state lasts, in turns. Unlisted = the state's own length. When two reactions add the same state, the longer wins.",
		"gases": "Gas released on the cell the target was hit on, e.g. steam off a wet body drying.",
		"equation": "The reaction as Deep Alchemy writes it, e.g. F2 + W2 -> 2FW. Read by the lint only: nothing in play reads it. The lines under it are what CI checks.",
		"popup": "What the reaction SHOUTS when it fires, e.g. Electrocuted! The queue row and the glossary read it too.",
		"short_name": "The badge word for the action queue's row, when the popup is too long to fit. Empty = the popup fits.",
		"vfx_tag": "Authored but read by nothing yet (#1443).",
		"icon": "The reaction's icon. Read by nothing yet (#1443). Set in Godot's own inspector: this form cannot pick a texture.",
	}
