class_name ChemicalSpitterWeaponInstance
extends WeaponInstance

# Chemical Spitter's signature: the TANK (#97). One injected vial loads a run of supercharged
# shots, and the tank IS the supercharge meter -- doctrine in docs/design/alchemy-kit.md.
#
# DELIBERATELY NOT THE READINESS SEAM. requires_readiness/consumes_readiness express GATING, and
# the one law of materia is that it never gates function: a dry spitter fires its ordinary Spray
# forever. Wiring the tank through those flags would be the Kinetic Mace's mistake in reverse --
# inferring an economy from a flag that means something else. is_attack_fireable stays inert here.
#
# `charges` is battle-scoped runtime state on THIS instance (non-@export, like the Carbine's
# shots_remaining): it never serializes, so make()/copy_for_grant() hand back an EMPTY tank every
# mission. Empty rather than full is the point -- the weapon is not born supercharged, and a
# mission's first injection is a real decision about a scarce item.
const TANK_SIZE := 3

var charges := 0


# The supercharge answer the substitution reads (WeaponInstance.effective_main) and the resolver
# threads. One number; is_supercharged is derived from it on the base.
func tank_charges() -> int:
	return charges


# THE INJECTION. Reload's verb, and the first in the game whose rearm consumes inventory -- which is
# the whole reason the seam takes a wielder now.
func reload_block_reason(wielder: Unit) -> String:
	if wielder == null:
		return "There is nobody holding it."
	if charges >= TANK_SIZE:
		return "The tank is full."
	if _vial_slot(wielder) < 0:
		return "No matching vial to inject."
	return ""


func reload(wielder: Unit) -> void:
	if reload_block_reason(wielder) != "":
		return
	wielder.inventory[_vial_slot(wielder)] = null   # the vial is gone; the tank is what remains
	charges = TANK_SIZE


func reload_label() -> String:
	return "Tank Injection"


func has_reload_verb() -> bool:
	return true


# The matching rule, and the same one the alchemist obeys: the vial answers for this weapon's
# element, or it is alkahest. Asked of the weapon's MAIN, so a prototype born fire wants sulfur
# while the generic corrosion spitter wants vitriol -- or, for either, the rare universal.
#
# ELEMENT-SPECIFIC FIRST. Alkahest is authored sparingly and answers for everything, so spending it
# on a spitter that had an ordinary vial in the next slot is the one outcome nobody would choose.
func _vial_slot(wielder: Unit) -> int:
	var element := _tank_element(wielder)
	var alkahest := -1
	for i in wielder.inventory.size():
		var vial := wielder.inventory[i] as VialData
		if vial == null or not vial.matches(element):
			continue
		if vial.is_alkahest:
			if alkahest < 0:
				alkahest = i
			continue
		return i
	return alkahest


# What this weapon burns. The main attack's authored element -- the vial supercharges, it never
# chooses (the ratified model, #97). Read through effective_main so a mod that replaced the main
# also moved what the tank takes; asked of the BASE form, since the empowered one is what the tank
# BUYS and cannot be what qualifies it.
func _tank_element(wielder: Unit) -> Elemental.Element:
	var main := base_main(wielder)
	return main.elemental_damage_type if main != null else Elemental.Element.NONE


func status_text() -> String:
	if charges <= 0:
		return "Tank empty -- fires its baseline"
	return "Tank %d/%d" % [charges, TANK_SIZE]


# Battle-state seam (#87), the Carbine's shape. Clamped on the way back in: a save written before
# TANK_SIZE was retuned downward must not hand back a deeper tank than the family allows.
func capture_battle_state() -> Dictionary:
	return {"charges": charges}


func apply_battle_state(state: Dictionary) -> void:
	charges = clampi(int(state.get("charges", 0)), 0, TANK_SIZE)


# Spending is the RESOLVER's call, not this class's: the outcome carries charge_spent so the queue
# row and both execution twins read one stamp (Law #2). This is the door they push.
func spend_charge() -> void:
	charges = maxi(0, charges - 1)
