extends RefCounted
class_name PreMissionSnapshot

# WHAT THE PLAYER CHOSE before the mission started (#763): who was standing and where, the squads
# they built, the gear and jobs and mods they set, and the stash they took it all out of. Captured
# at the commit, replayed when they come back to the phase through a restart.
#
# Dumb data. MissionController._capture_staged writes it and _stand_staged reads it -- the same
# split BoardSnapshot declares, and RefCounted for BoardSnapshot's reason: this is never saved,
# never loaded and never referenced by a file. It lives as long as the session's interest in one
# mission, and #731 ruling 3 still holds -- nothing here crosses a mission boundary.
#
# THE ROW TYPE IS ScenarioUnitEntry, on purpose. Everything the phase can change to a unit is
# already captured and replayed by capture_unit_state/apply_unit_state -- gear (as copies, through
# copy_for_grant, so a WeaponInstance brings its fitted mods), jobs, stats, worn armour -- and
# reusing it means this ticket adds no field to a resource 13 .tres files embed. The battle-scoped
# half of that block is inert here because a commit is BEFORE turn 1: nothing is downed, in crisis,
# or on watch when this is taken.
#
# The DRAW ORDER is the identity. roster.entries order is fixed and deploy_roster's skip rule
# (a null entry, or one with no unit_data) is fixed with it, so the i-th unit the draw spawns is
# the i-th unit it will spawn again. fits() below guards the one thing that can drift.

# Which board this belongs to -- ScenarioManager.last_loaded_path at the commit. A restart of any
# other mission simply does not match, which is why nothing has to remember to clear it (#763
# ruling 1: it lives until the next commit overwrites it, or an in-phase restart drops it).
var mission_path := ""
# One row per DRAWN roster unit -- deployed and reserve alike -- in draw order.
var entries: Array[ScenarioUnitEntry] = []
# Index-parallel with `entries`: was this unit STANDING on the board. ScenarioUnitEntry has no
# sentinel for "nowhere" (its cell is a Vector2i and the origin is a legal cell), and giving it one
# would mean editing the shipped resource for a fact only this buffer has -- so the flag lives here.
var deployed: Array[bool] = []
# The phase's loose gear, as copies. Not on a row because it belongs to nobody; Loadout owns the
# live one and this is what it is rebuilt from.
var stash: Array[Item] = []


# Does this buffer still describe THIS draw? Two ways it can stop, both needing the roster file to
# be edited between a commit and a restart in one session:
#
#   * a different COUNT -- an entry added or removed, so index i is a different character;
#   * a different CHARACTER at some index -- entries reordered, or one's unit_data repointed.
#
# The second is asked through unit_data_source, which is the standalone character FILE a unit came
# from (UnitFactory stamps it; a roster whose entries embed their unit_data leaves it null, and two
# nulls compare equal, which correctly falls back to the count check alone). It is the same meaning
# capture_scenario gives the field on a reference entry, not a second one.
#
# A buffer that does not fit is dropped rather than repaired: the authored draw is always a correct
# answer, and half-applying one would hand Aldin's kit to Bram in silence.
func fits(units: Array[Unit]) -> bool:
	if entries.size() != units.size() or deployed.size() != units.size():
		return false
	for i in units.size():
		if entries[i].unit_data != units[i].unit_data_source:
			return false
	return true
