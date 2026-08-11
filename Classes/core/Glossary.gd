extends Object
class_name Glossary

# The game's term registry (#135): what every player-facing term MEANS, at two lengths — `short`
# is the one-line hover tooltip, `long_text` the glossary-page body. One entry carries both, so
# the tooltips and the Glossary screen can never drift apart. Read by GlossaryScreen (the page),
# MainActionMenu (menu-row hover text via ACTION_DATA "term" keys), info_panel (stat rows) and
# StateIcons/HoverPresenter (state and tile hovers).
#
# Two content rules, both Law #4:
#   - Numbers are INTERPOLATED from the constants that rule them (DOWN_WILL_COST, COVER_DEF, ...),
#     never retyped — tuning a value re-words the glossary for free.
#   - Elemental/terrain INTERACTIONS are composed from the authored reaction .tres data
#     (reaction_lines/terrain_reaction_lines), never hand-written — the page cannot claim what
#     the resolver doesn't do. Transmutation recipe→identity content is deliberately absent:
#     that is #75's discovery layer.

enum Term {
	# Squads
	SQUAD, LEADER, COHESION, SQUAD_SIZE,
	# Stats (one per Stats.Stat, plus the derived readout rows)
	MHP, STR, LDR, WIL, DEX, PER, CON, COH, MOV, WEIGHT, DEF,
	# Actions (one per MainActionMenu.ACTION_DATA row)
	EXECUTE_ORDERS, MOVE, GROUP_MOVE, ATTACK, WEAPON_ACTION, TRANSMUTATION, ABILITY_ACTION,
	RESCUE, RALLY, CAPTURE, SQUAD_UP, JOIN_SQUAD, LEAVE_SQUAD, DISBAND_SQUAD, WAIT,
	CANCEL_ACTIONS, INSPECT, END_TURN,
	# Elemental
	ELEMENTS, WET, REACTIONS,
	# Terrain
	TERRAIN_KINDS, WATER_TILE, BURNING, BLAZE, FROZEN, COVER,
	# Will & lifecycle
	DOWNED, CRISIS, MAIM, PROSTHETIC,
}

enum Category { SQUADS, STATS, ACTIONS, ELEMENTAL, TERRAIN, LIFECYCLE }

# Player-facing category names, in page order.
const CATEGORY_NAMES: Dictionary[Category, String] = {
	Category.SQUADS: "Squads",
	Category.STATS: "Stats",
	Category.ACTIONS: "Actions",
	Category.ELEMENTAL: "Elemental",
	Category.TERRAIN: "Terrain",
	Category.LIFECYCLE: "Will & Lifecycle",
}

# Built lazily rather than declared const so entry text can interpolate the constants that rule
# each mechanic — a const table can't call `%` on another class's consts.
static var _entries: Dictionary = {}

static func _table() -> Dictionary:
	if _entries.is_empty():
		_entries = _build_entries()
	return _entries

static func title(term: Term) -> String:
	return _table()[term]["title"]

static func short(term: Term) -> String:
	return _table()[term]["short"]

static func long_text(term: Term) -> String:
	return _table()[term]["long"]

static func category_of(term: Term) -> Category:
	return _table()[term]["category"]

# Terms of one category, in Term declaration order (the table is built in enum order).
static func terms_in(category: Category) -> Array[Term]:
	var result: Array[Term] = []
	for term: Term in _table():
		if category_of(term) == category:
			result.append(term)
	return result

# --- Bridges from the game's own vocabularies -----------------------------------------------
# Declared maps, walked by tests/law/test_glossary_coverage.gd — a new stat or state cannot
# ship without a glossary entry, because the bridge below stops compiling or the law test reds.

static func term_for_stat(stat: Stats.Stat) -> Term:
	const MAP: Dictionary[Stats.Stat, Term] = {
		Stats.Stat.MHP: Term.MHP, Stats.Stat.STR: Term.STR, Stats.Stat.LDR: Term.LDR,
		Stats.Stat.WIL: Term.WIL, Stats.Stat.DEX: Term.DEX, Stats.Stat.PER: Term.PER,
		Stats.Stat.CON: Term.CON, Stats.Stat.COH: Term.COH,
	}
	return MAP[stat]

