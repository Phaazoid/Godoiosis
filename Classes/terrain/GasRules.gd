extends Resource
class_name GasRules

# How one gas BEHAVES (#508): the numbers its round step reads and what it does to a unit standing
# in it, one file per kind under Resources/GasRules/ named for the kind, edited in the inspector
# (dev, 2026-10-03). GasLook is the same shape for how it is DRAWN; the two never share a file,
# because a rule and a look have different owners.
#
# A kind with no file has no rules: it lies where it was put and never moves. Steam is the only one
# with a file (ruling 10).

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


static var _rules_by_kind: Dictionary = {}


# This kind's rules, or null when it has none. Cached for the process.
static func for_kind(kind: Gas.Kind) -> GasRules:
	if not _rules_by_kind.has(kind):
		var path := FOLDER + Gas.name_of(kind) + ".tres"
		_rules_by_kind[kind] = load(path) as GasRules if ResourceLoader.exists(path) else null
	return _rules_by_kind[kind]
