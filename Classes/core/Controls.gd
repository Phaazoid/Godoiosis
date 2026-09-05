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
	# --- What the player presses. Moved out of docs/SHORTCUTS.md by #691, which deleted it. The
	# WORDING is the player's, not the changelog's: the rules these lines carry are load-bearing
	# (right-click is two verbs, mode first; the tilt survives Q/E and only R levels it) but their
	# rationale and issue citations live in docs/design/ -- squad-system.md's LIFO-undo section,
	# visual-clarity.md's realign-keeps-the-tilt rule, presentation-effects.md's orbit_button knob.
	{"key": "Left-click", "context": Context.BOARD, "when": "",
		"does": "Select a tile or unit, commit the action ring's current slice, and confirm a target. With a ring open the whole screen is live -- the slice you get is the DIRECTION from the ring's centre, however far out you point -- and a click in the dead centre dismisses it.",
		"action": HARDCODED},
	{"key": "Right-click", "context": Context.BOARD, "when": "",
		"does": "Back out, mode first: it leaves an open aim, move pick or target pick, and collapses one ring at a time until there is nothing left to back out of. From a board already at rest it instead UNDOES your last order, newest first -- a group move comes back whole, because it was one decision.",
		"action": HARDCODED},
	{"key": "Right-click", "context": Context.BOARD, "when": "the newest order is one unit's own move",
		"does": "Re-opens that move's planning instead of undoing it, as though you had picked Move again. Pressing again with nothing planned leaves no move at all.",
		"action": HARDCODED},
	{"key": "Tab", "context": Context.BOARD, "when": "deploying, before a mission starts",
		"does": "Swap between the pre-mission menu and the board it is sitting on. The menu keeps its place, so looking at the ground you are about to fight over costs nothing. The Loadout button in the board's bottom-right corner is the same swap.",
		"action": "toggle_deployment_view"},
	{"key": "Enter", "context": Context.BOARD, "when": "deploying, before a mission starts",
		"does": "Begin the mission with the force you have placed. Refused while nobody is on the board -- a mission cannot start with no one to command. Begin Mission sits beside Loadout in that corner, and on the menu itself.",
		"action": "commit_deployment"},
	{"key": "Left-click", "context": Context.BOARD, "when": "deploying, before a mission starts",
		"does": "With the pre-mission menu swapped away: on one of your units, opens what you may still change about it -- squads, moving it to another cell in the deployment zone, and taking it back off the board. Picking Reposition lights the zone up and the next click places it, swapping with whoever is already there. On an empty cell inside the deployment zone, offers the units still waiting. There is no action ring here, because nothing is taking a turn yet.",
		"action": HARDCODED},
	{"key": "Click / Space / Enter", "context": Context.BOARD, "when": "someone is speaking",
		"does": "Advance the conversation. Dialog opens over the board, and the board waits underneath until the line is done.",
		"action": "dialogic_default_action"},
	{"key": "Escape", "context": Context.BOARD, "when": "",
		"does": "Pause: the menu with Restart, Save and Load, Glossary, Settings and Quit. Resume puts you back exactly where you were. Save is the one row that is not always live -- it is greyed while you are still placing your force, because a slot is a mid-battle snapshot and there is no battle yet.",
		"action": "ui_cancel"},
	{"key": "W / Up", "context": Context.CAMERA, "when": "",
		"does": "Pan the view forward, bounded to the board plus a margin.",
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
		"does": "Orbit AND tilt, freely -- sideways turns, up and down tilts, and both rest wherever you leave them. Tilting steeper is how you see into a hole the board's own angle hides. A drag orbits; a click that barely moves cancels instead.",
		"action": HARDCODED},
	{"key": "Q / E", "context": Context.CAMERA, "when": "",
		"does": "Square up to the next 90 degree turn -- one press realigns from any angle. The tilt SURVIVES it: looking down into a pit and then turning to see its other side is the gesture the tilt exists for, so squaring up must not throw the first half away.",
		"action": HARDCODED},
	{"key": "R", "context": Context.CAMERA, "when": "",
		"does": "Return to the opening shot the board loaded with. This is the ONLY thing that levels the tilt, and it returns to the mission's own authored angle rather than to flat.",
		"action": HARDCODED},
	{"key": "Mouse wheel", "context": Context.CAMERA, "when": "",
		"does": "Zoom, clamped so you cannot pull back past the whole board.",
		"action": HARDCODED},
	{"key": "Space", "context": Context.CAMERA, "when": "",
		"does": "Recentre on the cell under the pointer -- the fastest way back to the action after panning away.",
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
