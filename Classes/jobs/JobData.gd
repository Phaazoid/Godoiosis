extends Resource
class_name JobData

# A job's authored content (docs/design/jobs.md): a name, stat nudges, and an ability pool.
# Lives as .tres content, scanned by JobCatalog; UnitInstance only ever stores the id (in its
# `jobs` array), never a direct reference to this resource.

@export var id: String = ""             # stable key — UnitInstance.jobs persists THIS, not the name
@export var display_name: String = ""
@export var stat_nudges: Dictionary[Stats.Stat, int]
@export var ability_pool: Array[AbilityData]   # every ability here is live the instant the job is held
