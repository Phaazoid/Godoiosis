extends Resource
class_name AttackShape

# The SHAPE half of an attack's geometry: the cells it covers, as offsets from wherever it lands.
# The RANGE half lives on AttackData, and the split is the whole point of #808 -- a shape is
# SHARED BY REFERENCE between attacks (dev, 2026-09-06: "I wanted to save shapes as their own type
# of resource that could be loaded in and re-used"), and a shape carrying its own range would make
# "Line at range 0" and "Line at range 3" two files, which is the silliness #802 was filed to
# remove. Saved under Resources/AttackShapes/ and listed by AttackShapeCatalog.
#
# Was AttackPattern, which carried range and stamp together from #803 until the library landed; it
# in turn replaced three classes (Manhattan, ForwardLine, ForwardWide) whose own header said to
# consolidate rather than add a fourth.
#
# Authored in grid space where UP is forward (dev, 2026-09-06: "the top half of the grid
# intuitively represents forward"), on the Attack Editor's clickable grid (#804). Offsets are
# relative to the ANCHOR, and what the anchor IS -- the attacker, or the aimed cell -- is a RANGE
# question, so AttackData answers it (is_directional, grid_caption) and this class never asks.
#
# EMISSION ORDER IS A RULE (dev, 2026-09-06): cells come NEAR TO FAR along the facing, then left to
# right across it. Victim order is volley order, so this reproduces the retired classes' sequences
# cell for cell; and Reach._truncate (#756) needs a predecessor emitted before its successor, which
# the sort guarantees for any stamp.
#
# A stamp is a SET -- a duplicated offset counts once. The centre is a legal member (dev,
# 2026-09-06): at range 0 it is the attacker's own cell in the footprint, and whether they are then
# a VICTIM stays hits_self's question (RulesService).
#
# Board-blind on purpose: this emits the shape and Reach decides what the terrain leaves standing.

# Grid space: the stamp is authored facing this way.
const FORWARD := Vector2i.UP

# What the library lists this shape as -- ResourceCatalog.by_name keys on it, falling back to the
# filename. A different string from the attack's own name, and deliberately: "Lance" is the attack,
# "Line 6" is the shape it fires, and Line Snipe fires the same one.
@export var display_name: String = ""
@export var stamp: Array[Vector2i] = [Vector2i.ZERO]


# The stamp turned to face `dir` and set down on `anchor`, in emission order. Grid space reads
# forward as -y and right as +x; world space uses the facing and its right-hand perpendicular --
# the `side` the retired wide pattern used -- so a stamp is ROTATED, never mirrored, and a row
# authored left to right stays left to right from the shooter's point of view.
func place(anchor: Vector2i, dir: Vector2i) -> Array[Vector2i]:
	var side := Vector2i(-dir.y, dir.x)
	var keyed: Dictionary[Vector2i, Vector2i] = {}   # (forward, across) -> world cell; a set, so a duplicate folds
	for offset in stamp:
		var forward := -offset.y
		var across := offset.x
		keyed[Vector2i(forward, across)] = anchor + dir * forward + side * across
	var keys := keyed.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y)
	var out: Array[Vector2i] = []
	for key in keys:
		out.append(keyed[key])
	return out


# Per-field text for the dev tools' reflective editor (#473) -- see AttackData.property_tips for
# why this is a function rather than a table.
static func property_tips() -> Dictionary:
	return {
		"display_name": "What this shape is called in the Attack Editor's shape picker. Name it after the SHAPE, not the attack that first used it -- other attacks will pick it up.",
		"stamp": "The cells the attack COVERS once aimed, as offsets from where it lands. Click them on the grid: the centre is where the attack lands and the top of the grid is FORWARD, so the cell above the centre is one ahead. The whole shape turns to face the aim. An empty stamp covers nothing.",
	}


# Which of this resource's fields are CENTRED CELL STAMPS -- offsets around a 0,0 origin, which is
# what makes a clickable grid the right editor for them (#804). property_tips()'s shape and for its
# reason: the declaration lives beside the @export it describes, and DevWidgets asks with
# has_method, so the widget stays generic and no table anywhere can drift from the field.
#
# DECLARED rather than inferred from the type, and that is the whole point: ScenarioUnitEntry
# .watch_cells is an Array[Vector2i] too and holds ABSOLUTE board cells, so a grid centred on 0,0
# would be a lie about it. Nothing draws that entry reflectively today -- this keeps it that way by
# construction rather than by nobody having tried.
static func grid_fields() -> PackedStringArray:
	return ["stamp"]
