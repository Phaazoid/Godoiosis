# Attack-GEOMETRY builders for tests (#803, re-shaped by #808). PRELOADED, not class_name'd, like
# squad_fixtures:
#   const P := preload("res://tests/support/shape_fixtures.gd")
# A test builds its OWN geometry and never reads authored content (dev, 2026-09-06). The three named
# shapes are the retired classes' vocabulary -- a point attack at Manhattan range, a line ahead, a
# wide row ahead -- so a suite that only needs "a two-cell line" says so in one call.
#
# Each takes the ATTACK and returns it: geometry is two halves now (a RANGE on the attack, a SHAPE
# resource beside it), and a builder handing back only the shape could not say what range it wanted.
# The shapes built here are UNNAMED and unsaved, which is what keeps a suite off the library --
# a test that shared a library file would be pinning authored content.
extends RefCounted


# A point attack: aimed at any cell of the range ring, covering the aimed cell alone.
static func point(attack: AttackData, max_range := 1, min_range := 1, and_a_half := false) -> AttackData:
	attack.max_range = max_range
	attack.min_range = min_range
	attack.max_and_a_half = and_a_half
	attack.attack_shape = null
	return attack


# A self-anchored line: `length` cells straight ahead, nearest first. 0 = an empty stamp.
static func line(attack: AttackData, length := 2) -> AttackData:
	return wide(attack, length, 1)


# A self-anchored spread `length` deep and `width` across (odd), nearest row first, left to right.
static func wide(attack: AttackData, length := 1, width := 3) -> AttackData:
	var cells: Array[Vector2i] = []
	var half := (width - 1) / 2
	for f in range(1, length + 1):
		for s in range(-half, half + 1):
			cells.append(Vector2i(s, -f))
	return stamped(attack, 0, cells)


# Any range with any stamp -- offsets in grid space, UP forward.
static func stamped(attack: AttackData, max_range: int, offsets: Array[Vector2i], min_range := 1) -> AttackData:
	attack.max_range = max_range
	attack.min_range = min_range
	attack.attack_shape = shape(offsets)
	return attack


# A bare shape, for a suite that needs the resource itself (the stamp grid's, the library's).
static func shape(offsets: Array[Vector2i], shape_name := "") -> AttackShape:
	var s := AttackShape.new()
	s.display_name = shape_name
	s.stamp = offsets
	return s
