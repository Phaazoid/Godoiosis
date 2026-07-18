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

# Per-element aura — persistent damage scaling for runes (docs/design/alchemy-kit.md).
# Mirrors `stats`: seeded from UnitData.base_aura, grows over a unit's life.
var aura: Dictionary = {}

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

const JOBLESS_MOV_BASE := 4       # playtest-tunable; prompt 9 swaps in the main job's base
const WEIGHT_MOV_THRESHOLD := 8   # playtest-tunable: at/above this Weight, one coarse step off
const WEIGHT_MOV_PENALTY := 1     # a step, never per-point (jobs.md — plate isn't double-punished)

# --- Weapon proficiency (docs/design/weapons.md, #59) ---
const DEFAULT_PROFICIENCY := 3   # == WeaponData.SPACE_CAPACITIES.size() — all spaces active by
								  # default, so existing scenarios/weapons behave unchanged
var weapon_proficiency: Dictionary[WeaponData.WeaponType, int] = {}

# --- Limb slots (will-and-death.md, the limb-slot model — #56) ---
# Limbs are equipment slots: NATURAL = the unit's own limb (reads innate STR/DEX),
# EMPTY = maimed, PROSTHETIC = fitted gear with its own built-in stat (content: prompt 10).
enum LimbSlot { ARM_L, ARM_R, LEG_L, LEG_R }
enum LimbState { NATURAL, EMPTY, PROSTHETIC }

# --- Jobs (docs/design/jobs.md, #58) ---
var certified_jobs: Dictionary[String, bool] = {}   # a set: job id -> true, certify-once
var main_job: String = ""                            # "" = jobless
var sub_jobs: Array[String] = []                      # subs, size <= unlocked_sub_slots
var unlocked_sub_slots: int = 0                        # dev-settable stub until the campaign layer exists
var ability_progress: Dictionary[String, int] = {}     # empty scaffold; prompt 13 fills it
var known_abilities: Dictionary[String, bool] = {}     # granted starters; inert until prompt 12

# Maim order: weapon arm -> off leg -> off arm -> weapon leg; natural limbs first,
# prosthetics only when no natural limb remains (they detach as recoverable gear).
const MAIM_ROTATION: Array[LimbSlot] = [LimbSlot.ARM_R, LimbSlot.LEG_L, LimbSlot.ARM_L, LimbSlot.LEG_R]

class LimbFitting:
	var state: LimbState = LimbState.NATURAL
	var prosthetic_stat: int = 0             # meaningful only when PROSTHETIC and there's no real item (dev/test placeholder fittings)
	var prosthetic_item: WeaponData = null   # the integrated-weapon template, when this prosthetic is also a weapon

var limbs: Dictionary[LimbSlot, LimbFitting] = {}

func initialize():
	if data == null:
		push_error("UnitInstance has no UnitData assigned.")
		return
	#base current stats off of the data without editing the values in UnitData that we're pulling from
	stats = data.base_stats.duplicate(true)
	for stat in Stats.STAT_DEFAULTS:
		if not stats.has(stat):
			stats[stat] = Stats.STAT_DEFAULTS[stat]
	limbs = {}
	for slot in LimbSlot.values():
		limbs[slot] = LimbFitting.new()
	aura = data.base_aura.duplicate(true)
	#reset battle stats
	current_hp = get_max_hp()
	current_will = get_max_will()

func _main_job() -> JobData:
	return JobCatalog.get_job(main_job) if main_job != "" else null

func certify(job_id: String, force: bool = false) -> bool:
	if certified_jobs.has(job_id):
		return true
	var job := JobCatalog.get_job(job_id)
	if job == null:
		return false
	if job.is_locked and not force:
		return false
	certified_jobs[job_id] = true
	if job.starter_ability != null:
		known_abilities[job.starter_ability.id] = true
	return true

func set_main_job(job_id: String) -> bool:
	# TODO(campaign layer): jobs.md wants this free-but-between-missions-only; no mission
	# boundary exists yet in code, so it's unrestricted for now (dev call, 2026-07-16).
	if job_id != "" and not certified_jobs.has(job_id):
		return false
	if job_id != "" and sub_jobs.has(job_id):
		return false
	main_job = job_id
	return true

