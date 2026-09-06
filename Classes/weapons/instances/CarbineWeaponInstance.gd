class_name CarbineWeaponInstance
extends WeaponInstance

# Carbine's signature: a magazine (#84). The #73 readiness BOOL read as a COUNTER — same seam, same
# two authored flags on the attack, just an int. Two differences from Springspear define the family:
# the economy gates the MAIN attack, and there is no secondary, so an empty magazine leaves the
# weapon with nothing to fire until a Reload main action. shots_remaining is battle-scoped runtime
# state on THIS instance (non-@export, like ready/charge/revved_turns_remaining): it never
# serializes, so make()/copy_for_grant() hand back a full magazine every mission. Topping off a
# partial magazine is legal — spending a turn now beats getting caught dry.
const MAGAZINE_SIZE := 2

var shots_remaining := MAGAZINE_SIZE

func is_attack_fireable(attack: WeaponAttackData) -> bool:
	return shots_remaining > 0 or not attack.requires_readiness

func can_reload() -> bool:
	return shots_remaining < MAGAZINE_SIZE

func reload() -> void:
	shots_remaining = MAGAZINE_SIZE

func consume_readiness_for(attack: WeaponAttackData) -> void:
	if attack.consumes_readiness:
		shots_remaining = maxi(0, shots_remaining - 1)

func status_text() -> String:
	if shots_remaining <= 0:
		return "Ammo 0/%d — needs Reload" % MAGAZINE_SIZE
	return "Ammo %d/%d" % [shots_remaining, MAGAZINE_SIZE]

# Battle-state seam (#87). Clamped on the way back in: a save written before MAGAZINE_SIZE was
# retuned downward must not hand back a magazine deeper than the family allows.
func capture_battle_state() -> Dictionary:
	return {"shots": shots_remaining}

func apply_battle_state(state: Dictionary) -> void:
	shots_remaining = clampi(int(state.get("shots", MAGAZINE_SIZE)), 0, MAGAZINE_SIZE)
