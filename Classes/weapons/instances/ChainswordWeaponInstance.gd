class_name ChainswordWeaponInstance
extends WeaponInstance

# Chainsword's signature mechanic: Rev (#84). `revved_turns_remaining` is battle-scoped runtime
# state on THIS instance (deliberately NOT @export, mirroring SpringspearWeaponInstance.ready): two
# chainswords in one inventory rev independently, and it never serializes — make()/copy_for_grant()
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

func status_text() -> String:
	if revved_turns_remaining > 0:
		return "Revved — %d turn(s) left (ignores DEF)" % revved_turns_remaining
	return "Not revved"

# Battle-state seam (#87). The remaining COUNT rides along, not just "is it revved" — reloading
# must not silently refresh the timer, which is the whole cost side of the ability.
func capture_battle_state() -> Dictionary:
	return {"rev": revved_turns_remaining}

func apply_battle_state(state: Dictionary) -> void:
	revved_turns_remaining = clampi(int(state.get("rev", 0)), 0, REV_DURATION_TURNS)
