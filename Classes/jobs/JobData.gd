extends Resource
class_name JobData

# A job's authored content (docs/design/jobs.md): stat nudges/ceilings, MOV base, and its
# ability pool. Lives as .tres content, scanned by JobCatalog; UnitInstance only ever stores
# the id (main_job/sub_jobs/certified_jobs), never a direct reference to this resource.

@export var id: String = ""             # stable key — certified_jobs/main_job persist THIS, not the name
@export var display_name: String = ""
@export var stat_nudges: Dictionary[Stats.Stat, int]
@export var stat_ceilings: Dictionary[Stats.Stat, int]   # absent key = uncapped
@export var mov_base: int = 4            # playtest-tunable
@export var ability_pool: Array[AbilityData]
@export var starter_ability: AbilityData
@export var is_locked := false           # unique story jobs — the one sanctioned stat-free gate
