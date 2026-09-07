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
# copy_for_grant() copy at deploy time, never shared -- the rule starting_inventory already states.
#
# Loose MODS do not belong here, and since #732 that is a RULING rather than a limitation -- the class
# became an Item in that ticket and could sit in this array, but the dev's call was that it should not
# (2026-09-06: "If an item can't be carried, I don't think they should go in the stash. Stash is for
# inventory editing purposes"). They get their own list below instead.
@export var stash: Array[Item] = []

# Which weapon mods the fitting card offers (#812). A SET, not a supply: naming one here says the
# mod exists in this mission, never how many there are -- scarcity is #828 and is deliberately not
# expressible in this field.
#
# Shared refs, never copies, and that is inherited rather than chosen: WeaponModData.copy_for_grant()
# answers with ITSELF (#732), because a duplicate would fork its granted_attacks into siblings that a
# save then writes INLINE rather than as an ExtResource.
@export var available_mods: Array[WeaponModData] = []

# --- "or everything" (#812, dev 2026-09-07) ---
#
# EMPTY MEANS NONE on all three lists, so a mission that offers no mods yet is a different file from
# one nobody has thought about -- the ai_factions ambiguity, which needed a lint precisely because a
# chosen empty and a forgotten empty were the same bytes. These three say the other thing.
#
# A STORED FLAG rather than a bulk tick-everything, and the difference is what happens tomorrow: a
# flag includes content authored after the roster was, which is what lets a sandbox roster stay
# whole as the game grows, where a snapshot of today's five mods would go quietly stale.
#
# Each one is read in exactly ONE place -- the accessor below it -- so no caller ever asks the flag.
# Ticking a flag does NOT clear the list underneath it: the tool greys the picks rather than
# dropping them, so turning it on to test with everything and off again gives the curated list back.
@export var offers_every_character := false
@export var offers_every_item := false
@export var offers_every_mod := false


# WHO this mission offers. The authored entries, or one reference entry per character on disk.
#
# The synthesized entries are built fresh on every call and never written back: entries are shared
# sub-resources of a file, and PreMission.deployment_plan's own header states the rule -- filling in
# a cell on one would edit content in memory and the next save would write it out.
func offered_entries() -> Array[ScenarioUnitEntry]:
	if not offers_every_character:
		return entries
	var every: Array[ScenarioUnitEntry] = []
	var characters := UnitCatalog.get_characters()
	for key in characters:
		var entry := ScenarioUnitEntry.new()
		entry.unit_data = characters[key]
		# The reference half of #177's fork, which is what every hand-authored roster entry already
		# is: the character file's own starting kit is the whole answer, and apply_unit_state is
		# never called. A snapshot here would deploy the cast naked and jobless (RosterLint).
		entry.state_saved = false
		every.append(entry)
	return every


# The loose gear the phase starts with. One of each authored item under the flag -- a count is a
# thing only the authored list can express, and "everything" has no quantity to state.
func offered_stash() -> Array[Item]:
	if not offers_every_item:
		return stash
	return ItemCatalog.everything()


# The mods the fitting card may offer, BEFORE the family filter -- which is a rule about the weapon
# rather than about supply and stays where it is (WeaponModCatalog.offerable_for).
func offered_mods() -> Array[WeaponModData]:
	if not offers_every_mod:
		return available_mods
	var every: Array[WeaponModData] = []
	var mods := WeaponModCatalog.get_mods()
	for key in mods:
		every.append(mods[key])
	return every
