class_name AttackData
extends Resource

# Shared base for anything a unit can FIRE: a weapon attack (WeaponAttackData) or an
# inscribed carving (TransmutationData). Carries the attack's identity, geometry, and
# combat flags — what every consumer (pattern reach, counter gate, ally-splash, target
# mode) reads without caring which kind it is. Damage math deliberately stays on the
# subclasses: carvings scale off the wielder's AURA, weapon attacks off the wielding
# WEAPON (scaling_blend + mods) — there is no shared damage surface. #72.

@export var display_name: String = ""
@export var power: int = 0
# THE GEOMETRY, in two halves (#808). RANGE is where the attack may be AIMED, in Manhattan steps,
# and lives here; SHAPE is the set of cells it then covers and lives in its own shared, named
# resource, so a line fired at range and a line swung in melee are ONE shape with two ranges.
#
# THE ANCHOR IS DERIVED FROM THE RANGE, never a flag (dev, 2026-09-06), and so is whether the shape
# TURNS (dev, 2026-09-07 -- #818):
#   max_range == 0  -- the shape sits on the ATTACKER and the aim is a FACING: the player points a
#                      cardinal and the whole shape TURNS to fire that way (the directional path, #25).
#   max_range >= 1  -- the shape sits on the AIMED cell and NEVER turns: it lands as drawn, grid-up
#                      reading as board north, however the aim got there.
# One question, so one field answers both. Reach owns the placement, since answering "where does
# this land" needs both halves and Reach is where that question already lives.
#
# A NULL SHAPE COVERS THE ANCHOR CELL ALONE. That is the single-target attack -- most of the
# authored roster -- and it is deliberately not a file: a "Single" shape in the library would say
# nothing about the variety the library exists to show. An EMPTY stamp is a different thing and
# covers nothing at all, which AttackLint blocks.
@export var min_range := 1
@export var max_range := 1
@export var max_and_a_half := false   # .5 step: bevel in the diagonal corners of the max ring
@export var attack_shape: AttackShape
@export var can_counter := true
@export var hits_allies := false
@export var hits_self := false
@export var targets: EquippableData.TargetMode = EquippableData.TargetMode.UNIT
@export var knockback: int = 0
# Deterministic shove (#84, Kinetic Mace): tiles this attack pushes its target directly away
# from the attacker, stopping at the first wall/unit/edge. 0 = no displacement (every attack
# today). Generic on purpose — a future air-blast rune could carry it too. Resolved by
# PlanResolver, applied on execute; the Kinetic Mace's Blowback is the first user.
# How this attack answers the height question at aim time (#258; judged by Reach.vertical_aim_ok,
# directional spreads exempt in v1 — their per-cell height question is the deferred footprint one):
#   RANGED — the target may sit up to up_tolerance above / down_tolerance below the attacker
#            (-1 = unlimited). A lob's climb ceiling is its up_tolerance; a gun stays -1.
#   MELEE  — dev ruling 2026-08-20: same step, or a facing half step — same elevation, or adjacent
#            across a ramp-legal edge (RulesService.height_step_ok). A sheer 1-level edge is
#            melee-illegal in BOTH directions; the tolerances are ignored.
# A null attack (bare fists) reads as MELEE — punching is melee.
# Named for what they MEAN, not the mechanism each uses (#473, was TOLERANCE/STEP): the dev read
# "tolerance" as the lob setting, which is arc_clearance below. Members keep their order, so every
# authored `vertical_rule = 1` still means melee — this was a source rename, never a content one.
enum VerticalRule { RANGED, MELEE }
@export var vertical_rule: VerticalRule = VerticalRule.RANGED
# In height UNITS since #427 — two per level, so a weapon reaching one level up authors 2. The whole
# stack speaks one unit (dev, 2026-08-23), which is what keeps Reach free of conversions and lets a
# later weapon reach a HALF level if that is ever wanted.
@export var up_tolerance: int = -1
@export var down_tolerance: int = -1
# How high the shot arcs above its own sightline mid-flight (#218's number, built 2026-08-20), in the
# same height units as the tolerances above.
# 0 = a flat shot; there is deliberately no unlimited sentinel ("nothing clears infinity" — dev).
# The sightline runs at eye height and the arc is the ONE trajectory both the legality check and
# the in-game bead trace read (Reach.sight_trace) — the drawn path IS the rule.
@export var arc_clearance: int = 0
@export var heals := false   # EITHER damage OR heal, never both; reinterprets base damage as HP restored
# A pure-utility attack (#126): SCALING is suppressed, so neither aura nor a weapon's stat blend can
# sneak damage into a damageless effect. Only the attack's own contribution — an elemental reaction's
# damage_bonus still lands, deliberately (dev, 2026-08-08). Mutually exclusive with `heals`.
@export var deals_no_damage := false
# Ignores a Guard (#414): the hit lands on whoever it was aimed at, bodyguard or no. The first entry
# in Guard's authored counterplay set — the others are positional (shove the blocker out of range,
# shove the ward, AoE the cluster) and need no flag. On the shared base beside the two above, so a
# weapon attack and a carving author it identically.
@export var pierces_guard := false
# May this attack be declared as a standing WATCH instead of fired (#413)? The capability lives on
# the shared base so a carbine's WeaponAttackData and a transmutation carving ride one mechanism,
# exactly like `heals` and `pierces_guard` before it. Authored stock on the carbines and
# mod-grantable through WeaponModData.can_overwatch_override -- the watch is the attack, so nothing
# about its geometry or payload is duplicated here.
@export var can_overwatch := false

