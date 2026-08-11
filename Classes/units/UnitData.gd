extends Resource
class_name UnitData

#This is the basics of what a UnitInstance has.  Each UnitInstance will have a unique version of this, and it should never change during runtime
#basically immutable design draft

@export var display_name: String = "Unit"
@export var portrait: Texture2D = load("res://Art/Units/Portraits/faceless_one.png")
@export var base_stats: Dictionary[Stats.Stat, int]
@export var faction: Team.Faction
@export var map_sprite: Texture2D 
@export var move_sprite: Texture2D 
@export var downed_sprite: Texture2D 
@export var base_aura: Dictionary[Elemental.Element, int]
@export var base_affinity: Array[Elemental.Element] = []   # genetic; order = rank, [0] = primary
@export var base_is_alkahest_affine: bool = false          # Isaac's hidden sixth — never a UI bar
# Abilities this character is BORN with (jobs.md — the story/innate source, alongside jobs and
# gear). Authored per character; nothing awards one at runtime yet. The moment something does,
# this becomes base_abilities seeding a mutable UnitInstance.innate_abilities, and
# ScenarioUnitEntry has to round-trip it in the same change.
@export var innate_abilities: Array[AbilityData] = []

# --- Starting kit (#177) — what this character carries into any board, seeded by
# Unit._seed_starting_kit() right after initialize(). All defaults inert: a kit-less UnitData
# spawns exactly as before. Inventory entries should reference standalone equippable .tres
# (Item Editor output) — they are granted as copy_equippable() copies, never shared.
@export var starting_jobs: Array[String] = []
@export var starting_inventory: Array[EquippableData] = []
@export var starting_equipped_index := -1   # into starting_inventory; -1 = add_item's auto-equip decides
@export var starting_worn_index := -1       # into starting_inventory; -1 = nothing worn
@export var starting_proficiency: Dictionary[WeaponData.WeaponType, int] = {}
@export var starting_prosthetics: Dictionary[UnitInstance.LimbSlot, int] = {}   # slot -> starting_inventory index

func has_starting_kit() -> bool:
	return not starting_jobs.is_empty() or not starting_inventory.is_empty() \
		or not starting_proficiency.is_empty() or not starting_prosthetics.is_empty()
