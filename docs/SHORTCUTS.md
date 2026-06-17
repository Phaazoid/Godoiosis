# Iosis — Keys & Shortcuts

Quick reference for controls, dev-tool shortcuts, and Claude workflow commands. Keep this updated as new bindings are added (in-game ones live in Project Settings → Input Map, prefixed `cam_*` / `dev_*`). This is the canonical list — tab tooltips in the dev window should mirror it, not replace it.

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

## Claude slash commands
Typed into the **Claude Code chat** (not in-game). Each lives as a file in [`.claude/commands/`](../.claude/commands/) — the filename *is* the command name, and the file is the instructions Claude follows when you run it. Anything after the command is passed in as an argument to scope the run.

| Command | What it does |
|---------|--------------|
| `/agent-queue` | Scan the open GitHub issues labeled `agent/claude` and advance each one a step — draft a fix walkthrough, do `tests/`/`docs/` work directly, or flag a decision — then flip it to `agent/human`. Add issue numbers (e.g. `/agent-queue 23 25`) to work only those. |
| `/scratchpad-sweep` | Read [`docs/SCRATCHPAD.md`](SCRATCHPAD.md), file each **Inbox** idea into the right design doc / a proposed issue / the defer pile, log where it went, and leave the Inbox empty. Add an area or idea (e.g. `/scratchpad-sweep weapons`) to sweep just those. |

## Notes
- The dev tools open as a **separate OS window** (draggable to a second monitor). See `CLAUDE.md` → "Dev tools = separate OS window" for the architecture.
- Dev mode is editor-only tooling; none of the `dev_*` bindings are intended for the shipped game.
- Scenarios (saved skirmish setups: units, squads, loadouts, tiles) live in `res://Scenarios/` and are saved/loaded from the dev tools' Save/Load section.
