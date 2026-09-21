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
# Three content rules:
#   - Every entry describes a binding that EXISTS. The law test walks the Input Map both ways, so a
#     documented action that was deleted and a dev action nobody documented both red.
#   - The store never moves into a page's layout. A projection may reorder or style entries; it may
#     not author one.
#   - A `does` IS A LABEL, NOT A SENTENCE (#816, dev twice: "some of those descriptions were so
#     wordy... Nobody is going to read all of the current novel", then "Left Click - Select / Right
#     Click - Cancel / Tab - Menu Swap" when the first pass only got them down to a sentence). Two or
#     three words. WHY a rule is the way it is belongs in docs/design/ and is cited from there -- a
#     page nobody finishes reading documents nothing, and the long form was a SECOND COPY of
#     something already written down.
#   - A `when` IS A SECTION NAME, so equal ones are kept TOGETHER in this list. The Settings page
#     prints it on the change and the run below it belongs to it; a `when` that is a sentence, or one
#     that repeats non-adjacently, breaks that page rather than just reading badly.
#
# Dev mode is editor-only tooling: none of these bindings are intended for the shipped game, and
# the page projecting them is a DevOverlay leaf, so it is absent from a demo build outright.

# Where a binding lives, and what a SURFACE projects. The split is by what the player is doing --
# BOARD and CAMERA -- deliberately NOT by view (#691): `docs/SHORTCUTS.md` listed "the flat 2D game"
# and "the 3D battle view" as separate control schemes, and for a player that is a distinction
# without a difference. F4 is gated on DevTools.enabled(), so a shipped build has no flat 2D view to
# reach at all, and the bindings were identical between the two by design anyway. Splitting a
# player's controls page that way would document a screen they can never open.
enum Context { DEV, BOARD, CAMERA }

const CONTEXT_NAMES: Dictionary[Context, String] = {
	Context.DEV: "Dev tools & authoring",
	Context.BOARD: "On the board",
	Context.CAMERA: "Camera",
}

