class_name ChainswordWeaponInstance
extends WeaponInstance

# Chainsword's signature mechanic: Rev (#84). `revved_turns_remaining` is battle-scoped runtime
# state on THIS instance (deliberately NOT @export, mirroring SpringWeaponInstance.ready): two
# chainswords in one inventory rev independently, and it never serializes — make()/copy_equippable()
# always hand back a fresh 0, so it resets every mission. While revved, every attack from this
# weapon ignores the target's DEF (armor + terrain Cover), resolved by PlanResolver's mitigation
# stage. Ticks down one step at the wielder's faction turn start (game._tick_weapon_rev); re-Rev
# refreshes the full duration.
const REV_DURATION_TURNS := 3

var revved_turns_remaining := 0

func is_revved() -> bool:
	return revved_turns_remaining > 0

func can_rev() -> bool:
	return true

func rev() -> void:
	revved_turns_remaining = REV_DURATION_TURNS

func tick_rev() -> void:
	if revved_turns_remaining > 0:
		revved_turns_remaining -= 1

func ignores_def() -> bool:
	return is_revved()
