# Iosis — Keys & Shortcuts

Quick reference for controls and dev-tool shortcuts. Keep this updated as new bindings are added (they live in Project Settings → Input Map, prefixed `cam_*` / `dev_*`). This is the canonical list — tab tooltips in the dev window should mirror it, not replace it.

## Gameplay
| Key | Action |
|-----|--------|
| Left-click | Select tile / unit; choose menu option; confirm targeting |
| Right-click | Deselect / cancel current mode; dismiss the action menu |
| W / A / S / D (or arrow keys) | Pan camera (`cam_up`/`cam_down`/`cam_left`/`cam_right`) |
| Space | Center camera on cursor *(outside dev mode)* |

## Dev tools
| Key | Action |
|-----|--------|
| F1 | Toggle the dev tools window (`toggle_dev_overlay`) — enters/exits DEV_MODE |
| Space | Spawn a unit at the hovered cell *(in dev mode, with the Spawn tool configured)* — hardcoded `KEY_SPACE` check in `game.gd`, not an Input Map action |
| F2 | Reload the last-loaded scenario (`dev_reset_scenario`) — instant board reset |
| Left-click a unit | (DEV_MODE) Edit that unit in the Unit Editor |
| Left-drag | (DEV_MODE, Tile Brush active) Paint the selected tile |
| Right-click | (DEV_MODE, Tile Brush active) Erase a tile |

## Notes
- The dev tools open as a **separate OS window** (draggable to a second monitor). See `CLAUDE.md` → "Dev tools = separate OS window" for the architecture.
- Dev mode is editor-only tooling; none of the `dev_*` bindings are intended for the shipped game.
- Scenarios (saved skirmish setups: units, squads, loadouts, tiles) live in `res://Scenarios/` and are saved/loaded from the dev tools' Save/Load section.
