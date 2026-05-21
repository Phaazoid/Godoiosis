extends Resource
class_name UnitData

#This is the basics of what a UnitInstance has.  Each UnitInstance will have a unique version of this, and it should never change during runtime
#basically immutable design draft

@export var display_name: String = "Unit"
@export var portrait: Texture2D = load("res://Art/Units/Portraits/faceless_one.png")
@export var base_stats: Dictionary[String, int]
@export var growth_ranges: Dictionary[String, Vector2i]
@export var innate_abilities: Array[String]
@export var faction: Team.Faction
