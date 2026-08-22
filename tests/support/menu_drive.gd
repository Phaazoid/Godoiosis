# Driving the action ring from a test (#467).
#
# A suite used to reach a menu row by naming its ACTION_DATA id. Most rows are still ids, but every
# ATTACK is a SYNTHETIC leaf now -- allocated per open, negative, gone when the ring closes -- so
# its id cannot be written down in advance. It can only be found by walking the tree the ring is
# actually showing, which is the better test anyway: it asserts the row is REACHABLE, not merely
# that a constant exists.
#
# Nothing here pins an authored attack NAME (the content razor, tests/README.md #9). `first_leaf_under`
# asks for "whatever Attack offers first", which is a claim about the menu, not about the weapon.
extends Object


# The open ring, or null. There is one controller per open since #467 -- a category grows a ring on
# the same one -- but a just-picked menu lingers a frame before queue_free lands, so the
# queued-for-deletion check is load-bearing when a case opens a second menu.
static func controller_of(game: Node) -> ActionMenuController:
	var found: ActionMenuController = null
	for child in game.get_children():
		if child is ActionMenuController and not child.is_queued_for_deletion():
			found = child
	return found


# Indices from `nodes` down to the LEAF carrying `label`, or [] if nothing reachable does. Leaves
# only, so the Move category never shadows the Move verb inside it.
static func path_to(nodes: Array, label: String) -> Array[int]:
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		var children: Array = node.get("children", [])
		if children.is_empty():
			if String(node.get("name", "")) == label:
				var leaf: Array[int] = [i]
				return leaf
			continue
		var deeper := path_to(children, label)
		if not deeper.is_empty():
			var path: Array[int] = [i]
			path.append_array(deeper)
			return path
	var none: Array[int] = []
	return none


# What the KIT slice is called for this unit -- "Weapon" or "Rune" since #467 round 3, because it
# holds Reload and Burrow and carvings, none of which are attacks. Asked of MainActionMenu rather
# than typed here: a suite that spells the label itself is a second answer to what the slice is
# called, and goes stale the next time it is tuned. (It did, once, which is why this exists.)
static func kit_category(game: Node, unit: Unit) -> String:
	var menu: MainActionMenu = game.main_action_menu
	var display: Dictionary = menu.category_display(MainActionMenu.Group.ATTACK_GROUP, unit)
	return String(display.get("name", ""))


# The first leaf inside the named category, or {} -- and {} for a category that collapsed to a
# terminal slice, since then there is nothing "inside" it.
static func first_leaf_under(nodes: Array, category: String) -> Dictionary:
	for node: Dictionary in nodes:
		if String(node.get("name", "")) != category:
			continue
		var children: Array = node.get("children", [])
		if children.is_empty():
			return {}
		return children[0]
	return {}
