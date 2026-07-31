class_name KineticMaceWeaponInstance
extends WeaponInstance

# Kinetic Mace's signature: charge -> Blowback (#84). `charge` is battle-scoped runtime state on
# THIS instance (non-@export, mirrors SpringspearWeaponInstance.ready / Chainsword's rev timer):
# resets each mission via make()/copy_equippable(), tracks per-physical-weapon. Reuses the #73
# readiness seam, reinterpreted as a COUNTER rather than a bool (the generalization #84 flagged).
#
# Every question here is answered by the ATTACK'S OWN AUTHORED FLAGS (#108). This class used to
# infer the charge-spender from `knockback > 0` -- a private predicate for a fact
# requires_readiness/consumes_readiness already carried. Consequences, all real: authoring either
# flag on a mace attack was silently inert, every non-knockback attack banked a charge whether or
# not its content said so, and adding knockback to any future mace attack would have quietly
# rewired the family's whole economy. Design law #4 -- one question, one answer. `builds_readiness`
# is the third state the seam was missing, and the reason the shortcut got invented in the first
# place.
#
# Doctrine (dev, 2026-07-28): a COUNTER banks charge. It stamps main, and main builds -- swinging
# the mace into an enemy is what stores the kinetic energy, and a counter is still that swing. That
# is now an authored property of Smash rather than a side effect of how the predicate was written,
# so changing it is a content edit, not a code change.
const MAX_CHARGE := 3

var charge := 0

func is_attack_fireable(attack: WeaponAttackData) -> bool:
	return charge >= 1 or not attack.requires_readiness

# Post-fire economy. Spend and bank are independent clauses, not an if/else: an attack that
# declared both would net out honestly instead of one silently winning.
func consume_readiness_for(attack: WeaponAttackData) -> void:
	if attack == null:
		return
	if attack.consumes_readiness:
		charge = maxi(0, charge - 1)
	if attack.builds_readiness:
		charge = mini(MAX_CHARGE, charge + 1)

func status_text() -> String:
	if charge <= 0:
		return "Charge 0/%d — Blowback unavailable" % MAX_CHARGE
	return "Charge %d/%d" % [charge, MAX_CHARGE]

# Battle-state seam (#87) — the mission-boundary reset that had never been paid for: a mid-battle
# save was where this was first noticed missing. Clamped like the Carbine's magazine.
func capture_battle_state() -> Dictionary:
	return {"charge": charge}

func apply_battle_state(state: Dictionary) -> void:
	charge = clampi(int(state.get("charge", 0)), 0, MAX_CHARGE)