static func term_for_tile_state(state: Terrain.TileState) -> Term:
	const MAP: Dictionary[Terrain.TileState, Term] = {
		Terrain.TileState.BURNING: Term.BURNING, Terrain.TileState.BLAZE: Term.BLAZE,
		Terrain.TileState.FROZEN: Term.FROZEN, Terrain.TileState.COVER: Term.COVER,
	}
	return MAP[state]

static func term_for_element_state(state: Elemental.State) -> Term:
	const MAP: Dictionary[Elemental.State, Term] = {
		Elemental.State.WET: Term.WET,
	}
	return MAP[state]

# --- Composed interaction lists ---------------------------------------------------------------
# One line per authored reaction, read off the live catalogs so a .tres retune re-words the
# glossary for free. The count therefore always equals the catalog's — pinned by the law test.

static func reaction_lines() -> Array[String]:
	var lines: Array[String] = []
	for reaction in ReactionCatalog.get_all():
		lines.append(_reaction_line(reaction))
	return lines

static func terrain_reaction_lines() -> Array[String]:
	var lines: Array[String] = []
	for reaction in TerrainReactionCatalog.get_all():
		lines.append(_terrain_reaction_line(reaction))
	return lines

static func _reaction_line(r: ElementalReaction) -> String:
	var trigger: String = Elemental.display_name(r.incoming_element)
	if r.required_state != Elemental.State.NONE:
		trigger += " vs a %s target" % Elemental.state_display_name(r.required_state)
	else:
		trigger += " on any target"
	var effects: Array[String] = []
	if r.damage_mult != 1.0:
		effects.append("x%s damage" % String.num(r.damage_mult))
	if r.damage_bonus != 0:
		effects.append("%+d damage" % r.damage_bonus)
	for state: Elemental.State in r.add_states:
		effects.append("applies %s" % Elemental.state_display_name(state))
	for state: Elemental.State in r.remove_states:
		effects.append("clears %s" % Elemental.state_display_name(state))
	return _assemble_line(trigger, effects, r.popup)

static func _terrain_reaction_line(r: TerrainReaction) -> String:
	var trigger: String = Elemental.display_name(r.incoming_element)
	if r.required_kind != Terrain.Kind.NONE:
		trigger += " on %s" % Terrain.kind_display_name(r.required_kind)
	if r.required_tile_state != Terrain.TileState.NONE:
		trigger += " on a %s tile" % Terrain.tile_state_display_name(r.required_tile_state)
	var effects: Array[String] = []
	for state: Terrain.TileState in r.add_tile_states:
		effects.append("sets %s" % Terrain.tile_state_display_name(state))
	for state: Terrain.TileState in r.remove_tile_states:
		effects.append("clears %s" % Terrain.tile_state_display_name(state))
	return _assemble_line(trigger, effects, r.popup)

static func _assemble_line(trigger: String, effects: Array[String], popup: String) -> String:
	var line: String = trigger
	if not effects.is_empty():
		line += ": " + ", ".join(effects)
	if popup != "":
		line += " (\"%s\")" % popup
	return line

# Every element the player can meet, composed from the enum so a new element auto-lists.
static func _element_roster() -> String:
	var names: Array[String] = []
	for element: Elemental.Element in Elemental.Element.values():
		if element != Elemental.Element.NONE:
			names.append(Elemental.display_name(element))
	return ", ".join(names)

# --- The entries ------------------------------------------------------------------------------

