class_name TransmutationData
extends Resource

# An inscribed reaction carved onto a rune — the thing that actually fires (docs/design/
# alchemy-kit.md). TIER = number of constituent elements (1 = single, 2 = combined, ...).
# Aura-scaled: a flat parallel to weapon stat-scaling, summed over the elements it uses.
# NOT equippable itself — it lives in a RuneData's `inscriptions`.

const AURA_FLOOR := 1   # min aura per constituent element needed to channel (before leeway)

@export var display_name: String = ""
@export var elements: Array[Elemental.Element] = []   # constituent elements; tier = size()
@export var power: int = 0
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var carving_cost: int = 0   # capacity it eats on a rune; 0 = derive from tier()
@export var popup: String = ""
@export var icon: Texture2D
# materia: DEFERRED — some carvings will require fuel; not modeled yet.

func tier() -> int:
	return elements.size()

# Capacity a rune spends to hold this carving. Defaults to tier; authorable higher for a
# physically larger carving (a fire WALL costs more than a fireball, both tier 1).
func cost() -> int:
	return carving_cost if carving_cost > 0 else tier()

# Aura scaling: power + the SUM of the wielder's aura across the constituent elements. A
# leeway-covered (0-aura) element adds nothing — channelable, but it doesn't scale.
# [Sum vs primary-only is an open balance knob — docs/design/alchemy-kit.md.]
func base_damage(wielder: Unit) -> int:
	var scaling := 0
	for e in elements:
		scaling += wielder.get_element_aura(e)
	return power + scaling

# Can this wielder channel it? Need AURA_FLOOR in each element; the runestone's `leeway`
# point(s) cover that many otherwise-deficient elements (a 0-aura element rides the leeway
# at no scaling). Default leeway 1 = always channeled through a rune.
func can_channel(wielder: Unit, leeway: int = 1) -> bool:
	var uncovered := 0
	for e in elements:
		if wielder.get_element_aura(e) < AURA_FLOOR:
			uncovered += 1
	return uncovered <= leeway
