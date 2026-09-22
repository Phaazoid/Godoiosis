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
# question, so AttackData answers it (is_directional, grid_caption, grid_up_label) and this class
# never asks. WHETHER the stamp turns is that same question: a self-anchored attack rotates it to
# the facing, an anchored one places it as drawn with grid-up reading as board north (#818).
#
# EMISSION ORDER IS A RULE (dev, 2026-09-06): cells come NEAR TO FAR along the facing, then left to
# right across it. Victim order is volley order, so this reproduces the retired classes' sequences
# cell for cell; and Reach._truncate (#756) needs a predecessor emitted before its successor, which
# the sort guarantees for any stamp.
#
# For an ANCHORED shape "the facing" is grid-up, so that same sort reads out in BOARD terms: the
# southern row first, then northward, west to east within a row. Still one rule and still fully
# deterministic (law #1), but it is no longer *nearest the attacker first* -- an anchored footprint
# has no attacker in it to be near. Ordering a placed blast outward from where it LANDS is a spread
# question, and #805 answered it WITHOUT touching this sort: a placed blast decides its membership by
# flooding outward from the impact, which supplies its own order, and Reach then filters the
# survivors back into this one. So emission order stays the shape's rule and the spread stays
# independent of it -- which it has to be, because this sort hands out a south arm before the centre
# that arm propagates through.
#
# A stamp is a SET -- a duplicated offset counts once. The centre is a legal member (dev,
# 2026-09-06): at range 0 it is the attacker's own cell in the footprint, and whether they are then
# a VICTIM stays hits_self's question (RulesService).
#
# Board-blind on purpose: this emits the shape and Reach decides what the terrain leaves standing.
#
# A shape is EITHER painted tiles OR PATHS, never both (#1079, dev 2026-09-22: "should the arrows be
# the thing making the shape?"). A path is how a SINGLE-TARGET swing is authored -- a start tile,
# then each tile in the order the attack reaches it, one path per swing; a tile may be revisited but
# never twice in a row. A path shape's tiles are exactly the tiles its paths visit, so tiles() is the
# one answer to what a shape covers and place() lays those down; the stamp is empty on a path shape.
# Resolving a path as a single-target swing is #1057's -- until then a path shape fires as an AoE
# over its tiles.
#
# Stored FLAT rather than as sub-resources: path_cells holds every path back to back and
# path_lengths says where each ends. A LibraryField copy is a shallow duplicate, which would share
# sub-resource objects with the library file, and a minted sub-resource id churns the .tres on every
# edit; two typed arrays behave exactly as `stamp` does. The pair is a DECLARED second
# representation: path_fault() is the one check that it is sound, and AttackLint blocks a shape
# that fails it.

# Grid space: the stamp is authored facing this way.
const FORWARD := Vector2i.UP

# What the library lists this shape as -- ResourceCatalog.by_name keys on it, falling back to the
# filename. A different string from the attack's own name, and deliberately: "Lance" is the attack,
# "Line 6" is the shape it fires, and Line Snipe fires the same one.
@export var display_name: String = ""
@export var stamp: Array[Vector2i] = [Vector2i.ZERO]
@export var path_cells: Array[Vector2i] = []
@export var path_lengths: Array[int] = []


# The stamp turned to face `dir` and set down on `anchor`, in emission order. Grid space reads
# forward as -y and right as +x; world space uses the facing and its right-hand perpendicular --
# the `side` the retired wide pattern used -- so a stamp is ROTATED, never mirrored, and a row
# authored left to right stays left to right from the shooter's point of view.
#
# `dir` is FORWARD for every anchored placement since #818, which is a rotation by zero: the maths
# is unchanged and the shape simply lands as drawn.
func place(anchor: Vector2i, dir: Vector2i) -> Array[Vector2i]:
	var side := Vector2i(-dir.y, dir.x)
	var keyed: Dictionary[Vector2i, Vector2i] = {}   # (forward, across) -> world cell; a set, so a duplicate folds
	for offset in tiles():
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


