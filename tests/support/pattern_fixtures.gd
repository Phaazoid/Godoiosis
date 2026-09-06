# Attack-pattern builders for tests (#803). PRELOADED, not class_name'd, like squad_fixtures:
#   const P := preload("res://tests/support/pattern_fixtures.gd")
# A test builds its OWN geometry and never reads authored content (dev, 2026-09-06). The three
# named shapes are the retired classes' vocabulary -- a point attack at Manhattan range, a line
# ahead, a wide row ahead -- so a suite that only needs "a two-cell line" says so in one call.
extends RefCounted


# A point attack: aimed at any cell of the range ring, covering the aimed cell alone.
static func point(max_range := 1, min_range := 1, and_a_half := false) -> AttackPattern:
	var p := AttackPattern.new()
	p.max_range = max_range
	p.min_range = min_range
	p.max_and_a_half = and_a_half
	return p


# A self-anchored line: `length` cells straight ahead, nearest first. 0 = an empty stamp.
static func line(length := 2) -> AttackPattern:
	return wide(length, 1)


# A self-anchored spread `length` deep and `width` across (odd), nearest row first, left to right.
static func wide(length := 1, width := 3) -> AttackPattern:
	var cells: Array[Vector2i] = []
	var half := (width - 1) / 2
	for f in range(1, length + 1):
		for s in range(-half, half + 1):
			cells.append(Vector2i(s, -f))
	return stamped(0, cells)


# Any range with any stamp -- offsets in grid space, UP forward.
static func stamped(max_range: int, offsets: Array[Vector2i], min_range := 1) -> AttackPattern:
	var p := AttackPattern.new()
	p.max_range = max_range
	p.min_range = min_range
	p.stamp = offsets
	return p
