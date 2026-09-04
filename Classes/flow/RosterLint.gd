extends Object
class_name RosterLint

# "Is this roster file authored the way a roster can actually be read?" (#735) -- AttackLint's and
# WeaponTemplateLint's shape, and BoardLint's discipline: BORROW the rule rather than restate one.
#
# It exists because Roster reuses ScenarioUnitEntry wholesale (see Roster.gd for why), which buys
# zero migration and costs the ability to express nonsense: a roster member mid-Crisis, one holding
# a Guard on a unit that is on no board, one whose empty snapshot silently strips the character's
# own kit. None of that is reachable through a UI -- rosters are hand-authored in the inspector
# until #731's deferred dev tab -- so nothing else would ever say a word about it.
#
# Every fault here is an AUTHORING mistake and every one of them is SILENT in play, which is the
# only reason a lint is the right tool. Its CI caller is tests/dev/test_roster_lint.gd.

# Same two tiers as BoardLint, same meanings, and no third: BLOCKS = the roster is not the roster
# you authored; DEGRADES = it loads and offers units, but one of them is not what you meant.
# Nothing here is BLOCKS today -- a roster that LOADS is always offerable, and a roster that does
# not load is BoardLint's question, asked of the board that names it.
enum Severity { BLOCKS, DEGRADES }


# One row per fault: {"severity": Severity, "text": String}. Empty means nothing found.
static func check(roster: Roster) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if roster == null:
		return found   # "no roster" is not a defective roster; BoardLint owns the missing-file case

	for i in roster.entries.size():
		var entry: ScenarioUnitEntry = roster.entries[i]
		if entry == null:
			_add(found, Severity.DEGRADES, "Entry %d is empty and will be skipped." % (i + 1))
			continue
		_check_one_job(entry, i, found)
		_check_hollow_snapshot(entry, i, found)
		_check_battle_state(entry, i, found)
	return found


# #731 ruling 10: one job at a time binds at the ROSTER, not at UnitInstance.jobs (capping the
# model would break enemies, whose held jobs are their readable kit) and not at the picker (which
# would silently drop the second job of anyone authored with two).
#
# Reads the EFFECTIVE list, which is not always the entry's own: apply_unit_state REPLACES
# inst.jobs with the entry's copy, but only when state_saved -- a reference entry never gets there,
# and the jobs it ends up with are the ones _seed_starting_kit added from UnitData.starting_jobs.
static func effective_jobs(entry: ScenarioUnitEntry) -> Array[String]:
	if entry.state_saved:
		return entry.jobs
	if entry.unit_data == null:
		return []
	return entry.unit_data.starting_jobs


static func _check_one_job(entry: ScenarioUnitEntry, index: int, found: Array[Dictionary]) -> void:
	var jobs := effective_jobs(entry)
	if jobs.size() <= 1:
		return
	_add(found, Severity.DEGRADES,
		"%s holds %d jobs (%s) -- a roster unit carries one, and the pre-mission picker shows one."
			% [_label(entry, index), jobs.size(), ", ".join(jobs)])


# The inspector's default for state_saved is TRUE, which makes this the easiest mistake in the
# file to make and the hardest to see: add a character, leave the tick, and apply_unit_state runs
# with an empty snapshot -- inventory.fill(null), unequip_weapon(), inst.jobs = [] -- REPLACING
# whatever _seed_starting_kit granted. The unit deploys naked and jobless, with no error anywhere.
# A reference entry (state_saved = false) is what "just this character, as authored" means.
static func _check_hollow_snapshot(entry: ScenarioUnitEntry, index: int, found: Array[Dictionary]) -> void:
	if not entry.state_saved:
		return
	var captured: bool = not entry.stats.is_empty() \
		or entry.current_hp != -1 \
		or entry.current_will != -1 \
		or not entry.inventory.is_empty() \
		or not entry.jobs.is_empty() \
		or not entry.weapon_proficiency.is_empty() \
		or not entry.aura.is_empty() \
		or entry.affinity_saved \
		or not entry.limb_states.is_empty()
	if captured:
		return
	_add(found, Severity.DEGRADES,
		("%s is a snapshot that captured nothing, so it deploys with NO kit and NO jobs -- the "
		+ "character's own starting kit is replaced by the empty snapshot. Did you mean a "
		+ "reference entry (untick state_saved)?") % _label(entry, index))


# Battle-scoped fields (#87) mean nothing in a roster: a roster unit is on no board, has taken no
# turn, and is holding no Guard on anyone. They round-trip because a roster entry IS a
# ScenarioUnitEntry; setting one is an authoring accident, and apply_unit_state would replay it
# onto a freshly deployed unit at the start of a mission.
static func _check_battle_state(entry: ScenarioUnitEntry, index: int, found: Array[Dictionary]) -> void:
	var set_fields: Array[String] = []
	if entry.lifecycle_state != Unit.LifecycleState.ACTIVE:
		set_fields.append("lifecycle_state")
	if entry.in_crisis:
		set_fields.append("in_crisis")
	if entry.crisis_surge_pending:
		set_fields.append("crisis_surge_pending")
	if entry.downed_turns_remaining != -1:
		set_fields.append("downed_turns_remaining")
	if entry.rally_count != 0:
		set_fields.append("rally_count")
	if not entry.element_states.is_empty():
		set_fields.append("element_states")
	if not entry.stat_effects.is_empty():
		set_fields.append("stat_effects")
	if not entry.weapon_battle_states.is_empty():
		set_fields.append("weapon_battle_states")
	if entry.guard_ward_index != -1:
		set_fields.append("guard_ward_index")
	if not entry.watch_cells.is_empty():
		set_fields.append("watch_cells")
	if entry.squad_has_acted:
		set_fields.append("squad_has_acted")
	if set_fields.is_empty():
		return
	_add(found, Severity.DEGRADES,
		("%s carries battle state a roster unit cannot have (%s) -- it would be replayed onto the "
		+ "unit the moment it deploys.") % [_label(entry, index), ", ".join(set_fields)])


# Names the character when it can, since that is what the author is looking for in the inspector.
static func _label(entry: ScenarioUnitEntry, index: int) -> String:
	if entry.unit_data != null and entry.unit_data.display_name != "":
		return entry.unit_data.display_name
	return "Entry %d" % (index + 1)


static func _add(found: Array[Dictionary], severity: Severity, text: String) -> void:
	found.append({"severity": severity, "text": text})