func set_sub_job(index: int, job_id: String) -> bool:
	if index < 0 or index >= 2 or index >= unlocked_sub_slots:
		return false
	if job_id != "" and (not certified_jobs.has(job_id) or job_id == main_job):
		return false
	while sub_jobs.size() <= index:
		sub_jobs.append("")
	sub_jobs[index] = job_id
	return true

func set_unlocked_sub_slots(n: int) -> void:
	unlocked_sub_slots = clampi(n, 0, 2)

func get_proficiency(family: WeaponData.WeaponType) -> int:
	return weapon_proficiency.get(family, DEFAULT_PROFICIENCY)

func set_proficiency(family: WeaponData.WeaponType, value: int) -> void:
	weapon_proficiency[family] = clampi(value, 0, 3)

func get_base_stat(stat_name: Stats.Stat) -> int:
	if stats.has(stat_name):
		return stats[stat_name]
	# Missing key = a stat appended after this unit's data was authored -> its default,
	# never 0. Robust for every future enum append.
	return Stats.STAT_DEFAULTS.get(stat_name, 0)

func get_current_hp() -> int:
	return current_hp

func get_max_hp() -> int:
	# The one max-HP truth: MHP base + CON band — EFFECTIVE CON as of #56 (gear can shift it).
	return get_base_stat(Stats.Stat.MHP) + Stats.con_mhp_band(get_effective_stat(Stats.Stat.CON))

func get_effective_ldr() -> int:
	return get_effective_stat(Stats.Stat.LDR) + Stats.per_ldr_band(get_effective_stat(Stats.Stat.PER))

func get_weight(gear: int = 0) -> int:
	# Derived, never authored (stats.md): body + gear + modules + carried.
	# gear = the wielder's equipped weapon's effective weight — Unit passes it in, since
	# UnitInstance has no visibility into equipped_weapon (the other side of the persistence
	# seam, #59). Only the CON body term + gear exist yet — modules/carried are still 0.
	var body := get_base_stat(Stats.Stat.CON)
	var modules := 0
	var carried := 0
	return body + gear + modules + carried

func get_mov(gear: int = 0) -> int:
	# MOV is a READOUT (jobs.md, audit A4): job base + DEX band, minus the heavy-load step,
	# then the leg throttle LAST: one empty leg halves (round up), two pin MOV to 1 flat.
	var job := _main_job()
	var base := job.mov_base if job != null else JOBLESS_MOV_BASE
	var mov := base + Stats.dex_mov_band(get_effective_stat(Stats.Stat.DEX))
	if get_weight(gear) >= WEIGHT_MOV_THRESHOLD:
		mov -= WEIGHT_MOV_PENALTY
	match empty_leg_count():
		2:
			return 1
		1:
			mov = ceili(mov / 2.0)
	return maxi(1, mov)

func set_current_hp(value: int):
	current_hp = clamp(value, 0, get_max_hp())
	emit_signal("hp_changed", current_hp, get_max_hp())

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
	# Pay the flat down cost. Can't pay -> Will floors at 0 and the rotation takes a limb;
	# a maimed prosthetic detaches to recoverable gear. Fully maimed = still just a down —
	# "Will never kills" is absolute, multi-maim never escalates.
	if can_afford_down():
		set_current_will(current_will - DOWN_WILL_COST)
		return false
	set_current_will(0)
	var slot := next_maim_slot()
	if slot == -1:
		return false                      # nothing left to take; the down stands, nothing escalates
	var fitting: LimbFitting = limbs[slot]
	if fitting.state == LimbState.PROSTHETIC and fitting.prosthetic_item != null:
		pass                              # TODO(10): route the detached prosthetic to inventory (recoverable)
	fitting.state = LimbState.EMPTY
	fitting.prosthetic_stat = 0
	fitting.prosthetic_item = null
	_apply_maim_aura_tax()
	return true

func _apply_maim_aura_tax() -> void:
	# Audit A3: each lost limb costs -1 off the HIGHEST aura pool. Ties -> element enum
	# order for now; TODO(11): primary affinity breaks ties once the affinity set exists.
	# One-way: regrowth restores it, and regrowth is between-battle territory (not built).
	var best := Elemental.Element.NONE
	var best_val := 0
	for element in Elemental.SIGIL_ELEMENTS:
		var v: int = aura.get(element, 0)
		if v > best_val:
			best_val = v
			best = element
	if best != Elemental.Element.NONE:
		aura[best] = best_val - 1