# The physical DELIVERY of this attack's damage (#424) -- how the force arrives, which is what armour
# has an answer to. SEPARATE from the element set: a Fireball deals FIRE-kind damage and, separately,
# applies the fire effect; an ice spear deals PIERCE-kind damage and applies the ice effect. One kind
# per attack and one damage number, so mitigation stays a single subtraction. AUTHORED, never derived
# from sigils or family (dev, 2026-09-05: "too many of the transmutations pull from flavor rather than
# derivation" -- sheer cold is COLD, an ice spear is PIERCE). Members keep their order: BLUNT is the
# storage's own zero, and NONE is LAST because it is never authored -- delivered_kind() answers it
# for anything that deals no damage or heals, so "does this attack deal damage" keeps its one answer.
# The physical three, mechanically: PIERCE is a point (0D), SLASH a line (1D), BLUNT a plane (2D).
enum Kind { BLUNT, SLASH, PIERCE, FIRE, SHOCK, COLD, CORROSION, NONE }
@export var damage_kind: Kind = Kind.BLUNT

# What this attack SOUNDS like when it lands (#136). Null = no opinion, and AudioDirector falls
# through to the game's generic impact -- so this is authored where a family has a voice of its own
# and left alone everywhere else.
#
# ON THE SHARED BASE, so a weapon attack and a rune carving author it identically -- #485's ruling
# one field along: per FAMILY, every attack a weapon owned would sound alike, a mod-granted attack
# could bring no voice of its own, and an element's sound would need a second mechanism because a
# carving has no WeaponData to hang off. There is deliberately no fallback on the template; a
# family's sound IS its main attack's, or that is a second answer to what a blow sounds like.
@export var sound: AudioStream = null

# What this attack's elemental effect LOOKS like, per element it carries (#900) -- a named, shared
# EffectLook, empty meaning every value falls through to the Game tab's own. On the shared base
# rather than on WeaponAttackData because the Electric Rune is a shock attack too, and the question
# is about what an attack CARRIES rather than about where its element was authored.
#
# KEYED BY ELEMENT, and that is not a deferred seam wearing a dictionary: a carving resolves each
# distinct sigil separately, so the Electric Rune carries SHOCK and AIR today. A single reference
# would need a content migration the first time a second element earned a look, and it could not
# say which of two looks was which.
#
# The RULE stays global: SHOCK_ARC_RANGE and the order the hops light in are properties of
# electricity, so no attack may disagree about them (elemental-interactions.md). What an attack may
# author is everything on the other side of that line.
@export var effect_looks: Dictionary[Elemental.Element, EffectLook] = {}

