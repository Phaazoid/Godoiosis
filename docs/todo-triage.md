# In-code TODO triage — 2026-06-18

A one-time sweep of every `#TODO` left in the gameplay code, sorted into bins.
Vendor code (`addons/gdUnit4/`) is excluded — those TODOs belong to the test
framework, not to us.

**Found:** 13 comments — 11 in `game.gd`, 1 in `Classes/squads/Squad.gd`,
1 in `Classes/units/UnitFactory.gd`.

**Method:** every verdict was checked against the surrounding code, not just the
comment text.

**Note:** removing or rewording the comments themselves is the dev's job — they
live in gameplay code (see the collaboration contract in `CLAUDE.md`). This file
is the map of what to do with each.

---

## 1 · Already addressed or obsolete — delete the comment

The thing the comment asks for is already done, or the code it described is gone.

| Where | Comment | Verdict |
|---|---|---|
| `game.gd:864-865` | `# draw_squad_leader_range(...) #TODO - implement selective tile map deletion` | **Obsolete.** Dead, commented-out code. `OverlayManager` already does selective clears (`clear_target_icon_by_cell`, `clear_squad_range`, `clear_unit_icon_types`). Delete both lines. |
| `game.gd:222-223` | `#TODO ... only snap when unit's move is off screen` | **Probably stale.** `enter_move_mode()` no longer centres the camera at all — the "always snapping to center" behaviour the note worries about isn't in the function. Confirm nothing else snaps on move-enter, then delete. |
| `game.gd:591` | `#TODO Instead of a clear here, a refresh to projected cell` | **Probably moot.** The `clear_target_icon_by_cell` call is immediately followed by `redraw_squad_unit_icons(squad)` (line 596), which already redraws icons at projected cells. Confirm in play, then delete. |

## 2 · Mooted by a design / philosophy change

*(none)* — none of the surviving TODOs are killed by the three Laws or the
no-leveling decision. Called out so the bin isn't silently empty.

## 3 · Far-future — correctly deferred, leave them

Load-bearing reminders that depend on systems that don't exist yet. Keep as-is.

| Where | Depends on |
|---|---|
| `game.gd:532` — flyers spawning on non-walkable tiles | unit movement-classes |
| `game.gd:648` — more tile-walkability values (flyers vs. nothing) | unit movement-classes |
| `game.gd:862` — muted squad-icon colours when another squad is active | multi-squad visual layer — now tracked under **#44** (visual clarity) |
| `Classes/squads/Squad.gd:94` — preserve status actions when clearing the queue | a status-effect system (explicitly "if that becomes a thing") |

## 4 · Overdue — worth doing now

| Where | Comment | Verdict |
|---|---|---|
| `game.gd:648` (magic-number half) | was `if move_cost > 98: #...This is bad, placeholder logic. Fix later.` | **Already fixed in your working tree** (uncommitted): swapped to `CANNOT_WALK_TILE` and reworded to the forward-looking flyer note. Just commit it. This was the one genuine code smell — and you caught it yourself. |
| `game.gd:460-462` | `#TODO ... it's own game state - IN_MENU ... mouse icon changes while menu is up ... erratic behavior` | **Real, user-visible jank**, and there's still no `IN_MENU` in the `GameState` enum. Strongest *remaining* overdue item. Confirm it still repros after the June SubViewport refactor before investing. The Control-based menu rebuild (**#26**) is the natural fix — check there first. |

## 5 · Near-term polish — your call (not overdue, not far-future)

Legitimate, achievable now, nothing forcing the timing.

| Where | Idea | Routed to (2026-06-18) |
|---|---|---|
| `game.gd:357` | Close button on the unit info panel (today it's right-click-only; the panel has no button). | **#43** (new) |
| `game.gd:368` | Order the action-menu items explicitly instead of by append order. | **#26** (menu revamp) |
| `game.gd:404` | Split "cancel everything" vs. "cancel just queued plans." | **#26** — further-future option |
| `game.gd:878` | Colour-code the squad-target cursor (valid/invalid) — `CursorState.VALID/INVALID` already exist, so this is cheap. | **#44** (visual clarity umbrella) |
| `Classes/units/UnitFactory.gd:14` | Move the unit-builder functions out of `dev_overlay` into `UnitFactory`. Confirmed **not yet migrated** (`SpawnTool.build_unit_data()` still does `UnitData.new()`). | **#22** (now "slim down game.gd + SquadManager.gd") |

---

*Triaged by Claude (Opus 4.8), 2026-06-18.*