static func _build_entries() -> Dictionary:
	var e: Dictionary = {}

	# Squads
	e[Term.SQUAD] = {"category": Category.SQUADS, "title": "Squad",
		"short": "Units fight as squads: queue orders for the members, then execute the plan together.",
		"long": "Every unit belongs to exactly one squad, even when alone. A squad activates as a "
			+ "group — queue orders for its members, then Execute Orders runs the whole plan. Once a "
			+ "squad has acted it is spent for the turn. Members must stay within the leader's "
			+ "cohesion range, and a squad outnumbered unit-for-unit can still win: a squad's turn "
			+ "moves everyone."}
	e[Term.LEADER] = {"category": Category.SQUADS, "title": "Leader",
		"short": "The unit a squad forms around: capacity comes from its LDR, and the cohesion leash anchors to it.",
		"long": "The squad's anchor. Capacity comes from the leader's effective LDR (%d effective "
			% Squad.MEMBER_LDR_COST
			+ "LDR per member beyond the leader), every member must stay within cohesion range of "
			+ "the leader, and Group Move plans the whole formation around the leader's destination."}
	e[Term.COHESION] = {"category": Category.SQUADS, "title": "Cohesion",
		"short": "The leash: squadmates must stay in the leader's COH range, counted by walkable path, not straight line.",
		"long": "How far a squadmate may stand from its leader, measured in movement steps over "
			+ "terrain the member can actually cross — a wall between you breaks cohesion even when "
			+ "you are close. Orders that would break the leash are refused before they queue, and a "
			+ "member cut off after the fact (shoved away, ice melting under it) falls out of the "
			+ "squad into a squad of its own."}
	e[Term.SQUAD_SIZE] = {"category": Category.SQUADS, "title": "Squad Size (SQD)",
		"short": "Members over capacity. Capacity is 1 plus the leader's effective LDR, %d per member."
			% Squad.MEMBER_LDR_COST,
		"long": "How many units a squad can hold: the leader plus one member per %d effective LDR "
			% Squad.MEMBER_LDR_COST
			+ "the leader carries. A stronger leader fields a bigger squad."}

	# Stats
	e[Term.MHP] = {"category": Category.STATS, "title": "Max HP (MHP)",
		"short": "The health pool. CON's band shifts the ceiling.",
		"long": "Hit points. Reaching 0 does not simply kill — what actually happens is decided by "
			+ "the stakes ladder: see Downed, Crisis and Maim under Will & Lifecycle."}
	e[Term.STR] = {"category": Category.STATS, "title": "Strength (STR)",
		"short": "Raw power. Weapon damage draws on it through each weapon's scaling blend.",
		"long": "Every weapon blends its damage from STR, DEX, PER and CON in its own proportions, "
			+ "and heavy melee leans hardest on STR."}
	e[Term.LDR] = {"category": Category.STATS, "title": "Leadership (LDR)",
		"short": "Buys squad capacity: one squadmate per %d effective LDR." % Squad.MEMBER_LDR_COST,
		"long": "A leader's effective LDR sets how many units their squad can hold (%d per member "
			% Squad.MEMBER_LDR_COST
			+ "beyond the leader). PER's band nudges effective LDR up or down."}
	e[Term.WIL] = {"category": Category.STATS, "title": "Will (WIL)",
		"short": "The survival pool: a down costs %d Will; a full pool can arm Crisis."
			% UnitInstance.DOWN_WILL_COST,
		"long": "Will is what stands between a felled unit and permanent harm. Surviving a down "
			+ "spends %d Will; when the pool can't pay, the unit is maimed instead. Rally restores "
			% UnitInstance.DOWN_WILL_COST
			+ "your own Will (%d the first time, %d less each rally after), Intimidate drains an "
			% [Unit.RALLY_BASE, Unit.RALLY_FALLOFF]
			+ "enemy's, and a full pool (%d) plus the Crisis ability turns a would-be down into a "
			% UnitInstance.MAX_WILL
			+ "last stand."}
	e[Term.DEX] = {"category": Category.STATS, "title": "Dexterity (DEX)",
		"short": "Agility. Its band adds or removes MOV, and weapon blends draw on it.",
		"long": "Feeds weapon scaling blends, and its band shifts movement range — a point or two "
			+ "of DEX is the cheapest way to move further."}
	e[Term.PER] = {"category": Category.STATS, "title": "Perception (PER)",
		"short": "Awareness. Nudges effective LDR, and weapon blends draw on it.",
		"long": "Feeds weapon scaling blends, and its band nudges effective Leadership — a sharp-eyed "
			+ "leader runs a slightly bigger squad."}
	e[Term.CON] = {"category": Category.STATS, "title": "Constitution (CON)",
		"short": "Toughness: shifts max HP and multiplies worn armor into DEF.",
		"long": "Its band shifts max HP, worn armor blocks in proportion to CON (the same plate "
			+ "protects a tough unit more), and weapon blends draw on it."}
	e[Term.COH] = {"category": Category.STATS, "title": "Cohesion (COH)",
		"short": "Leash length as a leader: how far squadmates may stand, in path distance.",
		"long": "Read off the leader only — see Cohesion under Squads for how the leash works."}
	e[Term.MOV] = {"category": Category.STATS, "title": "Movement (MOV)",
		"short": "Tiles per move: base %d shifted by DEX's band." % UnitInstance.JOBLESS_MOV_BASE,
		"long": "How far a unit walks in one move order. Base %d, shifted by DEX's band. Losing a "
			% UnitInstance.JOBLESS_MOV_BASE
			+ "leg halves it; losing both pins it to 1."}
	e[Term.WEIGHT] = {"category": Category.STATS, "title": "Weight (WT)",
		"short": "Carried gear mass. Tracked only — no effect yet.",
		"long": "The summed weight of everything in the unit's inventory. Tracked but not yet fed "
			+ "into any rule."}
	e[Term.DEF] = {"category": Category.STATS, "title": "Defense (DEF)",
		"short": "Subtracted from incoming damage: armor scaled by CON, plus terrain cover.",
		"long": "Damage mitigation. Worn armor contributes its power scaled by CON, dug-in Cover "
			+ "adds +%d, and the total comes straight off every incoming hit." % Terrain.COVER_DEF}

	# Actions — the short line doubles as the action menu's hover tooltip.
	e[Term.EXECUTE_ORDERS] = {"category": Category.ACTIONS, "title": "Execute Orders",
		"short": "Run the squad's queued plan: moves together, then attacks, then reactions, then rescues and the rest.",
		"long": "Runs everything the squad has queued, in fixed phases: all moves land at once, then "
			+ "attacks resolve one by one, then reactions (counters and reactive heals), then the "
			+ "side actions — rescues, rallies and the like. The queue panel previews exactly what "
			+ "will happen; execution never deviates from it."}
	e[Term.MOVE] = {"category": Category.ACTIONS, "title": "Move",
		"short": "Walk this unit. Moving must be ordered before its main action, never after.",
		"long": "Queues a walk within the unit's MOV range. A unit that has already queued its main "
			+ "action for the turn can no longer add a move — plan the approach first."}
	e[Term.GROUP_MOVE] = {"category": Category.ACTIONS, "title": "Group Move",
		"short": "Move the whole squad as a formation around the leader's destination.",
		"long": "Pick a destination for the leader and the squad plans itself around it, everyone "
			+ "keeping cohesion. Destinations the squad cannot follow to are marked before you click."}
	e[Term.ATTACK] = {"category": Category.ACTIONS, "title": "Attack",
		"short": "Fire the equipped weapon's main attack.",
		"long": "Aims and queues the equipped weapon's main attack. Each unit gets one main action "
			+ "per turn — attack, rescue, rally and the other mains are exclusive."}
	e[Term.WEAPON_ACTION] = {"category": Category.ACTIONS, "title": "Weapon Action",
		"short": "The equipped weapon's other attacks and its self-verbs: reload, rev, burrow.",
		"long": "Everything the equipped weapon can do beyond its main attack: alternative attacks, "
			+ "plus the weapon's own verbs — reloading a magazine, revving a motor, digging in. "
			+ "Greyed entries say what they are missing."}
	e[Term.TRANSMUTATION] = {"category": Category.ACTIONS, "title": "Transmutation",
		"short": "Fire a carving inscribed on the equipped rune, paid for with elemental aura.",
		"long": "A rune carries inscribed carvings; firing one channels the wielder's elemental "
			+ "aura. A carving the wielder cannot pay for is listed greyed, with the reason."}
	e[Term.ABILITY_ACTION] = {"category": Category.ACTIONS, "title": "Ability Action",
		"short": "Verbs granted by a unit's abilities, like Intimidate.",
		"long": "Actions a unit's abilities unlock. Intimidate — draining an adjacent enemy's Will — "
			+ "is the first; more arrive with new abilities."}
	e[Term.RESCUE] = {"category": Category.ACTIONS, "title": "Rescue",
		"short": "Stand an adjacent downed ally back up at 1 HP.",
		"long": "Revives an adjacent downed ally at 1 HP before their clock runs out. The rescued "
			+ "unit is out of formation and spent for the turn — but alive."}
	e[Term.RALLY] = {"category": Category.ACTIONS, "title": "Rally",
		"short": "Steel yourself: restore %d Will, less each rally after the first." % Unit.RALLY_BASE,
		"long": "Restores the rallying unit's own Will — %d the first time this battle, %d less "
			% [Unit.RALLY_BASE, Unit.RALLY_FALLOFF]
			+ "with each repetition. It stops being offered once the returns run out."}
	e[Term.CAPTURE] = {"category": Category.ACTIONS, "title": "Capture Point",
		"short": "Claim the capture zone this unit stands on — or will stand on after its move.",
		"long": "Claims the objective zone at the unit's destination. Only available when the "
			+ "mission declares a capture objective there."}
	e[Term.SQUAD_UP] = {"category": Category.ACTIONS, "title": "Squad Up",
		"short": "Form a new squad with a unit in cohesion range.",
		"long": "Creates a squad from two solo units of the same faction within cohesion range. "
			+ "Neither may have queued orders or an already-spent turn."}
	e[Term.JOIN_SQUAD] = {"category": Category.ACTIONS, "title": "Join Squad",
		"short": "Join an existing squad whose leader is in cohesion range.",
		"long": "Adds this unit to a formed squad with room left (see Squad Size). The joiner must "
			+ "be within the leader's cohesion range."}
	e[Term.LEAVE_SQUAD] = {"category": Category.ACTIONS, "title": "Leave Squad",
		"short": "Leave the current squad and go solo.",
		"long": "The unit steps out of its squad into a squad of its own. Its old squad keeps its "
			+ "plan; the leaver starts fresh."}
	e[Term.DISBAND_SQUAD] = {"category": Category.ACTIONS, "title": "Disband Squad",
		"short": "Dissolve the squad: every member goes solo.",
		"long": "The leader dissolves the whole formation. Every member becomes a squad of one."}
	e[Term.WAIT] = {"category": Category.ACTIONS, "title": "Wait",
		"short": "Spend the squad's turn without acting.",
		"long": "Marks the squad as having acted this turn without doing anything. Sometimes "
			+ "holding position is the plan."}
	e[Term.CANCEL_ACTIONS] = {"category": Category.ACTIONS, "title": "Cancel Actions",
		"short": "Clear this unit's queued orders.",
		"long": "Removes everything this unit has queued this turn. The rest of the squad's plan "
			+ "stays put."}
	e[Term.INSPECT] = {"category": Category.ACTIONS, "title": "Inspect",
		"short": "Open the full readout: stats, limbs, abilities, inventory.",
		"long": "Docks the full panel for this unit — stats with their breakdowns, limb state, "
			+ "abilities and carried gear. Works on any unit, friend or foe."}
	e[Term.END_TURN] = {"category": Category.ACTIONS, "title": "End Turn",
		"short": "Pass play to the next faction.",
		"long": "Ends your faction's turn. Squads that have not acted give up their activation."}

	# Elemental
	e[Term.ELEMENTS] = {"category": Category.ELEMENTAL, "title": "Elements",
		"short": "Attacks can carry an element; on impact it reacts with what the target already holds.",
		"long": "The elements: %s. An attack tagged with one deposits it on impact, " % _element_roster()
			+ "where it reacts with whatever state the target already holds — see Reactions. Fire, "
			+ "Water, Earth, Air and Aether are the five base sigils; the rest arise from "
			+ "combinations."}
	e[Term.WET] = {"category": Category.ELEMENTAL, "title": "Wet",
		"short": "Soaked through. Some elements react hard with a wet target.",
		"long": "The soaked condition, left by water. Harmless on its own — the danger is what "
			+ "reacts with it. The interaction list below is the authored truth."}
	e[Term.REACTIONS] = {"category": Category.ELEMENTAL, "title": "Reactions",
		"short": "Element meets state, always the same way: reactions are fixed rules, never chance.",
		"long": "When an attack's element meets a state the target holds, the reaction changes "
			+ "damage and states by fixed, deterministic rules — no dice anywhere. The current "
			+ "authored reactions are listed below, straight from the data the resolver itself "
			+ "reads."}

	# Terrain
	e[Term.TERRAIN_KINDS] = {"category": Category.TERRAIN, "title": "Terrain",
		"short": "Ground types set movement cost and rules. Hover any unusual tile for its effect.",
		"long": "Every tile has a ground type — grass, mud, rock, tree, water — setting its movement "
			+ "cost and rules. Attacks can also change tiles: fire leaves ground burning, ice "
			+ "freezes water. Hovering a tile that is anything other than ordinary shows what it "
			+ "does."}
	e[Term.WATER_TILE] = {"category": Category.TERRAIN, "title": "Water",
		"short": "Impassable to most units. Waterwalkers cross it; frozen, it carries anyone.",
		"long": "Most units cannot enter water. A unit with Waterwalk crosses it freely, and frozen "
			+ "water is solid ground for everyone — until it thaws."}
	e[Term.BURNING] = {"category": Category.TERRAIN, "title": "Burning",
		"short": "On fire: %d damage to whoever stands here at end of turn. Burns out after %d turns."
			% [Terrain.BURNING_TILE_DAMAGE, TerrainStateManager.STATE_DURATIONS[Terrain.TileState.BURNING]],
		"long": "This ground is on fire: anyone standing on it takes %d damage at the end of the "
			% Terrain.BURNING_TILE_DAMAGE
			+ "turn. It burns out on its own after %d turns."
			% TerrainStateManager.STATE_DURATIONS[Terrain.TileState.BURNING]}
	e[Term.BLAZE] = {"category": Category.TERRAIN, "title": "Blaze",
		"short": "A fire that will not burn out: %d damage at end of turn, no timer."
			% Terrain.BURNING_TILE_DAMAGE,
		"long": "A standing fire — same end-of-turn damage as Burning (%d), but it never burns out "
			% Terrain.BURNING_TILE_DAMAGE
			+ "on its own."}
	e[Term.FROZEN] = {"category": Category.TERRAIN, "title": "Frozen",
		"short": "Frozen solid for %d turns. Frozen water can be walked on."
			% TerrainStateManager.STATE_DURATIONS[Terrain.TileState.FROZEN],
		"long": "Ice. Frozen water is walkable ground for any unit, for %d turns — mind where you "
			% TerrainStateManager.STATE_DURATIONS[Terrain.TileState.FROZEN]
			+ "are standing when it thaws."}
	e[Term.COVER] = {"category": Category.TERRAIN, "title": "Cover",
		"short": "Dug-in ground: +%d DEF to the occupant. Destroyed by attacks, never by time."
			% Terrain.COVER_DEF,
		"long": "Entrenchment — dug by a burrowing weapon. Whoever stands here gains +%d DEF. It "
			% Terrain.COVER_DEF
			+ "never expires, but a destructive hit removes it."}

	# Will & lifecycle
	e[Term.DOWNED] = {"category": Category.LIFECYCLE, "title": "Downed",
		"short": "Felled, not dead: %d turns to be rescued before dying. Any hit while down kills."
			% Unit.DOWNED_TURNS,
		"long": "A hit that would fell a unit downs it instead when its Will can pay (%d Will). A "
			% UnitInstance.DOWN_WILL_COST
			+ "downed unit is helpless: it dies when its %d-turn clock runs out, and any damaging "
			% Unit.DOWNED_TURNS
			+ "hit finishes it early. Rescue stands it back up at 1 HP. Massive overkill — more "
			+ "than %d past remaining HP — skips down entirely and kills outright."
			% LethalityRules.OVERKILL_CEILING}
	e[Term.CRISIS] = {"category": Category.LIFECYCLE, "title": "Crisis",
		"short": "Full Will plus the Crisis ability turns a would-be down into a last stand — up at %d HP, surged."
			% Abilities.CRISIS_REVIVE_HP,
		"long": "A unit holding the Crisis ability at full Will refuses its down: it stands back up "
			+ "at %d HP with +%d STR/DEX/PER for %d turns. The price is everything — Will locks at "
			% [Abilities.CRISIS_REVIVE_HP, Abilities.CRISIS_SURGE, Abilities.CRISIS_SURGE_TURNS]
			+ "0 for the rest of the battle, and the next would-be down is death, no ladder, no "
			+ "rescue."}
	e[Term.MAIM] = {"category": Category.LIFECYCLE, "title": "Maim",
		"short": "When Will can't pay for a down, a limb is lost instead. Permanently.",
		"long": "A down the Will pool cannot cover (%d Will) takes a limb instead — permanently. "
			% UnitInstance.DOWN_WILL_COST
			+ "Lost arms cost stats; one lost leg halves MOV, both pin it to 1. The inspect panel "
			+ "marks the limb next at risk."}
	e[Term.PROSTHETIC] = {"category": Category.LIFECYCLE, "title": "Prosthetic",
		"short": "A built replacement for a lost limb, with its own stat value.",
		"long": "A crafted limb installed in place of a lost one, carrying its own stat value — "
			+ "usually weaker than what it replaces, occasionally not."}

	return e
