extends Resource
class_name ScenarioUnitEntry

@export var unit_data: UnitData
@export var cell: Vector2i
@export var equipped_weapon: EquippableData
@export var squad_id := -1   #entries sharing an id form one squad; -1 = solo
@export var is_leader := false
