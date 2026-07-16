# Shared fixtures for the jobs test suites (#58). PRELOADED, not class_name'd — see
# squad_fixtures.gd for why (adding this never needs a one-time --import pass).
#
# The pipeline/MOV tests need a JobData with SPECIFIC nudges/ceilings/mov_base to exercise
# the ceiling-clamp and job-base seams. JobCatalog has no test-injection point (a deliberate
# disk scan mirroring WeaponCatalog), and the real authored placeholder jobs (Scout "scout",
# Tank "tank") only set id/display_name so far — every other field sits at its script default.
# Rather than add a production seam or write test-only content into Resources/Jobs/ (which
# would leak into the live dev editor's job list), these fixtures borrow the real catalog
# entries, mutate the fields a test needs, and restore them afterward via snapshot/restore.
# Coupled to "scout"/"tank" existing: if the roster/naming pass (jobs.md, deferred content)
# renames or removes those ids, these tests need updating alongside.
extends RefCounted

const SNAPSHOT_FIELDS := ["stat_nudges", "stat_ceilings", "mov_base", "is_locked", "starter_ability"]

static func snapshot(job: JobData) -> Dictionary:
	var snap := {}
	for field in SNAPSHOT_FIELDS:
		var value = job.get(field)
		snap[field] = value.duplicate() if value is Dictionary else value
	return snap

static func restore(job: JobData, snap: Dictionary) -> void:
	for field in SNAPSHOT_FIELDS:
		job.set(field, snap[field])

# A bare UnitInstance, stats patched by `overrides`. No job assigned — callers certify/slot
# as needed. Mirrors the stats-suite `_make_instance` pattern (tests/stats/test_mov.gd etc.)
static func make_instance(overrides: Dictionary[Stats.Stat, int] = {}) -> UnitInstance:
	var data := UnitData.new()
	data.base_stats = overrides
	var inst := UnitInstance.new()
	inst.data = data
	inst.initialize()
	return inst
