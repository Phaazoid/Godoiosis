extends Object
class_name JobCatalog

# Registry for authored JobData content (mirrors WeaponCatalog's pattern) — scans
# res://Resources/Jobs/ and resolves by id, the stable key units persist (never display name).

const JOB_DIR := "res://Resources/Jobs/"

# id -> JobData. The lookup UnitInstance uses to resolve a stored id into data.
static func get_jobs() -> Dictionary:
	var jobs := {}
	if not DirAccess.dir_exists_absolute(JOB_DIR):
		return jobs
	for file in DirAccess.get_files_at(JOB_DIR):
		if not file.ends_with(".tres"):
			continue
		var res = load(JOB_DIR + file)
		if res is JobData and res.id != "":
			jobs[res.id] = res
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
