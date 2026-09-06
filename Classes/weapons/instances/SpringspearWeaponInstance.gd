class_name SpringspearWeaponInstance
extends WeaponInstance

# Springspear's wind-up/recovery economy (#73). `ready` is deliberately NOT @export:
# runtime-only battle state that lives on THIS INSTANCE so two spears in one inventory track
# independently, and never serializes — make()/copy_for_grant() always hand back a fresh
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

func status_text() -> String:
	return "Loaded" if ready else "Spent — needs Spring Load"

func reload_label() -> String:
	return "Spring Load"

# Battle-state seam (#87). The default matches make()'s: an entry that never saved this reads back
# as a loaded spear, so a pre-#87 scenario loads exactly as it always did.
func capture_battle_state() -> Dictionary:
	return {"ready": ready}

func apply_battle_state(state: Dictionary) -> void:
	ready = bool(state.get("ready", true))
