extends Object
class_name Controls

# The game's BINDING registry (#690): every key and gesture, what it does, and the Input Map action
# it fires -- or that it has none. One store, projected to a surface; DevInfoTool is that surface
# for the dev context, and Glossary/GlossaryScreen is the precedent for the shape.
#
# It replaces docs/SHORTCUTS.md's dev-tools table, which was a hand-maintained THIRD copy beside the
# Input Map and the hardcoded checks, with nothing keeping it honest -- it had already drifted twice
# by its own admission, and it never learned about K at all. A registry can be law-tested against
# the real Input Map (tests/law/test_controls_coverage.gd), which a markdown table never could.
#
# `action` is the load-bearing field. Most bindings are NOT Input Map actions -- Q/E/R and the 3D
# pan are hardcoded physical_keycode checks in CameraRig3D, as are Space, F5, F4, V, K, the brush's
# Z/X/C and Ctrl+Z/Y -- so naming the action or declaring HARDCODED is what makes that visible
# instead of discovered. It is also what #691's player rebinding is gated on: only an entry with an
# action can be rebound, and the rest are the list of what still needs promoting.
#
# Two content rules:
#   - Every entry describes a binding that EXISTS. The law test walks the Input Map both ways, so a
#     documented action that was deleted and a dev action nobody documented both red.
#   - The store never moves into a page's layout. A projection may reorder or style entries; it may
#     not author one.
#
# Dev mode is editor-only tooling: none of these bindings are intended for the shipped game, and
# the page projecting them is a DevOverlay leaf, so it is absent from a demo build outright.

# Where a binding lives. #691 adds the player-facing contexts (the flat 2D game, the 3D battle view)
# when it has a Settings tab to render them on; DEV is the only one with a surface today.
enum Context { DEV }

const CONTEXT_NAMES: Dictionary[Context, String] = {
	Context.DEV: "Dev tools & authoring",
}

# `action` for a binding the Input Map does not own. Not "" as a bare literal at 14 call sites: the
# whole point of the field is that "has no action" is a DECLARED state, not a missing value.
const HARDCODED := ""

# Every binding, in display order. Fields:
#   key     -- what you press, as a player reads it
#   context -- which surface projects it
#   when    -- the mode that has to be live, or "" for always
#   does    -- what happens
#   action  -- the Input Map action, or HARDCODED
const ENTRIES: Array[Dictionary] = [
	{"key": "F1", "context": Context.DEV, "when": "",
		"does": "Toggle the dev-tools window — enters and leaves DEV_MODE with it.",
		"action": "toggle_dev_overlay"},
	{"key": "F2", "context": Context.DEV, "when": "",
		"does": "Reload the last-loaded scenario — an instant board reset.",
		"action": "dev_reset_scenario"},
	{"key": "F3", "context": Context.DEV, "when": "",
		"does": "File a bug report straight away — no card, no note, so the board is never covered. Lands in the report folder below.",
		"action": "dev_report_bug"},
	{"key": "F4", "context": Context.DEV, "when": "3D view",
		"does": "Toggle the flat 2D game full-screen and back. The only way there — the title screen deliberately offers no 2D option.",
		"action": HARDCODED},
	{"key": "Shift+F4", "context": Context.DEV, "when": "3D view",
		"does": "The corner picture-in-picture debug view.",
		"action": HARDCODED},
	{"key": "F5", "context": Context.DEV, "when": "flat 2D view",
		"does": "Toggle the elevation readout (#257) — each cell's height, with an arrow on ramps showing which way they rise. Throwaway: it goes when the real 2D height render lands.",
		"action": HARDCODED},
	{"key": "Space", "context": Context.DEV, "when": "dev mode, Spawn tool configured",
		"does": "Spawn a unit at the hovered cell. Outside dev mode the same key centres the camera instead — the help bar reads whichever is live.",
		"action": HARDCODED},
	{"key": "V", "context": Context.DEV, "when": "3D view — no dev mode needed",
		"does": "Cycle how deep the hover selector reads, Level ↔ Half. Deliberately ungated: the selector is up in ordinary play, so a key that needed dev mode would leave the thing visible and the key dead. The Game tab's Selector depth row is the same setting.",
		"action": HARDCODED},
	{"key": "K", "context": Context.DEV, "when": "a unit selected",
		"does": "Play the selected unit's zoom animations, one per press (#629) — the one question no test answers, whether a 66x42 combat sprite reads at the board's texel density. The set is found by convention at Resources/ZoomAnimations/<art family>.tres.",
		"action": HARDCODED},
	{"key": "Left-click a unit", "context": Context.DEV, "when": "dev mode",
		"does": "Edit that unit in the Unit Editor — the unit standing on THIS board, not its character file.",
		"action": HARDCODED},
	{"key": "Left-drag", "context": Context.DEV, "when": "dev mode, Tile Brush armed",
		"does": "Paint the selected tile, in both views; the 3D one previews the real block under the cursor. In Corners mode it drags the grid POINT nearest the cursor to the level picker's height instead, welding all four tiles that touch it.",
		"action": HARDCODED},
	{"key": "Right-click / right-drag", "context": Context.DEV, "when": "dev mode, Tile Brush armed",
		"does": "Erase a tile; in Corners mode, pull the point back to the board floor. This is why 3D orbit steps aside to middle-drag while the brush is armed.",
		"action": HARDCODED},
	{"key": "Mouse wheel", "context": Context.DEV, "when": "Tile Brush in Terrain or Corners mode",
		"does": "Raise or lower the level the brush paints at; negative levels are dips. Ctrl+wheel zooms instead while this is live. Inert in Zones and Tile States — the wheel answers in exactly the modes that SHOW the level row.",
		"action": HARDCODED},
	{"key": "Z / C", "context": Context.DEV, "when": "Tile Brush in Terrain mode",
		"does": "Turn the ramp rise one step, the way Q/E turn the board — None → North → East → South → West and around. Holding does not spin it. Greyed out for a tile that stands up: only flat ground can slope.",
		"action": HARDCODED},
	{"key": "X", "context": Context.DEV, "when": "Tile Brush in Terrain mode",
		"does": "Cycle how FAR that rise climbs — Full (45°, a level over one cell) ↔ Half (26.6°). Sits between Z and C so turn / pitch / turn read as one gesture. Survives Reset to flat: it is a preference, not part of the shape.",
		"action": HARDCODED},
	{"key": "Ctrl+Z", "context": Context.DEV, "when": "dev mode",
		"does": "Undo the last board EDIT — one press per stroke, not per cell. One stack across all four paint modes plus Resize Map and Clear Tile States. Not right-click's order undo, which takes back an order you gave.",
		"action": HARDCODED},
	{"key": "Ctrl+Shift+Z / Ctrl+Y", "context": Context.DEV, "when": "dev mode",
		"does": "Redo. A new edit after undoing abandons the redo tail; depth caps at 50, and loading a board clears the history — it belongs to one board.",
		"action": HARDCODED},
]


# Entries of one context, in declaration order.
static func in_context(context: Context) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in ENTRIES:
		if entry["context"] == context:
			result.append(entry)
	return result


static func context_name(context: Context) -> String:
	return CONTEXT_NAMES[context]


# The Input Map actions this registry claims, for the law test and for #691's rebinding list.
static func documented_actions() -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in ENTRIES:
		var action: String = entry["action"]
		if action != HARDCODED and not result.has(action):
			result.append(action)
	return result
