class_name UiText
extends Object

# Presentation-layer text shaping for the HUD. Lives at the UI layer on purpose: the data layer
# (ArmorData.mechanical_text, WeaponInstance.status_text, info_panel's *_tooltip builders) produces
# LOGICAL lines, and baking a screen width into content would follow it onto any wider surface.
#
# Why it exists: Godot's built-in tooltip is a Label with autowrap OFF, and autowrap is a property
# rather than a theme item, so there is no global way to switch it on. A long line runs off the
# right edge of the screen instead of wrapping (found by feel-test 2026-07-29). So every tooltip
# in Classes/ui/ routes its text through wrap() -- pinned at RUNTIME by
# tests/ui/test_tooltip_rendering.gd, which populates the real inspect panel and checks that every
# rendered tooltip is already in wrapped form. (That suite replaced a source-scanning one on
# 2026-08-01; the claim that this layer had no runtime coverage because the game scene segfaults
# under the runner was false -- see tests/ui/test_game_scene_smoke.gd and #114.)
#
# Scope is game UI only. Classes/dev/ tooltips are short one-liners in their own OS window.

const TOOLTIP_WIDTH := 56   # characters per line; playtest-tunable

# Word-wraps each line to `width`, preserving any newlines the caller already put in. A single
# word longer than `width` overflows its own line rather than being broken mid-word -- readability
# beats strictness for item names, and nothing authored is that long yet.
static func wrap(text: String, width: int = TOOLTIP_WIDTH) -> String:
	if width <= 0 or text == "":
		return text
	var out: Array[String] = []
	for paragraph in text.split("\n"):
		out.append(_wrap_line(paragraph, width))
	return "\n".join(out)

static func _wrap_line(line: String, width: int) -> String:
	if line.length() <= width:
		return line
	var wrapped: Array[String] = []
	var current := ""
	for word in line.split(" ", false):
		if current == "":
			current = word
		elif current.length() + 1 + word.length() <= width:
			current += " " + word
		else:
			wrapped.append(current)
			current = word
	if current != "":
		wrapped.append(current)
	return "\n".join(wrapped)
