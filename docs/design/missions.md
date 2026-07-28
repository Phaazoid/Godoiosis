# Missions — the closed loop

**Status: ALL FOUR SLICES BUILT 2026-07-28 ([#96](https://github.com/Phaazoid/Godoiosis/issues/96)).** Filed 2026-07-27, when the project acquired a win condition for the first time. Before this, Iosis had ten interlocking systems and no way to finish a battle — which meant a design question could be answered *"is this coherent?"* but never *"does this improve play?"*

**Canon checked through #101 (2026-07-28).**

## What a mission is

A mission is a board you can **lose**. Everything else — selection, capture points, extraction, briefings, rewards — is content stacked on a loop that already closes.

The loop lives in four places, and the split is load-bearing:

| part | lives in | why there |
|---|---|---|
| **the rule** — won, lost, or ongoing? | `MissionRules` (`flow/`, static, pure) | Mirrors `LethalityRules`: one function reading a `BoardContext`, so the game, the headless Play API and the tests cannot each grow their own copy. |
| **the state** — the latches, the objective progress, the ending | `MissionController` (`flow/`, a game collaborator) | Everything a pure predicate structurally cannot hold, plus what the game *does* about an ending. |
| **what a mission requires** | `ScenarioData.objectives` | Authored content, saved with the board. |
| **where a requirement IS** | `ScenarioData.zones` (via `ZoneManager.Kind`) | Geometry. A capture point is a zone of size one. |

Plus two UI surfaces: `MissionSelectScreen` (`ui/`) is the game's front door, and `MissionEndBanner` (`ui/`) is the card at the end.

## Objectives: declared explicitly, located by zones

**Fork A was called twice, and the second call overrode the first.** The original plan was a `MissionData` resource wrapping a scenario — the *"authored mission vs. saved sandbox"* split, by analogy with `WeaponData` template-vs-instance. **That analogy was wrong** (dev, 2026-07-28): template-vs-instance exists because many instances share one template and diverge. A mission and its board are 1:1, so a wrapper is an extra hop and a pointer to keep valid, not a split. There is **one** board resource, `ScenarioData`, and there is no `MissionData`.

What a mission requires is a list on that resource:

```gdscript
@export var objectives: Array[MissionRules.Objective] = []   # empty = plain rout map
```

- **`ROUT`** — no faction hostile to the player has an active unit left.
- **`CAPTURE`** — every `ZoneManager.Kind.CAPTURE` zone claimed.
- **`EXTRACT`** — every surviving player unit inside a `Kind.EXTRACTION` zone.

Objectives **compose by AND**: every declared one must be MET. Authorable OR-composition is scope on [#101](https://github.com/Phaazoid/Godoiosis/issues/101), along with the grouping question (a flat flag can't express *"A and (B or C)"*).

An **empty list is a plain rout map**, which is what every scenario saved before objectives existed still is — that fallback is why the change broke nothing.

### Why explicit, when implicit worked

Slices 3–4 originally derived the objective from what was painted: a CAPTURE zone on the board *was* a capture objective. That was neat and it was wrong (dev, 2026-07-28), for three reasons that all showed up as soon as the question "how do I add a rout clause?" was asked:

1. **Rout has no geometry**, so an implicit-from-zones scheme cannot express it at all — rout could only ever be the fallback, never a clause alongside a capture point.
2. **A mis-picked Zone Kind silently rewrote the win condition.** A patrol zone typo'd as CAPTURE turned a rout map into a capture map with no diagnostic.
3. **No decorative or optional zones** — painting was load-bearing, so geometry could never be authored ahead of the rule that uses it.

Zones now supply **geometry only**. The cost is a second source of truth, which is what the guard below exists to close.

### The guard: declared without painted

An objective ticked with no matching zone painted can never be met — the mission is unwinnable. Two things catch it:

- **Authoring time.** The dev Scenario tab's objective checkboxes render a live warning naming every declared-but-unpainted objective. This is the one that matters; it is cheaper than finding out mid-playtest.
- **Load time.** `MissionController.set_objectives` `push_error`s once per missing objective.

At runtime the unpainted objective reads **PENDING, not NONE** — deliberately. The map really is unwinnable, and silently dropping the objective would quietly convert a broken map into a *different, playable* one, which is a far worse failure than a loud one.

## `MissionRules.Progress` vs `MissionRules.Objective`

Two enums that are easy to confuse, so: **`Objective`** is *what is required* (ROUT/CAPTURE/EXTRACT), **`Progress`** is *how far along the mission's requirements are as a whole* (NONE/PENDING/MET). `Progress` was called `Objective` in slice 1 and was renamed when real objectives arrived.

`NONE` is not `PENDING`. Conflating them is exactly how "this scenario has no objective" becomes "this scenario is instantly won" — the same class of bug as the `contested` latch below.

## Doctrine

### An authored objective is the ONLY way to win

If a scenario declares objectives, routing the enemy wins nothing unless `ROUT` is one of them. The first draft had victory as `objective OR rout` — a consolation win so that killing everything while unable to reach the point couldn't softlock the map. **Overruled (dev, 2026-07-28): lockout is a level-design problem.** Maps get built so the player cannot lock themselves out; a map where they can and do should be a *loss*, which is [#101](https://github.com/Phaazoid/Godoiosis/issues/101)'s business, not a rule that hands out a win nobody earned.

### Mutual destruction is a DEFEAT

If the last player unit and the last hostile fall in the same resolution pass, the mission is **lost**. `MissionRules.evaluate` checks defeat first for exactly this reason. A wipe you don't survive is not a win — and the alternative would reward trading a whole squad for the last enemy, which is the opposite of what the Will/death ladder is for.

### `contested` — a dev scratchpad is not a mission

A board holding only enemies satisfies "the player has no active units" perfectly, and it is obviously not a defeat. The board alone cannot distinguish **wiped out** from **never here** (`present_factions` drops factions whose units are all dead, so the record of who started is gone).

So the caller latches it: `MissionRules.is_contested(board)` is true while both sides have a commandable unit, and `MissionController` remembers that it was ever true. `evaluate` is *handed* that latch rather than reading it live — a live read could never end a mission, because the moment one side is wiped the board stops being contested.

The practical effect: **dev sandbox boards stay inert.** Spawn five enemies in the Unit tab with no player units and nothing fires. No `dev_mode` flag was needed.

### Extraction counts the DOWNED

"Surviving" means **not dead**, so a downed unit *inside* an extraction zone is extracted exactly like an active one — alive and in the zone means they get out. What blocks the objective is a living unit *outside* the zone, and a downed one out there cannot walk in on its own: someone has to reach them with `RescueAction`, which revives to 1 HP and ACTIVE.

That is the whole design of the rescue-under-pressure mission. Counting only ACTIVE units would let you leave a body behind and still win (fork C: **surviving**, not starting).

### Capture is instant and uncontested

One main action, standing anywhere inside the zone, and the **whole zone** is claimed — a multi-tile objective is one objective, not N of them. Nobody takes it back (fork D). Hold-for-N-turns and enemy re-capture are a strictly bigger design that needs enemy objectives to mean anything first.

## When the rule is asked — fork E: pass-end, not turn-end

`MissionController.check()` runs at every point board state can change *and settle*:

1. **End of a resolution pass** (`OrderExecutor.execute_orders`, right after `_process_downed_pending` and *before* its squad-validity guard, so a squad that wiped itself can't skip the check) — covers damage, downs, deaths, counters, Crisis, and movement into an extraction zone.
2. **After the end-of-turn burn** (`game.end_turn`) — a burning tile can take the last unit.
3. **Turn start, after the downed clocks tick** (`game._on_turn_started`) — an expiring downed countdown kills, and that is the one death that happens outside a pass.

Turn-boundary-only evaluation would have been simpler and dishonest: **a friendly AoE can down your own last unit mid-pass**, and the game should say so at that moment rather than taking more orders for a squad that no longer exists.

`AIController.take_faction_turn` guards on `is_over()` so a squad that wipes the player stops issuing orders behind the end-of-mission card.

**Crisis needs no special case.** Crisis fires at the moment of a would-be-down and stands the unit back up ACTIVE, so `faction_has_active_units` is already correct when the pass settles. No self-revive from a *downed* state exists, which is what makes all-downed genuinely terminal.

### The infinite turn-pass this replaced

`game._on_turn_started` auto-skips a faction with no commandable units, guarded so an all-downed board can't recurse forever. That guard existed specifically to survive the exact state that *should* be a loss; the predicate was right there and nothing treated its result as an outcome. It **stays** — an uncontested sandbox board can still reach all-downed, and the guard keeps that inert rather than hung.

## Fork B: the queue does not preview the win

Law #2 says the queue never lies — it does not say the queue must surface every consequence. The lethal skull already tells you the last enemy dies; declining to *also* tag it "this wins" withholds nothing and asserts nothing false.

Capture turned out to be the cheap case to preview (a cell test against the resolved destination) and it still wasn't built — the question is now better asked alongside [#101](https://github.com/Phaazoid/Godoiosis/issues/101)'s clock, because *"this move loses"* is the version that actually matters for fairness.

## Mission start resets battle state (the #87 seam, finally executed)

The persistence seam has always said battle-scoped state resets each mission — but **nothing had ever fired a mission-start event**, so that rule had never run. `MissionController.reset()` is the first thing to do it, called from `ScenarioManager.clear_board()`.

Keep the distinction [#87](https://github.com/Phaazoid/Godoiosis/issues/87) flagged: **loading a mid-battle save restores battle state; starting a mission resets it.** Both currently route through `load_scenario`; when #87 splits them, `reset()` goes on the mission-start path only.

`clear_board()` also empties the zone store, which `load_scenario` refills — without that, the Sandbox board inherited the previous mission's zones (and therefore its objectives' geometry).

## Mission select

The game boots into `MissionSelectScreen`, not a board. `TestBoard` was retired as the boot path (dev, 2026-07-28) and is a labelled dev row on the menu; `game.spawn_sandbox()` is its one remaining call site, so retiring it entirely is still a one-line deletion.

- **Missions** are scenarios under `Scenarios/missions/` — the folder convention `Scenarios/fixtures/` already set. `save_scenario` already creates directories, so saving a scenario named `missions/Camp` needs no new code.
- **Scenarios & fixtures** (everything outside `missions/`) are listed below the missions and are selectable — during development these *are* the content.
- A board arriving from the menu has nobody's turn *started* (`load_scenario` only restores whose turn it *was*), so `MissionController._begin_turn` fires the banner and `start_faction_turn`. Without it a mission saved on an AI faction's turn would sit there doing nothing, because `turn_started` only ever fires from `TurnManager.end_turn`.

The end-of-mission banner offers **Retry** (hidden when the board wasn't loaded from disk), **Mission Select**, and **Stay** — which unlocks the finished board for inspection with the dev tools while leaving the mission over and the turn cycle stopped.

## The AI and CAPTURE

`CAPTURE` sits in `AIArchetype.MAIN_ACTION_NEVER` for all three archetypes, and `tests/law/test_ai_action_coverage.gd` forced that to be an explicit decision.

**This is not the Rev/Burrow drift.** There is nothing for an AI faction to *win* by capturing, because enemy objectives are out of #96's scope — the point is the player's. The AI contests it positionally, which it already does: Rushdown walks into the approach, and a Sentry squad zoned over the point defends it with no AI code at all. Revisit when non-player factions get objectives of their own, which is [#101](https://github.com/Phaazoid/Godoiosis/issues/101)'s "defend a point".

## Known gaps

- **The Play API cannot see authored objectives.** `play_session.mission_outcome()` calls the same `MissionRules.evaluate`, but with no `MissionController` it always passes `Progress.NONE` — so headless runs evaluate every board as a rout map, and there is no `capture` command to queue. Headless coverage of the loop stops at rout/defeat.
- **`MissionController` itself is untested.** `MissionRules` and `ZoneManager` are well covered (`tests/flow/test_mission_rules.gd`, `tests/ai/test_zone_manager.gd`); the latches, the objective composer, the banner and the six call sites are not, because they need the game scene, which segfaults inside the runner.
- **No mission-status UI.** Nothing on screen says what the objectives are or how far along they are — you find out by winning. This is the prerequisite [#101](https://github.com/Phaazoid/Godoiosis/issues/101) fork D names, and a turn clock will force it.
- **`CaptureAction`'s icon is a placeholder** (the board target marker).

## Not in scope for #96

Campaign layer (mission ordering, unlocks, roster carried between missions, between-battle recovery) · objectives for non-player factions · story/briefing framing, rewards, acquisition · **lose conditions beyond the last unit falling → [#101](https://github.com/Phaazoid/Godoiosis/issues/101)**.

## What this unblocks

- [#70](https://github.com/Phaazoid/Godoiosis/issues/70) — between-missions-only job swap, blocked purely because no mission-boundary concept existed (`set_main_job`/`set_sub_job` carry a `TODO(campaign layer)`).
- [#87](https://github.com/Phaazoid/Godoiosis/issues/87) — the mid-battle-save split above.
- [#101](https://github.com/Phaazoid/Godoiosis/issues/101) — lose conditions, which reuse `check()`, the objectives list, and `ZoneManager.Kind` wholesale.

Cross-refs: [level-concepts.md](level-concepts.md) (the set-piece pool missions will draw from), [will-and-death.md](will-and-death.md) (why all-downed is terminal, and why extraction counts the downed), [ai-tactics.md](ai-tactics.md), [resolution-pipeline.md](resolution-pipeline.md) (the persistence seam).
