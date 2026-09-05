extends Resource
class_name Roster

# Who a mission OFFERS, and what loose gear it offers them (#735, the foundation of #731's
# pre-mission phase). A mission names one of these; the player picks from it, up to the mission's
# cap, and places the picks in the deployment zone. MissionController.deploy_roster is what reads
# one (#737) -- today it draws for the player, and #740 is the screen that hands the choosing over.
# Rosters are PLURAL and per-mission on purpose (dev, 2026-09-04): the same characters can carry
# different state in different missions, which is the balance-testing lever.
#
# A roster entry IS a ScenarioUnitEntry, deliberately, and that is the whole design. #731 ruling 1
# made `cell`/`squad_id`/`is_leader` OUTPUTS of the pre-mission phase, so an entry that has not been
# deployed yet is just that resource with those three unset -- and at commit the board's
# unit_entries is this list with them filled in. Reusing it also inherits #177's reference/snapshot
# fork for free: an entry with state_saved=false points at a character file whose starting kit is
# the whole answer, which is exactly what an unauthored roster member should be.
#
# The alternative -- factoring the persistent block out into a shared nested resource -- was
# rejected on migration cost: 13 .tres embed ScenarioUnitEntry as sub-resources, plus every user://
# save slot, and Godot drops properties a resource no longer declares SILENTLY. All of them would
# read as defaults with no error anywhere (CLAUDE.md's retyping trap; predates_corner_heights()
# exists because of it).
#
# The cost of that reuse is that a roster file can express nonsense -- a roster member mid-Crisis,
# or holding a Guard on a unit that is not on any board. RosterLint is what pays it.
#
# No display_name: a roster's identity is its FILENAME, the way a LookPreset's is. RosterCatalog
# keys on it, the Properties dropdown lists it, and ScenarioData stores that name. One name, one
# place to disagree with.

@export var entries: Array[ScenarioUnitEntry] = []

# Loose gear this mission's roster starts with. Same element type as ScenarioUnitEntry.inventory
# and UnitData.starting_inventory, and the same authoring source: standalone .tres out of
# Resources/Weapons/WeaponVariants/, Resources/Armor/ and the rune variants. Granted to a unit as a
# copy_equippable() copy at deploy time, never shared -- the rule starting_inventory already states.
#
# Loose MODS are not here and cannot be: WeaponModData extends Resource, not Item, so it has no
# icon, no description, and structurally cannot sit in an inventory. #732 carries both halves.
@export var stash: Array[EquippableData] = []
