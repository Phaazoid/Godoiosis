class_name SpringWeaponInstance
extends WeaponInstance

# Springspear's wind-up/recovery economy (#73). `ready` is deliberately NOT @export:
# runtime-only battle state that lives on THIS INSTANCE so two spears in one inventory track
# independently, and never serializes — make()/copy_equippable() always hand back a fresh
# `ready = true`, so it resets for free every mission (the same trick Unit.rally_count uses
# on the transient-node side of the persistence seam, just one layer down).
var ready := true

func is_attack_fireable(attack: WeaponAttackData) -> bool:
	return ready or not attack.requires_readiness

func can_reload() -> bool:
	return not ready

func reload() -> void:
	ready = true

func consume_readiness_for(attack: WeaponAttackData) -> void:
	if attack.consumes_readiness:
		ready = false