# What this attack would deliver if it delivered `kind`: NONE for a heal or a pure-utility attack,
# the kind itself otherwise. ONE home for that rule -- delivered_kind() reads it for the authored
# field, WeaponInstance.effective_kind for the field with a mod's override composed on top.
func deliver(kind: Kind) -> Kind:
	if heals or deals_no_damage:
		return Kind.NONE
	return kind

func delivered_kind() -> Kind:
	return deliver(damage_kind)

# Player-facing spelling, lower case so it sits inside a sentence ("Damage 12, slash").
static func kind_name(kind: Kind) -> String:
	return Kind.keys()[kind].to_lower()

# Which elements THIS ATTACK AUTHORS -- the base carries none, a carving resolves its sigils, a
# weapon attack names one field (#900). It is the authored half of PlanResolver.elements_of, which
# calls it and adds the wielder's fitted mods on top: one answer with two readers, rather than the
# two hand-written branches that function used to carry.
#
# The Attack Editor asks THIS rather than elements_of, and the difference is the point: the editor
# authors a file and has no wielder, while a mod-granted element belongs to a weapon rather than to
# the attack. So an attack that gains SHOCK only from a fitted mod authors no look and plays the
# defaults -- correct, and worth knowing before it reads as a gap.
func authored_elements() -> Array[Elemental.Element]:
	var none: Array[Elemental.Element] = []
	return none


# The look this attack wears for one element, or null to inherit every value. The effects read
# through it; nothing else should reach into the dictionary.
func look_for(element: Elemental.Element) -> EffectLook:
	return effect_looks.get(element, null) as EffectLook


# The elements this attack may author a look for: what it carries, narrowed to what has an
# attack-scoped effect at all. Drawn by the Attack Editor, and the reason the section is absent on
# an ordinary sword swing rather than empty.
func lookable_elements() -> Array[Elemental.Element]:
	var found: Array[Elemental.Element] = []
	for element in authored_elements():
		if EffectLook.is_lookable(element) and not found.has(element):
			found.append(element)
	return found


func hits_map() -> bool:
	return targets == EquippableData.TargetMode.MAP or targets == EquippableData.TargetMode.BOTH

func hits_units() -> bool:
	return targets == EquippableData.TargetMode.UNIT or targets == EquippableData.TargetMode.BOTH

# How a readout PHRASES this attack's payload. The number stays per-kind (a carving scales off
# aura, a weapon attack off its weapon — #72 keeps damage math off this base), but the three-state
# question damages/heals/neither is answered HERE, so the two kinds can never word it differently.
# Takes the DELIVERED kind rather than reading damage_kind (#424): a fitted mod may have replaced
# it, and the caller holds the composed answer.
func payload_text(amount: int, kind: Kind) -> String:
	if deals_no_damage:
		return "No damage"
	if heals:
		return "Heals %d" % amount
	return "Damage %d, %s" % [amount, kind_name(kind)]

# The targeting channel's readout token (#135 round 2) — same one-spelling rule as payload_text,
# deliberately its own function: payload and targeting are different questions. Concise parens by
# dev call ("(unit)" / "(tile)" / "(unit/tile)"); Glossary's ATTACK_TARGETING entry explains them.
func targets_text() -> String:
	if targets == EquippableData.TargetMode.BOTH:
		return "(unit/tile)"
	return "(tile)" if targets == EquippableData.TargetMode.MAP else "(unit)"



