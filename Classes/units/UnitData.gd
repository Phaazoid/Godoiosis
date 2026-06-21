extends Resource
class_name UnitData

#This is the basics of what a UnitInstance has.  Each UnitInstance will have a unique version of this, and it should never change during runtime
#basically immutable design draft

@export var display_name: String = "Unit"
@export var portrait: Texture2D = load("res://Art/Units/Portraits/faceless_one.png")
@export var base_stats: Dictionary[Stats.Stat, int]
@export var innate_abilities: Array[String]
@export var faction: Team.Faction
@export var map_sprite: Texture2D = load("res://Art/Units/MapSprites/Basic_Soldier.png")
@export var move_sprite: Texture2D = load("res://Art/Units/MapSprites/Basic_Soldier_Moving.png")
