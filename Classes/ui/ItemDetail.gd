class_name ItemDetail

# WHICH DETAIL CARD A PIECE OF GEAR HAS, and how it is opened (#1019). ONE file, because the question
# is asked twice per surface -- once to build the affordance, once to act on it -- across two surfaces
# (PreMissionCard's unit gear rows and PreMissionScreen's stash rows). Four hand-written kind forks is
# four places to forget the third kind the day one exists.
#
# IT IS ALSO WHY THERE IS ONE SIGNAL. `PreMissionCard.detail_requested` carries an `Item`, not a
# weapon, so the chip and the handler ask the same question of the same value; a per-kind signal would
# put the fork back in the wiring, where nothing could see the two halves together.
#
# A NULL CHIP MEANS THIS KIND HAS NO CARD -- armour, a vial, a weapon whose template authors no mod
# spaces. A rune always has one, blank included; RuneDetailCard.chip_for says why.

static func chip_for(item: Item) -> Button:
	var weapon := item as WeaponInstance
	if weapon != null:
		return ModFittingCard.chip_for(weapon)
	var rune := item as RuneData
	if rune != null:
		return RuneDetailCard.chip_for(rune)
	return null


# `mods` is the mission's own mod pool (#812) and `on_closed` what the host does afterwards. Both are
# the WEAPON card's business and are carried past the rune branch rather than forked at the call site,
# which is the whole point of one door -- see below for why the rune branch drops the second.
static func open(game_node: Node, item: Item, owner_unit: Unit,
		mods: Array[WeaponModData], on_closed: Callable) -> void:
	var weapon := item as WeaponInstance
	if weapon != null:
		ModFittingCard.open(game_node, weapon, owner_unit, mods).closed.connect(on_closed)
		return
	var rune := item as RuneData
	if rune != null:
		# NOTHING TO REDRAW BEHIND IT. Fitting a mod moves WT, DEF, the ability chips and the stat
		# grid, so that card's host redraws on the way out; this one is a read and wrote nothing, so
		# redrawing on its close would be a screen rebuilding itself over an event that changed no
		# state. `on_closed` goes unused here deliberately rather than by omission.
		RuneDetailCard.open(game_node, rune, owner_unit)
