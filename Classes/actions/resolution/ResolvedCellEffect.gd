extends RefCounted
class_name ResolvedCellEffect

# One cell's resolved terrain consequences from a pass — the #47 cell-effect channel, now
# living under #50. Sibling of ResolvedOutcome but tile-facing. Preview AND execution consume
# the same object (R3): the resolver derives it at plan time, execution plays it back.

var cell: Vector2i
var states_added: Array[Terrain.TileState] = []
var states_removed: Array[Terrain.TileState] = []
var popups: Array[String] = []
var icons: Array[Texture2D] = []
# Gas LEVELS this cell gains, added to what it holds (#508): the reactions that fired here plus the
# attack's own deposit. GasField.apply plays it; a cell effect may carry gas and no state at all.
var gas_added: Dictionary[Gas.Kind, int] = {}
# Every gas the cell held is cleared FIRST, before gas_added lands (#1335: an Air hit disperses it).
# GasField.apply and projected_packed_at fold it in that order, so the forecast and both executors agree.
# A hit that shoves BLOWS the gas instead (#1332): the same clear here, plus the same levels in the
# gas_added of the effect on the tile it lands on, so a push needs no field of its own.
var gas_cleared := false


func add_gas(kind: Gas.Kind, levels: int) -> void:
	if levels > 0:
		gas_added[kind] = mini(gas_added.get(kind, 0) + levels, Gas.MAX_LEVEL)


# Everything one holder's `gases` releases (an attack's or a reaction's, #1335), in kind order.
func add_gases(gases: Dictionary[Gas.Kind, Gas.Level]) -> void:
	for kind: Gas.Kind in Gas.released(gases):
		add_gas(kind, gases[kind])
# The blow that deposited it, or null for an order's own deposit (Burrow's COVER). Live applies a
# pass's deposits in one batch, so nothing in playback reads this; the Split forecast does (#367),
# to hand a break over ice this pass melts to the fire that melted it.
var cause: AttackAction = null
