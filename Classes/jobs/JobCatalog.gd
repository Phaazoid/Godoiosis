extends Object
class_name JobCatalog

# Registry for authored JobData content (mirrors WeaponCatalog's pattern) — scans
# res://Resources/Jobs/ and resolves by id, the stable key units persist (never display name).
# The scan is CACHED: job files only change between runs, and a per-call disk scan measured
# ~5ms — fatal in hot paths (movement_cost's Waterwalk check, get_effective_stat's nudges).
# Any future runtime job-authoring tool must call refresh() after saving (#66).

const JOB_DIR := "res://Resources/Jobs/"

static var _jobs_by_id: Dictionary = {}
static var _scanned := false

# id -> JobData. The lookup UnitInstance uses to resolve a stored id into data.
static func get_jobs() -> Dictionary:
	if not _scanned:
		_jobs_by_id = _scan()
		_scanned = true
	return _jobs_by_id

static func refresh() -> void:
	_scanned = false

static func _scan() -> Dictionary:
	var jobs := {}
	for job: JobData in ResourceCatalog.load_all(JOB_DIR, JobData):
		if job.id != "":
			jobs[job.id] = job
	return jobs

static func get_job(id: String) -> JobData:
	return get_jobs().get(id)

# display_name -> JobData, for the dev editor's dropdown (mirrors WeaponCatalog.get_editable).
static func get_editable() -> Dictionary:
	var jobs := get_jobs()
	var editable := {}
	for id in jobs:
		var job: JobData = jobs[id]
		editable[job.display_name if job.display_name != "" else id] = job
	return editable
