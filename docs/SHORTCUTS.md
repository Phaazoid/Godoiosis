# Iosis — Keys & Shortcuts

Quick reference for controls, dev-tool shortcuts, and Claude workflow commands. Keep this updated as new bindings are added (in-game ones live in Project Settings → Input Map, prefixed `cam_*` / `dev_*`). This is the canonical list — tab tooltips in the dev window should mirror it, not replace it.

## Gameplay (the flat 2D game)
| Key | Action |
|-----|--------|
| Left-click | Select tile / unit; choose menu option; confirm targeting |
| Right-click | Deselect / cancel current mode; dismiss the action menu |
| W / A / S / D (or arrow keys) | Pan camera (`cam_up`/`cam_down`/`cam_left`/`cam_right`) |
| Space | Center camera on cursor *(outside dev mode)* |

## The 3D battle view (`Scenes/Battle3D`, #176) — this is what the game boots into
**`Battle3D.tscn` is the main scene as of 2026-08-14.** Launching the game lands here, on Mission Select drawn over the 3D world; **F4** is the only way to the flat 2D game and it toggles straight back. There is deliberately no 2D option on the title screen.

The 2D game runs underneath as the UI layer, so every UI click behaves exactly as above. These are the board-and-camera keys the 3D host owns. **Note the 2D camera stands down here** — `cam_*` reaches the 3D rig only, so W/A/S/D and the arrows drive one camera, not two.

| Key | Action |
|-----|--------|
| Left-click | Act on the cell under the pointer (delivered straight to the 2D dispatchers) |
| Right-click | Cancel the current mode — an open aim or move pick. It does **not** unqueue orders (that is [#228](https://github.com/Phaazoid/Godoiosis/issues/228)), so with no mode open it does nothing |
| Right-drag | Orbit freely; the yaw rests wherever you leave it. It shares the button with cancel: a drag orbits, a click under the slop cancels (`orbit_button` is an inspector knob, and flipping it to middle moves cancel back to press). While the Tile Brush is armed the brush takes right-click to erase, so orbit falls back to **middle**-drag on its own and the help bar reads whichever is live |
| Q / E | Snap to the next 90° detent — one press realigns from any angle |
| Mouse wheel | Zoom (clamped so you cannot pull back past the whole board) |
| W / A / S / D (or arrows) | Pan the diorama, bounded to the board plus a margin |
| Space | Recentre the diorama on the pointer cell — **unless dev mode is up**, where it spawns instead, the same precedence the flat game gives it |
| R | Reset to the opening shot (the framing the board loaded with) |
| F4 | Toggle the flat 2D game full-screen and back *(dev builds)* |
| Shift + F4 | The corner picture-in-picture debug view *(dev builds)* |

The view **opens close on your own squad**, not on the whole board (`opening_view_cells`); the board is what bounds zoom and panning, so pulling back still reaches every corner. During an AI turn the camera follows the acting squad by itself, squares up to the nearest 90° detent, and refuses manual input until the turn ends.

## Dev tools
| Key | Action |
|-----|--------|
| F1 | Toggle the dev tools window (`toggle_dev_overlay`) — enters/exits DEV_MODE |
| Space | Spawn a unit at the hovered cell *(in dev mode, with the Spawn tool configured)* — hardcoded `KEY_SPACE` check in `game.gd`, not an Input Map action |
| F2 | Reload the last-loaded scenario (`dev_reset_scenario`) — instant board reset |
| F5 | Toggle the elevation readout ([#257](https://github.com/Phaazoid/Godoiosis/issues/257)) — each cell's height, with an arrow on ramps showing which way they rise. Flat 2D view only; **throwaway**, and deleted when the real 2D height render lands. Hardcoded `KEY_F5` in `game.gd`, gated on `DevTools.enabled()`. The elevation brush lights it too (#260), and the two reasons are independent: leaving Elevation mode never switches off a readout F5 asked for |
| Left-click a unit | (DEV_MODE) Edit that unit in the Unit Editor |
| Left-drag | (DEV_MODE, Tile Brush active) Paint the selected tile — works in **both** views; the 3D one previews the real block under the cursor |
| Right-click | (DEV_MODE, Tile Brush active) Erase a tile. In the 3D view this is why orbit steps aside to middle-drag while the brush is armed |
| Mouse wheel | (DEV_MODE, Tile Brush in **Elevation** mode) Raise / lower the level the brush paints at ([#260](https://github.com/Phaazoid/Godoiosis/issues/260)). Negative levels are dips. Inert in every other paint mode; the tab's *Reset to flat (0)* button returns the brush to level 0 with no ramp. Entering Elevation mode lights the F5 readout on its own — **paint heights in the 2D view (F4)**, since nothing renders elevation in 3D yet |
| Z / C | (DEV_MODE, Tile Brush in **Elevation** mode) Turn the ramp rise one step, the way Q/E turn the board — None → North → East → South → West and around. Holding the key does not spin it. Same gate as the wheel: inert with the brush down or in another paint mode |

## Claude slash commands
Typed into the **Claude Code chat** (not in-game). Each lives as a file in [`.claude/commands/`](../.claude/commands/) — the filename *is* the command name, and the file is the instructions Claude follows when you run it. Anything after the command is passed in as an argument to scope the run.

| Command | What it does |
|---------|--------------|
| `/agent-queue` | Scan the open GitHub issues labeled `agent/claude` and advance each one a step — post a plan (feature / core-gameplay change), fix it and write it up (small bugfix, `tests/`, `docs/`), or flag a decision — then flip it to `agent/human`. Add issue numbers (e.g. `/agent-queue 23 25`) to work only those. |
| `/scratchpad-sweep` | Read [`docs/SCRATCHPAD.md`](SCRATCHPAD.md), file each **Inbox** idea into the right design doc / a proposed issue / the defer pile, log where it went, and leave the Inbox empty. Add an area or idea (e.g. `/scratchpad-sweep weapons`) to sweep just those. |

## Notes
- The dev tools open as a **separate OS window** (draggable to a second monitor). See `CLAUDE.md` → "Dev tools = separate OS window" for the architecture.
- **The dev bindings work in the 3D view as of #231 (v0.20.0).** The tile brush paints and erases there, SPACE spawns, and the brush previews the real 3D block under the cursor. *(This note previously said every `dev_*` binding was inert in 3D, blaming an absolute `DevOverlay` path in `game.gd`. Both halves are dead: the lookup became relative earlier in the arc, and the input plumbing landed with #231.)*
- **Bindings are deliberately IDENTICAL between the two views** — the flat game is not a different control scheme. The one runtime difference is right-click: the brush claims it to erase while armed, so orbit falls back to middle-drag and the help bar re-reads the live binding. 3D-*native* authoring — placing at height rather than on the flat plane — is a separate future issue, gated on #218's verticality work.
- Dev mode is editor-only tooling; none of the `dev_*` bindings are intended for the shipped game.
- Scenarios (saved skirmish setups: units, squads, loadouts, tiles) live in `res://Scenarios/` and are saved/loaded from the dev tools' Save/Load section.