# Does this attack aim by FACING rather than at a cell? Derived from the range and never stored --
# game.gd's targeting and the hover branch read it through Reach.is_directional_attack, and the
# AI's watch picker loops the four facings when it answers true. See #25.
func is_directional() -> bool:
	return max_range == 0

# The sentence under the Attack Editor's stamp grid, which has to say what the CENTRE is -- and
# that is the ANCHOR rule, so the attack answers it rather than the widget or the shape. The SHAPE
# cannot: it holds no range, which is the whole reason this lives here after #808. Reads through
# is_directional() so the caption cannot drift from the rule it describes.
func grid_caption(_field: String) -> String:
	if is_directional():
		return "Centre is the attacker. Aimed by facing -- the shape turns to it."
	return "Centre is the aimed cell. The shape lands as drawn; it never turns."


# What the arrow above that grid points at, which is the SAME question one word long, and therefore
# the same answer's job (#818). Two surfaces read it -- the Attack Editor's authoring grid and the
# read-only ShapePlate on the mod-fitting card -- and a label spelled twice is two labels: one of
# them would go on saying "forward" about a shape that no longer turns.
func grid_up_label(_field: String) -> String:
	return "^ forward" if is_directional() else "^ board north"

# Which SECTION of the Attack Editor's form each field belongs in, and the order both the sections
# and the rows inside them are drawn (#825). property_tips()'s exact shape and for its exact reason:
# the declaration lives beside the @export it describes, so the layout and the field cannot drift
# apart in different files, and a subclass MERGES its own fields into the sections this class
# already declares rather than restating the whole layout.
#
# EVERY exported field must land in exactly ONE section -- tests/dev/test_attack_editor_layout.gd
# refuses a field that is in none. That is what stops a new @export dropping silently out of the
# form the way #803's stamp row did, and it is why the editor needs no skip list any more: a field
# is drawn because it is declared here, not because nobody remembered to exclude it.
#
# GEOMETRY IS ONE SECTION. The range trio and the stamp used to sit at opposite ends of the page,
# which is half of what made the form unreadable -- and since #818 they answer one question
# together (where this lands, and whether it turns).
static func property_sections() -> Array[Dictionary]:
	var sections: Array[Dictionary] = [
		{"title": "Identity", "fields": PackedStringArray(["display_name"])},
		{"title": "Range and shape", "fields": PackedStringArray(["max_range", "min_range", "max_and_a_half", "attack_shape"])},
		{"title": "Who it can hit", "fields": PackedStringArray(["targets", "hits_allies", "hits_self", "pierces_guard"])},
		{"title": "Height", "fields": PackedStringArray(["vertical_rule", "up_tolerance", "down_tolerance", "arc_clearance"])},
		{"title": "Payload", "fields": PackedStringArray(["heals", "deals_no_damage", "power", "damage_kind", "knockback", "sound"])},
		{"title": "How it is used", "fields": PackedStringArray(["can_counter", "can_overwatch"])},
		# LAST because it is the biggest: one picker plus every look row the element has, which for
		# SHOCK is thirty-five. Placed above "How it is used" it would push two checkboxes off the
		# bottom of the form on the only attacks that have it.
		{"title": "What its element looks like", "fields": PackedStringArray(["effect_looks"])},
	]
	return sections


# A subclass's own fields, appended to a section this class already declares. Matched by TITLE
# rather than by index, so inserting a section above cannot silently move a subclass's rows into
# the wrong one; an unknown title is a push_error rather than a silent drop.
#
# The copy-then-assign is not ceremony: a PackedStringArray is a VALUE type, so appending to what
# the Dictionary hands back would append to a copy and change nothing (CLAUDE.md's sharp edge).
static func in_section(sections: Array[Dictionary], title: String, fields: PackedStringArray) -> Array[Dictionary]:
	for section in sections:
		if section["title"] == title:
			var merged: PackedStringArray = section["fields"]
			merged.append_array(fields)
			section["fields"] = merged
			return sections
	push_error("no section titled '%s' to merge %s into" % [title, fields])
	return sections


