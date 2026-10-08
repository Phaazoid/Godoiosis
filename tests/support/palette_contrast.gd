# THE PALETTE CONTRAST WALKER (#814, shared since #1105): can the player READ a built surface under
# the live palette? It walks the real tree, and both halves of every comparison are read off the
# running node:
#   * the INK is Control.get_theme_color, i.e. override -> theme -> engine default, which is the one
#     read that cannot tell a styled label from an unstyled one apart by accident.
#   * the GROUND is COMPOSITED down the ancestor chain, because a stylebox may be translucent --
#     ModalCard's frame is the engine theme's panel at alpha 0.6, and parchment's own SECTION_BG is
#     opaque exactly where slate's is 0.7. Reading only the nearest panel gets both wrong.
#
# Moved out of tests/ui/test_pre_mission_contrast.gd when the Inspect dock and the info card joined the
# palette, so two suites ask one walker rather than a copy each.
extends Object

# test_queue_palette's floor and its metric, restated rather than imported: that suite is a plain
# Object with no seam to borrow from, and a second spelling of one subtraction is cheaper than the
# coupling. If the two ever disagree the pair cases and these will disagree loudly.
const CONTRAST_FLOOR := 0.25




# --- the metric ----------------------------------------------------------------------------------

static func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func contrast(ink: Color, ground: Color) -> float:
	return absf(luma(ink) - luma(ground))


static func over(top: Color, under: Color) -> Color:
	var a := top.a
	return Color(top.r * a + under.r * (1.0 - a),
			top.g * a + under.g * (1.0 - a),
			top.b * a + under.b * (1.0 - a), 1.0)


# The bg a stylebox contributes, or null-ish when it paints none. A StyleBoxEmpty and a flat button
# both draw nothing, which is what makes the ancestor chain rather than the node itself the answer.
static func _box_bg(box: StyleBox) -> Variant:
	var flat := box as StyleBoxFlat
	return null if flat == null else flat.bg_color


# Everything painted UNDER this control, composited outermost-first. A translucent panel over a
# translucent panel is the case a nearest-ancestor read gets wrong, and both palettes ship one.
static func _ground_under(node: Control, base: Color) -> Color:
	var chain: Array[Control] = []
	var walk: Node = node.get_parent()
	while walk != null:
		var as_control := walk as Control
		if as_control != null:
			chain.append(as_control)
		walk = walk.get_parent()
	chain.reverse()

	var ground := base
	for host: Control in chain:
		if not host.has_theme_stylebox_override("panel") and not (host is PanelContainer or host is Panel):
			continue
		var bg: Variant = _box_bg(host.get_theme_stylebox("panel"))
		if bg != null:
			ground = over(bg, ground)
	return ground


# A BUTTON USUALLY STANDS ON ITS OWN CHROME, and that is why the exit buttons pass while the labels
# beside them failed: the engine's own dark button box travels with its own light font colour. A
# FLAT button paints nothing, though -- the card's job picker is one -- so it falls through to the
# chain like a label, which is exactly where it was found to be cream on cream.
#
# ITS OWN BOX IS COMPOSITED, NEVER SUBSTITUTED, and getting that wrong is what this suite's first run
# reported: the engine's button box is dark at alpha 0.6, so treating it as the whole ground made
# every Deploy button read as white-on-cream and the real answer is the blend of the two.
static func _ground_for(node: Control, base: Color, box_name: String) -> Color:
	var under := _ground_under(node, base)
	var button := node as Button
	if button == null or button.flat or box_name == "":
		return under
	var bg: Variant = _box_bg(button.get_theme_stylebox(box_name))
	return under if bg == null else over(bg, under)


# Which font colours a control will actually draw, EACH WITH THE BOX IT IS DRAWN OVER.
#
# THE PAIRING IS THE POINT, and it was wrong here from #814 until #1022: a Button resolves hover
# independently in BOTH channels -- its ink and its chrome -- so reading the hover colour against the
# NORMAL box judges a state that never exists on screen. It went unseen because no control on these
# menus had a hover box that differed, so the two grounds happened to be the same colour; the detail
# chip is the first that inverts, and it was reported as unreadable while being the opposite.
#
# This is the same blind spot this suite already carries a note about one state along -- a sweep over
# a RESTING state cannot see the states a control can be put into -- and the cure is the same: name
# the state on both halves rather than on one.
#
# A RichTextLabel draws in `default_color` rather than `font_color` (the dock's squad box, #1105).
# Its bbcode spans carry their own colours and are not walked -- the caller's cases name those.
static func _ink_states(node: Control) -> Array:
	if node is Button:
		return [["font_color", node.get_theme_color("font_color"), "normal"],
				["font_hover_color", node.get_theme_color("font_hover_color"), "hover"]]
	if node is RichTextLabel:
		return [["default_color", node.get_theme_color("default_color"), ""]]
	return [["font_color", node.get_theme_color("font_color"), ""]]


static func _readable_text(node: Control) -> String:
	if node is Label:
		return (node as Label).text
	if node is Button:
		return (node as Button).text
	if node is RichTextLabel:
		return (node as RichTextLabel).get_parsed_text()
	return ""


static func walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(walk(child))
	return out


# Every finding under one root, as sentences. Empty means everything on it can be read.
static func findings(root: Node, base: Color, label: String) -> Array[String]:
	var out: Array[String] = []
	for node in walk(root):
		var control := node as Control
		if control == null:
			continue
		if _readable_text(control).strip_edges() == "":
			continue   # a spacer, or an empty inventory slot's placeholder
		for pair: Array in _ink_states(control):
			var ink: Color = pair[1]
			var ground := _ground_for(control, base, pair[2])
			var gap := contrast(ink, ground)
			if gap > CONTRAST_FLOOR:
				continue
			out.append("%s: %s \"%s\" draws %s at luma %.2f on a ground at %.2f (gap %.2f)" % [
				label, control.get_path(), _readable_text(control).substr(0, 24),
				pair[0], luma(ink), luma(ground), gap])
	return out
