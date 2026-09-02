# Iosis — Player Controls

What the player presses, in both views. **The dev-tools and authoring keys are NOT here** — they live in the dev window itself, on **Session → Info**, projected from `Classes/core/Controls.gd` ([#690](https://github.com/Phaazoid/Godoiosis/issues/690)); the Claude slash commands moved to `CLAUDE.md`. In-game bindings that are Input Map actions are prefixed `cam_*` / `dev_*`, but most are hardcoded key checks — the registry says which is which, per entry.

**This file is on its way out.** [#691](https://github.com/Phaazoid/Godoiosis/issues/691) gives Settings a Controls tab reading the same registry, and deletes this file when it lands. The two tables below are here because they are load-bearing rulings in prose, not because a document is the right home for them — do not add to them.

## Gameplay (the flat 2D game)
| Key | Action |
|-----|--------|
| Left-click | Select tile / unit; commit the action ring's current slice; confirm targeting. On an open ring the whole screen is live — the slice you get is the DIRECTION from the ring's centre, however far away the pointer is — and a click in the dead centre dismisses |
| Right-click | Two verbs, mode first ([#228](https://github.com/Phaazoid/Godoiosis/issues/228)): cancel the current mode — an open aim, move pick or target pick. On an open action ring it instead COLLAPSES one ring (#467), dismissing only once there is nothing left to back out of. From a board already at rest it instead **undoes the last order you gave**, one press per order, newest first. A group move undoes whole (it was one decision); hold-position fillers are never what a press takes |
| W / A / S / D (or arrow keys) | Pan camera (`cam_up`/`cam_down`/`cam_left`/`cam_right`) |
| Space | Center camera on cursor *(outside dev mode)* |

## The 3D battle view (`Scenes/Battle3D`, #176) — this is what the game boots into
**`Battle3D.tscn` is the main scene as of 2026-08-14.** Launching the game lands here, on Mission Select drawn over the 3D world; **F4** is the only way to the flat 2D game and it toggles straight back. That key is dev-gated, so it is in the Info tab's registry rather than in the table below. There is deliberately no 2D option on the title screen.

The 2D game runs underneath as the UI layer, so every UI click behaves exactly as above. These are the board-and-camera keys the 3D host owns. **Note the 2D camera stands down here** — `cam_*` reaches the 3D rig only, so W/A/S/D and the arrows drive one camera, not two.

| Key | Action |
|-----|--------|
| Left-click | Act on the cell under the pointer (delivered straight to the 2D dispatchers) |
| Right-click | Exactly as in the 2D table above — cancel the open mode, or undo the last order from a board at rest ([#228](https://github.com/Phaazoid/Godoiosis/issues/228)). Not a parallel implementation: the picker calls `game._on_right_click`, the same dispatcher, so the two views cannot drift |
| Right-drag | Orbit **and tilt** freely; both rest wherever you leave them. Sideways turns the yaw, up/down tilts the pitch ([#586](https://github.com/Phaazoid/Godoiosis/issues/586)) — grab-the-world in each axis, at one shared `orbit_sensitivity` — read ONCE for both axes since [#394](https://github.com/Phaazoid/Godoiosis/issues/394), because a player's *Mouse sensitivity* step scales it and reaching only one axis would make a diagonal drag curve. The tilt is clamped to a band the *Game* tab owns (`Tilt limit: shallow` / `Tilt limit: steep`), not a mood: a mission may not re-teach the controls. Steeper is how you see into a one-cell hole the board's own angle hides. It shares the button with cancel: a drag orbits, a click under the slop cancels (`orbit_button` is an inspector knob, and flipping it to middle moves cancel back to press). While the Tile Brush is armed the brush takes right-click to erase, so orbit falls back to **middle**-drag on its own and the help bar reads whichever is live |
| Q / E | Snap to the next 90° detent — one press realigns from any angle. **Yaw only: the tilt survives** (dev ruling, 2026-08-27). Looking down into a pit and then turning to see its other side is the gesture the tilt exists for, so squaring up must not throw the first half away |
| Mouse wheel | Zoom (clamped so you cannot pull back past the whole board). While the Tile Brush is armed in **Terrain** or **Corners** mode the brush takes the wheel for its paint level and **Ctrl+wheel** zooms instead ([#285](https://github.com/Phaazoid/Godoiosis/issues/285)) — scoped to the two modes that pick a height (Terrain and **Corners**), since Zones and Tile States never read the wheel. The help bar reads whichever is live |
| W / A / S / D (or arrows) | Pan the diorama, bounded to the board plus a margin |
| Space | Recentre the diorama on the pointer cell — **unless dev mode is up**, where it spawns instead, the same precedence the flat game gives it |
| R | Reset to the opening shot (the framing the board loaded with) — **the only leveller for the tilt**, which returns to the board's own authored angle rather than a second copy of it |

The view **opens close on your own squad**, not on the whole board (`opening_view_cells`); the board is what bounds zoom and panning, so pulling back still reaches every corner. During an AI turn the camera follows the acting squad by itself, squares up to the nearest 90° detent, and refuses manual input until the turn ends.

## Notes
- **Bindings are deliberately IDENTICAL between the two views** — the flat game is not a different control scheme. The one runtime difference is right-click: the brush claims it to erase while armed, so orbit falls back to middle-drag and the help bar re-reads the live binding. 3D-*native* authoring — placing at height rather than on the flat plane — **landed with [#285](https://github.com/Phaazoid/Godoiosis/issues/285)**: the wheel sets the brush's paint level in the 3D view too, and a ghost block hangs at the level the next click would produce. See the 3D battle view table above. *(This note previously called that a separate future issue gated on #218's verticality work. Both halves are dead: #218's design landed in [verticality.md](design/verticality.md) and the issue is closed, and #285 built the authoring on top of it — #340 then folded the level into the terrain brush itself.)*
