extends Resource
class_name UnitInstance

#This resource represents a runtime instance of a character.  This is where we will store persistent changes to units such as
#stat changes, limb loss, weapon proficiency, job stats, etc. 

@export var data: UnitData

signal died
signal hp_changed(current, max)
signal will_changed(current, max)

#Permanent stat storage (base + growth gains, other permanent additions)
var stats: Dictionary = {}

#all buffs and debuffs from everything. Terrain, items, enemy attacks, etc. 
var stat_modifiers: Dictionary = {}

#Battle stats
var current_hp: int = 0
#effective str, other things here

# --- Will (docs/design/will-and-death.md — the limb/integrity buffer, 2026-06-24 reframe) ---
# PERSISTENT, per-unit: lives here on UnitInstance (survives missions, like limb loss) — the
# opposite side of the persistence seam from the battle-scoped lifecycle state on Unit.
# Reframe: Will gates LIMBS, not life. A would-be-fatal sub-overkill hit ALWAYS downs you;
# Will only decides whether that down is clean or MAIMED. Will never directly kills.
const DOWN_WILL_COST := 5           # flat cost paid per down (placeholder). Can't pay it -> maim.
const MAX_WILL := 20                # ceiling for the WIL-stat-derived Will pool (a cap, not a flat value).
var current_will: int = 0

# Which limb a maim takes. Default ARM for now; the deterministic choice (stat-derived, Law #1)
# is an open design knob. NONE = not maimed. Persists (limb loss survives missions).
enum MaimedPart { NONE, ARM_LEFT, ARM_RIGHT, LEG_LEFT, LEG_RIGHT }
var maimed_part: MaimedPart = MaimedPart.NONE

func initialize():
	if data == null:
		push_error("UnitInstance has no UnitData assigned.")
		return
	#base current stats off of the data without editing the values in UnitData that we're pulling from
	stats = data.base_stats.duplicate(true) 
	
	#reset battle stats
	_refresh_derived_stats()
	current_hp = get_base_stat(Stats.Stat.MHP)
	current_will = get_max_will()

func get_base_stat(stat_name: Stats.Stat) -> int:
	if stats.has(stat_name):
		return stats[stat_name]
	return 0

func _refresh_derived_stats():
	#Placeholder for - 
	#item bonuses
	#job modifiers
	#debuffs
	#passives
	#literally anything that can change stats
	pass

func get_current_hp() -> int:
	return current_hp
	
func set_current_hp(value: int):
	current_hp = clamp(value, 0, get_base_stat(Stats.Stat.MHP))
	emit_signal("hp_changed", current_hp, get_base_stat(Stats.Stat.MHP))

	if current_hp <= 0:
		emit_signal("died")

func apply_damage(amount: int):
	set_current_hp(current_hp - amount)

func is_dead() -> bool:
	return current_hp <= 0

# --- Will API ---

func get_max_will() -> int:
	# Max Will = the unit's WIL stat (per-unit; set via the dev editor / UnitData), capped at MAX_WILL.
	return min(get_base_stat(Stats.Stat.WIL), MAX_WILL)

func get_current_will() -> int:
	return current_will

func set_current_will(value: int):
	current_will = clamp(value, 0, get_max_will())
	emit_signal("will_changed", current_will, get_max_will())

func can_afford_down() -> bool:
	# Pure read — the resolver uses it to PREVIEW maim (Law #2) without spending anything.
	return current_will >= DOWN_WILL_COST

func spend_will_for_down() -> bool:
	# Pay the flat down cost at down-time. Returns true if the unit was MAIMED (couldn't pay):
	# Will floors at 0 and a limb is lost. False = a clean down. The limb EFFECT is deferred
	# (docs/design/progression.md); today it's recorded + surfaced in UI/preview only.
	if can_afford_down():
		set_current_will(current_will - DOWN_WILL_COST)
		return false
	set_current_will(0)
	maimed_part = MaimedPart.ARM_RIGHT   # default limb. TODO: derive deterministically (stat diff?), no RNG (Law #1).
	return true

func is_maimed() -> bool:
	return maimed_part != MaimedPart.NONE