# Which fields do not apply to THIS attack as it stands right now (#825) -- the Attack Editor hides
# their rows and brings them back the instant the governing field moves (dev, 2026-09-07: hidden
# rather than greyed). An INSTANCE method, unlike the two statics above, because the answer is about
# this attack's own values; asked with has_method, exactly like grid_fields().
#
# EVERY ENTRY IS DERIVED FROM WHAT THE RULE ACTUALLY READS, never from what looks irrelevant:
#   is_directional()     -- min_range and max_and_a_half reach nothing, being read only through the
#                           ring (GridUtils.cells_within_blended_range), and a facing aim has none.
#   MELEE                -- Reach._vertical_rule_ok returns before either tolerance. arc_clearance
#                           is deliberately NOT here: the lane trace reads it whatever the rule.
#   deals_no_damage      -- both base_damage implementations return 0 before power or the blend.
#                           knockback and elemental_damage_type STAY: a damageless shove is Gust,
#                           and the element is applied separately from the damage number.
#   delivered_kind()     -- the SAME rule the None caption reads, so the hidden picker and the
#                           sentence standing in for it can never disagree about whether a kind is
#                           delivered. deliver() is that rule's one home.
# `scaling_blend` is named from here though only WeaponAttackData has it: the RULE is this class's
# (deals_no_damage suppresses scaling, per its own comment), and a name matching no row is ignored.
#
# Hiding has NO side effect -- a field keeps whatever it holds and comes back unchanged, so an
# authored tolerance under a MELEE rule survives being invisible.
func hidden_fields() -> PackedStringArray:
	var hidden: PackedStringArray = []
	if is_directional():
		hidden.append_array(["min_range", "max_and_a_half"])
	if vertical_rule == VerticalRule.MELEE:
		hidden.append_array(["up_tolerance", "down_tolerance"])
	if deals_no_damage:
		hidden.append_array(["power", "scaling_blend"])
	if delivered_kind() == Kind.NONE:
		hidden.append("damage_kind")
	# ...and the look section is absent unless this attack carries an element that HAS one (#900).
	# Its heading goes with it: a section drawn as a bare title over nothing is worse than no
	# section, and _draw_sections derives that rather than being told (see its own note).
	if lookable_elements().is_empty():
		hidden.append("effect_looks")
	return hidden


