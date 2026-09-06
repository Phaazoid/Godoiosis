class_name Loadout
extends RefCounted

# The pre-mission phase's LIVE gear (#741) -- the stash, and the one place any move between the
# stash and a unit, or between two units, is judged.
#
# WHY THIS EXISTS AT ALL: before it, PreMissionScreen read `roster.stash` straight off the resource
# RosterCatalog.resolve() handed back, and that is Godot's resource CACHE. The first item moved out
# would have mutated the authored Roster for the rest of the session -- every later resolve() in the
# same run returning the depleted one -- which is #731 ruling 3 (edits do not persist between
# missions) broken by the first drag. The unit side never had this problem: ScenarioUnitEntry grants
# gear through copy_for_grant(). The stash simply never got the same treatment, because until this
# ticket nothing could move it.
#
# So the stash here is COPIES, and the phase owns them. MissionController builds one in deploy_roster
# -- where the Roster is already in hand -- and drops it in reset(), the same pair of edges
# _roster_units lives on.
#
# ONE RULE, TWO INPUTS. Clicking and dragging both ask move_block_reason and both act through move();
# a drag that judged for itself would be a second answer to "may this move", which is the exact shape
# #744 collapsed one layer down. The stash is addressed as a NULL unit at both ends, so all four
# directions the dev listed are one function rather than four near-copies.

var stash: Array[Item] = []


# Copies, never the authored array -- see the header. A null entry is authoring noise and is dropped
# rather than carried as a hole, since the stash is a list the player reads, not a slot grid.
static func from_roster(roster: Roster) -> Loadout:
	var made := Loadout.new()
	if roster == null:
		return made
	for item: Item in roster.stash:
		if item != null:
			made.stash.append(item.copy_for_grant())
	return made


# WHY this move cannot happen -- "" means it can. `from` and `to` are the OWNERS, with null meaning
# the stash; every refusal is the owning end's own sentence rather than one worded here, so the
# reason a card gives and the reason a stash row gives are the same string.
func move_block_reason(item: Item, from: Unit, to: Unit) -> String:
	if item == null:
		return "There is nothing to move."
	if from == to:
		return ""   # a drop back where it started is a no-op, not a refusal
	if from != null:
		var index := from.inventory.find(item)
		if index == -1:
			return "%s is not carrying that." % from.get_unit_name()
		var refusal := from.remove_block_reason(index)
		if refusal != "":
			return refusal
	elif not stash.has(item):
		return "That is no longer in the stash."
	if to != null:
		return to.add_block_reason(item)
	return ""


# Performs it, or says why not -- "" on success. The reason is asked FIRST and the act is the same
# call's second half, so nothing can act on a judgement the caller made a frame ago.
func move(item: Item, from: Unit, to: Unit) -> String:
	var refusal := move_block_reason(item, from, to)
	if refusal != "" or from == to:
		return refusal

	# Taken from the source before it is given, so a mid-move failure cannot leave two owners
	# holding one object. Nothing between these can fail: both ends were judged above.
	if from != null:
		from.remove_item(from.inventory.find(item))
	else:
		stash.erase(item)

	if to != null:
		# No copy_for_grant() here, deliberately. The stash was copied when the phase opened and a
		# unit's kit was copied when it spawned, so this object already has exactly one owner --
		# copying again would leave the battle-state identity of a WeaponInstance behind (#87's
		# per-inventory-index states), and two units would carry sibling objects the save cannot
		# tell apart.
		to.add_item(item)
	else:
		stash.append(item)
	return ""
