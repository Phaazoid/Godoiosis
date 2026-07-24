class_name KineticMaceWeaponInstance
extends WeaponInstance

# Kinetic Mace's signature: charge -> Blowback (#84). `charge` is battle-scoped runtime state on
# THIS instance (non-@export, mirrors SpringWeaponInstance.ready / Chainsword's rev timer): resets
# each mission via make()/copy_equippable(), tracks per-physical-weapon. A normal attack BUILDS +1
# charge (capped); the Blowback attack (any attack with knockback > 0) REQUIRES and SPENDS 1. No
# reload action needed — charge accrues from attacking. Reuses the #73 readiness seam's fireability
# gate + post-fire hook, reinterpreted as a counter (the bool -> count generalization #84 flagged).
const MAX_CHARGE := 3

var charge := 0

func _is_blowback(attack: WeaponAttackData) -> bool:
	return attack != null and attack.knockback > 0

func is_attack_fireable(attack: WeaponAttackData) -> bool:
	return charge >= 1 if _is_blowback(attack) else true

func consume_readiness_for(attack: WeaponAttackData) -> void:
	# Post-fire economy: a Blowback spends a charge, any other attack banks one (capped).
	if attack == null:
		return
	if _is_blowback(attack):
		charge = maxi(0, charge - 1)
	else:
		charge = mini(MAX_CHARGE, charge + 1)
