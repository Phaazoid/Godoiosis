extends Object
class_name WeaponModCatalog

# Registry for authored WeaponModData content — the fitting tool's mod picker scans here.
# Fitted mods ride instances as direct refs, so editing a mod .tres updates every weapon
# it's fitted to (same live-sync model as templates) -- true only since #589 taught
# DevWidgets.save_over to write THROUGH to the object that owns the path, rather than
# orphaning it behind the editor's copy.
const MOD_DIR := "res://Resources/WeaponMods/"

static func get_mods() -> Dictionary:
	return ResourceCatalog.by_name(MOD_DIR, WeaponModData)


# The mods a weapon of this family could EVER take -- keyed by display name, the filename when a mod
# has none, exactly as get_mods keys them.
#
# ONE ANSWER, TWO PICKERS (#732). The Item Editor's fitting rows and the pre-mission fitting card ask
# the same question of the same source, and the split it encodes is the ratified one: a FAMILY
# refusal can never be fixed on this weapon, so those entries are not offered at all, while a full
# space is live state you fix by removing something and is refused WITH THE REASON where the dev can
# act on it (weapons.md; WeaponInstance.fit_block_reason asks family first for this).
static func offerable_for(weapon_type: WeaponData.WeaponType) -> Dictionary:
	var offerable := {}
	var mods := get_mods()   # ONE scan: get_mods re-reads the whole directory on every call
	for key in mods:
		var mod: WeaponModData = mods[key]
		if mod.fits_family(weapon_type):
			offerable[key] = mod
	return offerable
