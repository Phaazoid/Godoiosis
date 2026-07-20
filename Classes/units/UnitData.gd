extends Resource
class_name UnitData

#This is the basics of what a UnitInstance has.  Each UnitInstance will have a unique version of this, and it should never change during runtime
#basically immutable design draft

@export var display_name: String = "Unit"
@export var portrait: Texture2D = load("res://Art/Units/Portraits/faceless_one.png")
@export var base_stats: Dictionary[Stats.Stat, int]
@export var innate_abilities: Array[String]
@export var faction: Team.Faction
@export var map_sprite: Texture2D 
@export var move_sprite: Texture2D 
@export var downed_sprite: Texture2D 
@export var base_aura: Dictionary[Elemental.Element, int]
@export var base_affinity: Array[Elemental.Element] = []   # genetic; order = rank, [0] = primary
@export var base_is_alkahest_affine: bool = false          # Isaac's hidden sixth — never a UI bar
