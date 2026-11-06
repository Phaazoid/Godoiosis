extends Object
class_name Pace

# How fast the ROUND runs a thing in one cell (#1311), the time pair's one answer. Not Pacing, which is
# playback's pauses: this is the board's round clock.
#
# Still(X) HOLDS what is made of X and Quicken(X) runs it TWICE (docs/design/deep-alchemy.md -> Quicken
# and Still). A carving lays a MARK on every cell its circle strikes, one per substance its time verbs
# name, for TransmutationData.time_rounds rounds; TerrainStateManager stores them and the round reads them
# through here. A mark reaches a thing by what the thing is MADE of: a tile state or gas whose SubstanceMap
# row makes X present (CellSubstances.present_from, the walk a cast's presence is), so Still(F) holds a fire,
# whose row names heat, and leaves the smoke over it alone. A mark sits on the CELL, so what arrives there
# later runs at its pace too.
#
# Kind is SAVED (a cell's marks are substance id -> Vector2i(Kind, rounds left)), so it is APPEND-ONLY.

enum Kind { NORMAL, HELD, QUICK }


static func mark(kind: Kind, rounds: int) -> Vector2i:
	return Vector2i(kind, rounds)


static func kind_of(marked: Vector2i) -> Kind:
	return marked.x as Kind


static func rounds_of(marked: Vector2i) -> int:
	return marked.y


# The pace a thing made of `made_of` runs at under one cell's `marks`: HELD where a Still names what it is
# made of, else QUICK where a Quicken does, else NORMAL. Still wins a clash: nothing runs fast while held.
static func of(marks: Dictionary, made_of: Array[String]) -> Kind:
	if marks.is_empty() or made_of.is_empty():
		return Kind.NORMAL
	var present := CellSubstances.present_from(made_of)
	var quick := false
	for id: String in marks:
		if not present.has(id):
			continue
		match kind_of(marks[id]):
			Kind.HELD:
				return Kind.HELD
			Kind.QUICK:
				quick = true
	return Kind.QUICK if quick else Kind.NORMAL


static func of_tile_state(marks: Dictionary, state: Terrain.TileState) -> Kind:
	if marks.is_empty():
		return Kind.NORMAL
	return of(marks, SubstanceMap.authored().of_tile_state(state))


static func of_gas(marks: Dictionary, kind: Gas.Kind) -> Kind:
	if marks.is_empty():
		return Kind.NORMAL
	return of(marks, SubstanceMap.authored().of_gas(kind))


# One effect's marks laid over a cell's: each replaces the old mark on its substance (#1311 ruling 6).
static func laid(marks: Dictionary, added: Dictionary[String, Vector2i]) -> Dictionary:
	var result := marks.duplicate()
	for id: String in added:
		result[id] = added[id]
	return result


# A cell's marks one round older: each loses a round and goes at none. Empty when nothing is left.
static func aged(marks: Dictionary) -> Dictionary:
	var result := {}
	for id: String in marks:
		var marked: Vector2i = marks[id]
		if rounds_of(marked) > 1:
			result[id] = mark(kind_of(marked), rounds_of(marked) - 1)
	return result