# What each field MEANS, for the dev tools' reflective editor (#473). Every field above carries a
# comment already, but a comment reaches nobody editing in the running game -- the Attack Editor
# draws these rows from get_property_list() and had no text on any of them, which is how a range
# edit landed in the wrong box of two adjacent lookalike spinboxes with nothing to say so.
#
# A FUNCTION rather than a const table, and not by preference: GDScript refuses to let a subclass
# declare a member its parent already has, so a `const PROPERTY_TIPS` here makes one on
# WeaponAttackData a parse error. A subclass overrides this and merges instead. It lives beside the
# @export it describes rather than in a table inside DevWidgets, so the tip and the field cannot
# drift apart in different files.
static func property_tips() -> Dictionary:
	return {
		"display_name": "What this attack is called wherever a player meets it -- the action menu, the queue row, a weapon's tooltip. Saving under a new name renames it.",
		"sound": "What this attack sounds like when it lands. Leave it empty and the blow makes the game's generic impact noise, which is what most attacks want -- author one where a weapon has a voice of its own. Set in Godot's own inspector; this form cannot pick an audio file.",
		"power": "Base damage before scaling. A weapon attack scales this off its weapon's stat blend and fitted mods; a carving scales it off the wielder's aura.",
		"min_range": "The CLOSEST cell this attack can be aimed at, in Manhattan steps. Untick Custom minimum range and it is 1, i.e. adjacent, which is what nearly every attack wants.\n0 also allows the attacker's OWN cell (a self-heal). Above 1 leaves a dead zone it cannot hit at all, which is how a carbine cannot shoot what has closed on it.\nMUST NOT EXCEED Max range: nothing refuses the pair, the attack simply reaches no cells and stops showing any range at all.",
		"max_range": "Placed at range OFF is max range 0, and it is a different kind of attack rather than a shorter one: the shape sits on the ATTACKER and the aim is a FACING -- the player points a direction and the whole shape TURNS to fire that way. That is what a cleave or a line is.\nON, this is the FURTHEST cell the attack can be aimed at, in Manhattan steps (no diagonals). The shape is PLACED on the aimed cell and never turns: it lands exactly as you drew it, so the grid's top is board north rather than a facing.",
		"max_and_a_half": "Adds a half step to the outer ring, bevelling its diagonal corners -- a reach of 2 and a half rather than 2 or 3.",
		"attack_shape": "The SHAPE this attack covers once aimed, picked from the shared library. Shapes are shared BY REFERENCE: editing one changes every attack that uses it. No shape at all = the aimed cell alone.",
		"can_counter": "May this attack be used when countering? A weapon always counters with its MAIN attack whatever is picked, so this only matters on a main.",
		"hits_allies": "Splash reaches your own side too, not just enemies.",
		"hits_self": "The attacker is a legal victim of its own attack.",
		"targets": "What an aim may land on -- a unit, a tile, or either.",
		"knockback": "Tiles the target is shoved directly away from the attacker, stopping at the first wall, unit or board edge. 0 = no shove.",
		"vertical_rule": "MELEE: same elevation at any range, or ONE adjacent ramp-connected half step. A sheer edge refuses in both directions and the two tolerances below are ignored entirely.\nRANGED: the tolerances below decide.\nThis also decides whether the in-game sight-line beads are DRAWN -- only a RANGED attack with a point (non-directional) pattern draws them.",
		"up_tolerance": "RANGED only: how many levels ABOVE the attacker a target may stand. -1 = unlimited, which is what a gun wants. A lob's climb ceiling.",
		"down_tolerance": "RANGED only: how many levels BELOW the attacker a target may stand. -1 = unlimited.",
		"arc_clearance": "How high the shot arcs above its own sight line mid-flight -- this is the LOB setting, not the tolerances above. 0 = a flat, straight shot. Higher clears taller walls to the far side. There is deliberately no unlimited value.",
		"heals": "Reinterprets the damage number as HP restored instead. An attack is either damage or a heal, never both.",
		"deals_no_damage": "Pure utility: scaling is suppressed, so neither aura nor a weapon's stat blend can sneak damage into a damageless effect. Mutually exclusive with Heals.",
		"pierces_guard": "Ignores a Guard -- the hit lands on whoever it was aimed at, bodyguard or no.",
		"damage_kind": "How the damage ARRIVES -- the thing armour can answer. Blunt is a plane (hammer, fist, thrown rock, a jet of water), slash a line (blade), pierce a point (spear, bullet, arrow, ice spear). Fire, shock, cold and corrosion are non-physical deliveries. SEPARATE from the element: a fireball is Fire kind AND applies the fire effect; an ice spear is Pierce AND applies the ice effect. Ignored on a heal or a no-damage attack, which read as None.",
		"effect_looks": "A named LOOK for this attack's elemental effect, shared with every other attack that names it -- so a family of shock weapons can share one feel and one of them can differ.\nEach row inherits the Game tab's value until you untick it. Leave the look empty and nothing changes; pick (none) and the effect plays exactly as the Game tab has it tuned.\nThe RULE is never in here: how far a current arcs is a property of electricity, not of an attack.",
		"can_overwatch": "Makes this an OVERWATCH attack, and only that -- it is aimed as a standing watch and never fired directly, so it does not appear in the attack menu, the AI never picks it, and it cannot be a weapon's main. It fires on the first enemy who enters the aimed cells during someone else's turn, once, then it is spent.",
	}
