class_name RuneData
extends EquippableData

# A blank rune is alkahest-saturated runestone — element/pattern AGNOSTIC until an alchemist
# INSCRIBES transmutation carvings onto it. The carvings (TransmutationData) are the attacks;
# the rune is the customizable LOADOUT that holds them (docs/design/alchemy-kit.md).
#
# Size = capacity budget; a carving costs capacity (~ its tier). Channeling a held carving
# also needs the wielder's AURA — but the runestone grants one free leeway point, so a 0-aura
# unit can still channel the simplest carving of an element (see TransmutationData.can_channel).
#
# Equippable (inherits the EquippableData slot surface). FIRING a chosen inscription through
# the resolver is the next slice; the inherited single-attack fields stay dormant until then.

enum Size { SMALL, MEDIUM, LARGE }   # APPEND-ONLY (serialized as int)

const CAPACITY := {
	Size.SMALL: 1,    # beginner's tool — one basic (tier-1) carving
	Size.MEDIUM: 6,   # e.g. 3x tier-2, or a tier-3 + a tier-1
	Size.LARGE: 12,   # the big board
}   # placeholder balance — the curve is open (docs/design/alchemy-kit.md)

const RUNE_LEEWAY := 1   # the runestone's free channeling point (alkahest saturation)

@export var size: Size = Size.SMALL
@export var inscriptions: Array[TransmutationData] = []

func capacity() -> int:
	return CAPACITY[size]

func used_capacity() -> int:
	var total := 0
	for t in inscriptions:
		total += t.cost()
	return total

func remaining_capacity() -> int:
	return capacity() - used_capacity()

func can_inscribe(t: TransmutationData) -> bool:
	return t != null and t.cost() <= remaining_capacity()

func inscribe(t: TransmutationData) -> bool:
	if not can_inscribe(t):
		return false
	inscriptions.append(t)
	return true

# The held carvings this wielder can actually channel (aura gate + the rune's leeway point).
func channelable(wielder: Unit) -> Array[TransmutationData]:
	var result: Array[TransmutationData] = []
	for t in inscriptions:
		if t.can_channel(wielder, RUNE_LEEWAY):
			result.append(t)
	return result