# The contexts a PLAYER may see. Declared rather than "everything except DEV", so that adding a
# second dev-only context cannot silently leak it into the Settings page.
const PLAYER_CONTEXTS: Array[Context] = [Context.BOARD, Context.CAMERA]

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
		"does": "Dev tools",
		"action": "toggle_dev_overlay"},
	{"key": "F2", "context": Context.DEV, "when": "",
		"does": "Reload the board",
		"action": "dev_reset_scenario"},
	# PLAIN F3 IS THE PLAYER'S NOW (#1050) and lives in the BOARD block below. What is left here is
	# the zero-friction path: no card, no note, straight to a filed report -- which is correct for
	# the developer and meaningless to anybody else, since the note is the whole of what a stranger
	# has to say.
	{"key": "Shift+F3", "context": Context.DEV, "when": "",
		"does": "File a report instantly",
		"action": "dev_report_instant"},
	{"key": "F4", "context": Context.DEV, "when": "3D view",
		"does": "Flat 2D, full screen",
		"action": HARDCODED},
	{"key": "Shift+F4", "context": Context.DEV, "when": "3D view",
		"does": "Corner debug view",
		"action": HARDCODED},
	{"key": "F5", "context": Context.DEV, "when": "flat 2D view",
		"does": "Elevation readout",
		"action": HARDCODED},
	{"key": "Space", "context": Context.DEV, "when": "Spawn tool armed",
		"does": "Spawn a unit. Otherwise centres the camera",
		"action": HARDCODED},
	{"key": "V", "context": Context.DEV, "when": "3D view",
		"does": "Selector depth: Level or Half",
		"action": HARDCODED},
	{"key": "K", "context": Context.DEV, "when": "a unit selected",
		"does": "Play its zoom animations",
		"action": HARDCODED},
	{"key": "Left-click a unit", "context": Context.DEV, "when": "dev mode",
		"does": "Edit it in the Unit Editor",
		"action": HARDCODED},
	{"key": "Left-drag", "context": Context.DEV, "when": "Tile Brush armed",
		"does": "Paint. In Corners mode, drag the nearest point",
		"action": HARDCODED},
	{"key": "Right-click / right-drag", "context": Context.DEV, "when": "Tile Brush armed",
		"does": "Erase",
		"action": HARDCODED},
	{"key": "Mouse wheel", "context": Context.DEV, "when": "Brush: Terrain or Corners",
		"does": "Brush level. Ctrl+wheel zooms",
		"action": HARDCODED},
	{"key": "Z / C", "context": Context.DEV, "when": "Brush: Terrain",
		"does": "Turn the ramp rise",
		"action": HARDCODED},
	{"key": "X", "context": Context.DEV, "when": "Brush: Terrain",
		"does": "Ramp pitch: Full or Half",
		"action": HARDCODED},
	{"key": "Ctrl+Z", "context": Context.DEV, "when": "dev mode",
		"does": "Undo a board edit",
		"action": HARDCODED},
	{"key": "Ctrl+Shift+Z / Ctrl+Y", "context": Context.DEV, "when": "dev mode",
		"does": "Redo",
		"action": HARDCODED},
	# --- What the player presses. Moved out of docs/SHORTCUTS.md by #691, which deleted it. The
	# WORDING is the player's, not the changelog's, and #816 cut every one of these to a LABEL. The
	# rules behind them are unchanged and are not written here any more -- right-click being two verbs
	# and the tilt surviving Q/E are both real, and both live in docs/design/: squad-system.md's
	# LIFO-undo section, visual-clarity.md's realign-keeps-the-tilt rule, presentation-effects.md's
	# orbit_button knob. What a player needs at the moment they open this page is which key, not why.
	{"key": "Left-click", "context": Context.BOARD, "when": "",
		"does": "Select",
		"action": HARDCODED},
	{"key": "Right-click", "context": Context.BOARD, "when": "",
		"does": "Cancel",
		"action": HARDCODED},
	{"key": "Escape", "context": Context.BOARD, "when": "",
		"does": "Pause menu",
		"action": "ui_cancel"},
	{"key": "T", "context": Context.BOARD, "when": "",
		"does": "Cycle enemy intent",
		"action": "toggle_threat_view"},
	{"key": "V", "context": Context.BOARD, "when": "",
		"does": "Enemy ranges",
		"action": "toggle_enemy_ranges"},
	# A PLAYER BINDING SINCE #1050. It was a dev key for its whole life, which meant a shipped build
	# had no hotkey for the one thing a stranger most needs to do -- and this page is half the point
	# of promoting it, the other half being that a key nobody is told about is not a door.
	{"key": "F3", "context": Context.BOARD, "when": "",
		"does": "Report a bug",
		"action": "report_bug"},
	{"key": "Shift+click", "context": Context.BOARD, "when": "On an enemy",
		"does": "Pin its ranges",
		"action": HARDCODED},
	{"key": "Right-click", "context": Context.BOARD, "when": "After a move order",
		"does": "Re-plan that move",
		"action": HARDCODED},
	{"key": "Tab", "context": Context.BOARD, "when": "Deploying",
		"does": "Menu swap",
		"action": "toggle_deployment_view"},
	{"key": "Enter", "context": Context.BOARD, "when": "Deploying",
		"does": "Begin the mission",
		"action": "commit_deployment"},
	{"key": "Left-click", "context": Context.BOARD, "when": "Deploying",
		"does": "Unit options, or place a unit",
		"action": HARDCODED},
	{"key": "Click / Space / Enter", "context": Context.BOARD, "when": "In dialog",
		"does": "Advance",
		"action": "dialogic_default_action"},
	{"key": "W / Up", "context": Context.CAMERA, "when": "",
		"does": "Pan forward",
		"action": "cam_up"},
	{"key": "S / Down", "context": Context.CAMERA, "when": "",
		"does": "Pan back",
		"action": "cam_down"},
	{"key": "A / Left", "context": Context.CAMERA, "when": "",
		"does": "Pan left",
		"action": "cam_left"},
	{"key": "D / Right", "context": Context.CAMERA, "when": "",
		"does": "Pan right",
		"action": "cam_right"},
	{"key": "Right-drag", "context": Context.CAMERA, "when": "",
		"does": "Orbit and tilt",
		"action": HARDCODED},
	{"key": "Q / E", "context": Context.CAMERA, "when": "",
		"does": "Square up 90 degrees",
		"action": HARDCODED},
	{"key": "R", "context": Context.CAMERA, "when": "",
		"does": "Reset the view",
		"action": HARDCODED},
	{"key": "Mouse wheel", "context": Context.CAMERA, "when": "",
		"does": "Zoom",
		"action": HARDCODED},
	{"key": "Space", "context": Context.CAMERA, "when": "",
		"does": "Recentre on the pointer",
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
