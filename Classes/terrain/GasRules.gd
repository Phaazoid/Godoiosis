extends Resource
class_name GasRules

# How one gas BEHAVES (#508): the numbers its round step reads and what it does to a unit standing
# in it, one file per kind under Resources/GasRules/ named for the kind, edited in the inspector
# (dev, 2026-10-03). GasLook is the same shape for how it is DRAWN; the two never share a file,
# because a rule and a look have different owners.
#
# A kind with no file has no rules: it lies where it was put and never moves (ruling 10). Steam, smoke,
# frost and essence have files.

const FOLDER := "res://Resources/GasRules/"

# Rounds a cell holds a level before it thins one step. The hold counter lives in two bits of the
# packed cell (Gas.MAX_AGE), so it cannot go past four.
@export_range(1, 4) var hold_rounds := 2

# What a unit still standing in this gas when its OWN side's turn ends gains (#508 PR 3), and the
# thinnest level that gives it -- fire's end-of-turn burn, with a state instead of damage. Thin steam
# stays harmless so a wisp does not keep anyone wet (dev, 2026-10-04). NONE is a gas that touches
# nobody.
@export var state: Elemental.State = Elemental.State.NONE
@export var state_from: Gas.Level = Gas.Level.MEDIUM

# HOW the state is given (#1335). Off: gained at the end of its own side's turn, and kept (steam's
# soak). On: HELD for exactly as long as the unit stands in the gas at state_from or thicker, and
# stored nowhere, so the gas field stays the one answer -- smoke blinds whoever is in the cloud (dev,
# 2026-10-22). Read where the board is asked: the leash (SquadCohesion.reach_at) and the status row.
@export var while_standing := false

# How this gas moves the air's reading on the cell it lies on (#1324): substance id -> percentage
# points PER LEVEL, negative to lower. WeatherRules.air's shape; BoardContext.air_at adds it over the
# board's reading. The one answer to what a gas does to the air -- SubstanceMap.GASES says what the gas
# IS, for presence, and a formula cannot say what a gas has taken away. A missing key moves nothing.
@export var air: Dictionary[String, int] = {}


static var _rules_by_kind: Dictionary = {}


# This kind's rules, or null when it has none. Cached for the process.
static func for_kind(kind: Gas.Kind) -> GasRules:
	if not _rules_by_kind.has(kind):
		var path := FOLDER + Gas.name_of(kind) + ".tres"
		_rules_by_kind[kind] = load(path) as GasRules if ResourceLoader.exists(path) else null
	return _rules_by_kind[kind]


# The states a unit standing on this cell HOLDS while it stands there (`packed`, Gas.with_level's form):
# every while_standing gas lying at its state_from or thicker, in kind order, each state once.
static func states_while_standing(packed: int) -> Array[Elemental.State]:
	var out: Array[Elemental.State] = []
	for kind: Gas.Kind in Gas.kinds_in(packed):
		var rules := for_kind(kind)
		if rules == null or not rules.while_standing or rules.state == Elemental.State.NONE:
			continue
		if Gas.level_in(packed, kind) >= rules.state_from and not out.has(rules.state):
			out.append(rules.state)
	return out


# What standing in this kind at this level does, as the tile card says it ("Smoked: -2 COH"); empty
# when it does nothing there.
static func standing_text(kind: Gas.Kind, level: int) -> String:
	var rules := for_kind(kind)
	if rules == null or not rules.while_standing or rules.state == Elemental.State.NONE \
			or level < rules.state_from:
		return ""
	var parts: Array[String] = []
	var mods := Elemental.paired_stat_mods(rules.state)
	for stat: Stats.Stat in mods:
		parts.append("%+d %s" % [mods[stat], Stats.Stat.keys()[stat]])
	var said := Elemental.state_display_name(rules.state)
	return said if parts.is_empty() else "%s: %s" % [said, ", ".join(parts)]


# How one cell's gases move the air (`packed`, Gas.with_level's form): each kind's air times its level,
# summed. The nudge Atmosphere.nudged takes, WeatherRules.air_of's twin for a cell.
static func air_of(packed: int) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	for kind: Gas.Kind in Gas.kinds_in(packed):
		var rules := for_kind(kind)
		if rules == null:
			continue
		var level := Gas.level_in(packed, kind)
		for id: String in rules.air:
			out[id] = int(out.get(id, 0)) + rules.air[id] * level
	return out


# What this kind does to the air at this level, as a readout says it ("elemental aether +10%, vapor
# -10%"), in Atmosphere.SUBSTANCES order. Empty when it moves nothing.
static func air_text(kind: Gas.Kind, level: int) -> String:
	var rules := for_kind(kind)
	if rules == null:
		return ""
	var parts: Array[String] = []
	for id: String in Atmosphere.SUBSTANCES:
		var points := int(rules.air.get(id, 0)) * level
		if points != 0:
			parts.append("%s %+d%%" % [SubstanceCatalog.name_of(id).to_lower(), points])
	return ", ".join(parts)
