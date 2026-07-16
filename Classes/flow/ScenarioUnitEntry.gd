extends Resource
class_name ScenarioUnitEntry

# One saved unit's snapshot inside a ScenarioData (the persistence seam, #8): spawn cell,
# equipped gear, squad membership, and job assignment. What ScenarioManager reads on save
# and writes back on load.

@export var unit_data: UnitData
@export var cell: Vector2i
@export var equipped_weapon: EquippableData
@export var squad_id := -1   #entries sharing an id form one squad; -1 = solo
@export var is_leader := false
@export var squad_name := ""
@export var squad_archetype: AIArchetype.Type = AIArchetype.Type.FACTION_DEFAULT
@export var squad_zone := ""   # only meaningful on the leader's entry; "" = none
@export var certified_jobs: Dictionary[String, bool] = {}
@export var main_job := ""
@export var sub_jobs: Array[String] = []
@export var unlocked_sub_slots := 0
