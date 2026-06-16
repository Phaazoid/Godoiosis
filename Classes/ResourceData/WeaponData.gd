class_name WeaponData
extends Item

@export var power: int = 0
@export_enum("STR", "LDR", "WIL", "MHP") var scaling_stat: String = "STR"
@export var attack_pattern: AttackPattern
@export var can_counter := true
@export var hits_allies := false
@export var weapon_type: String = ""
@export var elemental_damage_type: String = ""
