extends Object
class_name RosterCatalog

# "Which rosters exist, and what does this NAME point at?" (#735). Deliberately shaped like
# LookKnobs' preset lookup rather than like UnitCatalog/ArmorCatalog, and the difference matters:
# ResourceCatalog.by_name keys by the resource's own display_name, and its comment says outright
# that two resources sharing a name COLLAPSE into one entry. A roster is addressed by the name a
# scenario stores, so a collapse would silently hand a mission the wrong pool. Filename IS the
# identity here, exactly as it is for a look preset -- so a roster carries no display_name at all.
const ROSTER_DIR := "res://Resources/Rosters/"

# The dropdown's source and the lint's source: one question, so a name the Properties row offers is
# always a name the lint accepts. Through ResourceDir, never DirAccess -- an exported build returns
# packed names and every catalog that bypasses it silently empties (CLAUDE.md).
static func saved_rosters() -> Array[String]:
	var names: Array[String] = []
	for file: String in ResourceDir.files_with_extension(ROSTER_DIR, ".tres"):
		names.append(file.trim_suffix(".tres"))
	return names

static func roster_path(name: String) -> String:
	return "%s%s.tres" % [ROSTER_DIR, name]

# The one side-effecting reader: it push_errors and returns null, the way LookKnobs.resolve
# push_errors and falls back. Nothing in a lint may call this (BoardLint's own rule) -- a lint asks
# saved_rosters() instead.
#
# There is no default-roster fallback, and that asymmetry with LookKnobs is deliberate: a board
# with no look wears the default look and plays fine, while a board whose pool cannot be found has
# no pool. Substituting some other roster would hand the player a different mission; null is the
# honest answer, and BoardLint flags the board that produced it as BLOCKS.
static func resolve(name: String) -> Roster:
	if name == "":
		return null   # the ordinary case: this board has no pre-mission phase
	var path := roster_path(name)
	if not ResourceLoader.exists(path):
		push_error("Roster '%s' does not exist (%s)." % [name, path])
		return null
	# load_tolerant, not load: a roster references UnitData and EquippableData files, so it is
	# exactly the #596 dangling-chain shape -- one deleted weapon three files down refuses the
	# WHOLE roster, and the repair pass is what gets it back.
	var roster := ContentRepair.load_tolerant(path) as Roster
	if roster == null:
		push_error("Roster '%s' did not load as a Roster (%s)." % [name, path])
	return roster