func get_element_aura(element: Elemental.Element) -> int:
	return aura.get(element, 0)

func limb_stat(slot: LimbSlot) -> int:
	# What this slot contributes: arms carry STR, legs carry DEX; empty = 0.
	var fitting: LimbFitting = limbs[slot]
	match fitting.state:
		LimbState.EMPTY:
			return 0
		LimbState.PROSTHETIC:
			return fitting.prosthetic_item.built_in_stat if fitting.prosthetic_item != null else fitting.prosthetic_stat
		_:
			var natural := Stats.Stat.STR if slot == LimbSlot.ARM_L or slot == LimbSlot.ARM_R else Stats.Stat.DEX
			return get_base_stat(natural)

func install_prosthetic(slot: LimbSlot, item: WeaponData) -> bool:
	# Fits a real, content-authored prosthetic (weapons.md item 6). Its built_in_stat feeds
	# limb_stat() LIVE off the template — no snapshot, so editing the .tres later propagates
	# to every unit with it installed, same as scaling_blend does for ordinary weapons.
	if item == null:
		return false
	var is_arm_slot := slot == LimbSlot.ARM_L or slot == LimbSlot.ARM_R
	var wanted := WeaponData.LimbKind.ARM if is_arm_slot else WeaponData.LimbKind.LEG
	if item.limb_kind != wanted:
		return false
	var fitting: LimbFitting = limbs[slot]
	fitting.state = LimbState.PROSTHETIC
	fitting.prosthetic_item = item
	return true

func is_installed_prosthetic(template: WeaponData) -> bool:
	# An installed prosthetic weapon can't be swapped out (Unit.gd guards) — it's a limb,
	# not held gear. "Uninstalling" is a between-mission action, not built yet.
	if template == null:
		return false
	for slot in limbs:
		var fitting: LimbFitting = limbs[slot]
		if fitting.state == LimbState.PROSTHETIC and fitting.prosthetic_item == template:
			return true
	return false

func next_maim_slot() -> int:
	# The deterministic "next at risk" (Law #1 — previewable). -1 = fully maimed.
	for slot in MAIM_ROTATION:
		if limbs[slot].state == LimbState.NATURAL:
			return slot
	for slot in MAIM_ROTATION:
		if limbs[slot].state == LimbState.PROSTHETIC:
			return slot
	return -1

func is_maimed() -> bool:
	# Maimed = an EMPTY slot. A prosthetic-fitted unit is repaired, not maimed.
	for slot in limbs:
		if limbs[slot].state == LimbState.EMPTY:
			return true
	return false

func has_missing_arm() -> bool:
	return limbs[LimbSlot.ARM_L].state == LimbState.EMPTY or limbs[LimbSlot.ARM_R].state == LimbState.EMPTY

func empty_leg_count() -> int:
	return int(limbs[LimbSlot.LEG_L].state == LimbState.EMPTY) + int(limbs[LimbSlot.LEG_R].state == LimbState.EMPTY)
	
func get_limb_effective_base(stat: Stats.Stat) -> int:
	# Limb substitution: effective STR = mean of arm slots, effective DEX = mean of leg
	# slots, both ROUNDED UP. Everything else passes through untouched.
	match stat:
		Stats.Stat.STR:
			return ceili((limb_stat(LimbSlot.ARM_L) + limb_stat(LimbSlot.ARM_R)) / 2.0)
		Stats.Stat.DEX:
			return ceili((limb_stat(LimbSlot.LEG_L) + limb_stat(LimbSlot.LEG_R)) / 2.0)
		_:
			return get_base_stat(stat)

func get_effective_stat(stat: Stats.Stat) -> int:
	var value := get_stat_before_ceiling(stat)
	var job := _main_job()
	if job != null and job.stat_ceilings.has(stat):
		value = mini(value, job.stat_ceilings[stat])
	return value

func get_stat_before_ceiling(stat: Stats.Stat) -> int:
	# Pipeline up to (not including) the ceiling clamp — exposed so the dev editor's
	# preview-at-decision can show what a job WOULD clamp without duplicating this logic.
	var value := get_limb_effective_base(stat)
	var job := _main_job()
	if job != null:
		value += job.stat_nudges.get(stat, 0)
	value += stat_modifiers.get(stat, 0)
	return value
