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
#   - A `does` IS A PHRASE, NOT A PARAGRAPH (#816, dev: "some of those descriptions were so wordy...
#     Nobody is going to read all of the current novel"). One sentence, two where a binding genuinely
#     has two verbs. WHY a rule is the way it is belongs in docs/design/ and is cited from there, not
#     restated here -- a page nobody finishes reading documents nothing, and the long form was a
#     SECOND COPY of something already written down.
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
		"does": "Open or close the dev-tools window.",
		"action": "toggle_dev_overlay"},
	{"key": "F2", "context": Context.DEV, "when": "",
		"does": "Reload the last scenario -- an instant board reset.",
		"action": "dev_reset_scenario"},
	{"key": "F3", "context": Context.DEV, "when": "",
		"does": "File a bug report straight away, with no card in the way.",
		"action": "dev_report_bug"},
	{"key": "F4", "context": Context.DEV, "when": "3D view",
		"does": "Full-screen the flat 2D game, and back. The only way there.",
		"action": HARDCODED},
	{"key": "Shift+F4", "context": Context.DEV, "when": "3D view",
		"does": "The corner picture-in-picture debug view.",
		"action": HARDCODED},
	{"key": "F5", "context": Context.DEV, "when": "flat 2D view",
		"does": "Toggle the elevation readout -- each cell's height, arrows on ramps.",
		"action": HARDCODED},
	{"key": "Space", "context": Context.DEV, "when": "dev mode, Spawn tool configured",
		"does": "Spawn a unit at the hovered cell. Outside dev mode it centres the camera.",
		"action": HARDCODED},
	{"key": "V", "context": Context.DEV, "when": "3D view — no dev mode needed",
		"does": "Cycle how deep the hover selector reads, Level or Half. Same as the Game tab's row.",
		"action": HARDCODED},
	{"key": "K", "context": Context.DEV, "when": "a unit selected",
		"does": "Play the selected unit's zoom animations, one per press.",
		"action": HARDCODED},
	{"key": "Left-click a unit", "context": Context.DEV, "when": "dev mode",
		"does": "Edit that unit in the Unit Editor -- this board's copy, not its character file.",
		"action": HARDCODED},
	{"key": "Left-drag", "context": Context.DEV, "when": "dev mode, Tile Brush armed",
		"does": "Paint the selected tile. In Corners mode, drag the nearest grid point to the picker's height.",
		"action": HARDCODED},
	{"key": "Right-click / right-drag", "context": Context.DEV, "when": "dev mode, Tile Brush armed",
		"does": "Erase a tile; in Corners mode, pull the point back to the floor.",
		"action": HARDCODED},
	{"key": "Mouse wheel", "context": Context.DEV, "when": "Tile Brush in Terrain or Corners mode",
		"does": "Raise or lower the level the brush paints at. Ctrl+wheel zooms instead.",
		"action": HARDCODED},
	{"key": "Z / C", "context": Context.DEV, "when": "Tile Brush in Terrain mode",
		"does": "Turn the ramp rise one step, the way Q/E turn the board. Flat ground only.",
		"action": HARDCODED},
	{"key": "X", "context": Context.DEV, "when": "Tile Brush in Terrain mode",
		"does": "Cycle how far that rise climbs -- Full or Half.",
		"action": HARDCODED},
	{"key": "Ctrl+Z", "context": Context.DEV, "when": "dev mode",
		"does": "Undo the last board edit -- one press per stroke, not per cell.",
		"action": HARDCODED},
	{"key": "Ctrl+Shift+Z / Ctrl+Y", "context": Context.DEV, "when": "dev mode",
		"does": "Redo. A new edit abandons the redo tail.",
		"action": HARDCODED},
	# --- What the player presses. Moved out of docs/SHORTCUTS.md by #691, which deleted it. The
	# WORDING is the player's, not the changelog's, and #816 cut every one of these to a phrase. The
	# rules they carry are still load-bearing -- right-click is two verbs, mode first; the tilt
	# survives Q/E and only R levels it -- so each keeps the clause that says so and drops the
	# explanation, which lives in docs/design/ anyway: squad-system.md's LIFO-undo section,
	# visual-clarity.md's realign-keeps-the-tilt rule, presentation-effects.md's orbit_button knob.
	{"key": "Left-click", "context": Context.BOARD, "when": "",
		"does": "Select a tile or unit, and confirm. With a ring open, the slice you get is the direction you point.",
		"action": HARDCODED},
	{"key": "Right-click", "context": Context.BOARD, "when": "",
		"does": "Back out one step: an open aim or pick first, then the ring. From a board at rest, undo your last order.",
		"action": HARDCODED},
	{"key": "Right-click", "context": Context.BOARD, "when": "the newest order is one unit's own move",
		"does": "Reopen that move's planning instead of undoing it.",
		"action": HARDCODED},
	{"key": "Tab", "context": Context.BOARD, "when": "deploying, before a mission starts",
		"does": "Swap between the pre-mission menu and the board. Same as the Loadout button.",
		"action": "toggle_deployment_view"},
	{"key": "Enter", "context": Context.BOARD, "when": "deploying, before a mission starts",
		"does": "Begin the mission with the force you have placed. A card asks first; there is no coming back.",
		"action": "commit_deployment"},
	{"key": "Left-click", "context": Context.BOARD, "when": "deploying, before a mission starts",
		"does": "On one of your units: squads, reposition, take it off. On an empty deployment cell: who is still waiting.",
		"action": HARDCODED},
	{"key": "Click / Space / Enter", "context": Context.BOARD, "when": "someone is speaking",
		"does": "Advance the conversation.",
		"action": "dialogic_default_action"},
	{"key": "Escape", "context": Context.BOARD, "when": "",
		"does": "Pause -- Restart, Save, Load, Glossary, Settings, Quit. Save is greyed until the battle starts.",
		"action": "ui_cancel"},
	{"key": "W / Up", "context": Context.CAMERA, "when": "",
		"does": "Pan the view forward.",
		"action": "cam_up"},
	{"key": "S / Down", "context": Context.CAMERA, "when": "",
		"does": "Pan the view back.",
		"action": "cam_down"},
	{"key": "A / Left", "context": Context.CAMERA, "when": "",
		"does": "Pan the view left.",
		"action": "cam_left"},
	{"key": "D / Right", "context": Context.CAMERA, "when": "",
		"does": "Pan the view right.",
		"action": "cam_right"},
	{"key": "Right-drag", "context": Context.CAMERA, "when": "",
		"does": "Orbit and tilt freely -- both rest wherever you leave them.",
		"action": HARDCODED},
	{"key": "Q / E", "context": Context.CAMERA, "when": "",
		"does": "Square up to the next 90 degrees. The tilt survives it.",
		"action": HARDCODED},
	{"key": "R", "context": Context.CAMERA, "when": "",
		"does": "Return to the board's opening shot. The only thing that levels the tilt.",
		"action": HARDCODED},
	{"key": "Mouse wheel", "context": Context.CAMERA, "when": "",
		"does": "Zoom, clamped to the whole board.",
		"action": HARDCODED},
	{"key": "Space", "context": Context.CAMERA, "when": "",
		"does": "Recentre on the cell under the pointer.",
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
