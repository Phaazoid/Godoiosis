# Is this label drawn wide enough to say what is written in it? PRELOADED, not class_name'd, like
# squad_fixtures:
#   const FIT := preload("res://tests/support/label_fit.gd")
#
# EXTRACTED from test_pre_mission_screen (#1024), where it had pinned the same rule at three
# surfaces since #944 and could not travel to a fourth. The rule is a FAMILY, not a screen's quirk:
# a clip_text Label declares a minimum width of ONE, and a container lays a child out at exactly its
# minimum unless the child's flags carry SIZE_EXPAND -- so a clipped label with nothing asking for
# width draws as a sliver of its first glyph. #788 met it in a ScrollContainer, #944 in the deployed
# strip, #989 in an HFlowContainer, #1024 in a plain HBox one card over.
#
# Measured off the font the label ACTUALLY draws with, so nothing here pins a pixel count and no
# theme or font change can make the assertion lie. This is the property a bug report names ("cut off
# instead of continuing to the right") stated in the one unit a feel pass cannot move.

# The label's laid-out width against its own text. Needs the label IN THE TREE and a frame past the
# layout pass -- `size` is what a container gave it, not what it asked for.
static func draws_in_full(label: Label) -> bool:
	if label.get_theme_font("font") == null:
		return true   # nothing to measure against; a caller's width assertions still speak
	return label.size.x + 0.5 >= ink_width(label)


# What this label's own text needs, in pixels.
static func ink_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x


# Every clipped label under `root`, which is the population this rule governs -- a label that does
# not clip asks for its own text already and cannot fail.
static func clipped_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child: Node in root.get_children():
		var label := child as Label
		if label != null and label.clip_text:
			out.append(label)
		out.append_array(clipped_labels(child))
	return out


# THE STRUCTURAL HALF, and the one that is fixture-free: a clipped label under a container that lays
# its children out at their own MINIMUM width, which has neither been given SIZE_EXPAND nor asked for
# a width of its own. That is the #1024 bug exactly -- not "too narrow for its text", which is what a
# clip is FOR, but "never asked, so it got the one pixel the flag declares".
#
# HBox and HFlow are the two containers in this family. A VBox, a MarginContainer or a PanelContainer
# stretches a child to its own width, so a clipped label in one of those is bounded by the column it
# sits in and clipping there is the design (ModFittingCard's mod descriptions are that case).
static func unasked_labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for label: Label in clipped_labels(root):
		var parent := label.get_parent()
		if not (parent is HBoxContainer or parent is HFlowContainer):
			continue
		if label.size_flags_horizontal & Control.SIZE_EXPAND:
			continue
		if label.custom_minimum_size.x > 1.0:
			continue
		out.append(label)
	return out