# Which tiles this shape covers, as grid-space offsets: its paths' tiles, each once in the order
# they are first visited, for a path shape; its stamp otherwise.
func tiles() -> Array[Vector2i]:
	return tiles_of(stamp, path_cells, path_lengths)


# tiles() over bare fields, so the grid can ask it by field name.
static func tiles_of(stamp_cells: Array[Vector2i], cells: Array[Vector2i], lengths: Array[int]) -> Array[Vector2i]:
	if lengths.is_empty():
		return stamp_cells
	var seen: Array[Vector2i] = []
	for cell in cells:
		if not seen.has(cell):
			seen.append(cell)
	return seen


func is_path_shape() -> bool:
	return not path_lengths.is_empty()


func path_count() -> int:
	return path_lengths.size()


# One path's tiles in the order they are hit, as offsets in grid space. Empty for an index past the
# end, and truncated rather than erroring on a malformed pair -- path_fault() is where that is judged.
func path_at(index: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var paths := split_paths(path_cells, path_lengths)
	if index >= 0 and index < paths.size():
		path.assign(paths[index])
	return path


# The flat pair read back as one Array[Vector2i] per path. Static, so the grid can edit the pair by
# field name without a second decoder.
static func split_paths(cells: Array[Vector2i], lengths: Array[int]) -> Array[Array]:
	var paths: Array[Array] = []
	var start := 0
	for length in lengths:
		var path: Array[Vector2i] = []
		for i in maxi(length, 0):
			if start + i < cells.size():
				path.append(cells[start + i])
		paths.append(path)
		start += maxi(length, 0)
	return paths


static func joined_cells(paths: Array[Array]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for path in paths:
		cells.append_array(path)
	return cells


static func joined_lengths(paths: Array[Array]) -> Array[int]:
	var lengths: Array[int] = []
	for path in paths:
		lengths.append(path.size())
	return lengths


# "" when the path pair is sound, otherwise what is wrong with it. Only a hand edit can break it --
# the grid keeps every rule -- so this is the check a malformed file meets, not a live one.
func path_fault() -> String:
	var total := 0
	for length in path_lengths:
		if length < 1:
			return "it has a path with no tiles"
		total += length
	if total != path_cells.size():
		return "its path lengths add up to %d tiles but %d are stored" % [total, path_cells.size()]
	if is_path_shape() and not stamp.is_empty():
		return "it has both painted tiles and paths"
	for path in split_paths(path_cells, path_lengths):
		for i in range(1, path.size()):
			if path[i] == path[i - 1]:
				var cell: Vector2i = path[i]
				return "a path visits %d,%d twice in a row" % [cell.x, cell.y]
	return ""


# Per-field text for the dev tools' reflective editor (#473) -- see AttackData.property_tips for
# why this is a function rather than a table.
static func property_tips() -> Dictionary:
	return {
		"display_name": "What this shape is called in the Attack Editor's shape picker. Name it after the SHAPE, not the attack that first used it -- other attacks will pick it up.",
		"stamp": "The cells the attack COVERS once aimed, as offsets from where it lands. Click them on the grid: the centre is where the attack lands, and the cell above it is one step toward the top of the grid.\nWhat the top MEANS depends on the attack's range. Max range 0 = the attacker's FACING, and the whole shape turns to wherever they point. Any other range = board NORTH, and the shape lands exactly as drawn however you aim it.\nAn empty stamp covers nothing.",
		"path_cells": "A PATH shape: the tiles a single-target swing hits, in order, drawn in the grid's Paths mode. Pick a path, then click tiles in the order the attack reaches them; the first click is where the swing starts. Each path is its own swing. A tile may be revisited, but never twice in a row.\nA shape is either painted tiles or paths: a path shape's tiles are exactly the ones its arrows touch. Switching modes clears the other kind, after a confirm.\nUntil single-target resolution lands, a path shape fires as an AoE over its tiles.",
		"path_lengths": "How many tiles each path holds, in path order. The grid writes it; it is what splits Path Cells into separate paths.",
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
