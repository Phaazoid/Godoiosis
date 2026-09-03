# Missions — the closed loop

**Status: ALL FOUR SLICES BUILT 2026-07-28 ([#96](https://github.com/Phaazoid/Godoiosis/issues/96)).** Filed 2026-07-27, when the project acquired a win condition for the first time. Before this, Iosis had ten interlocking systems and no way to finish a battle — which meant a design question could be answered *"is this coherent?"* but never *"does this improve play?"*

**Canon checked through #572 (2026-08-26).**

## What a mission is

A mission is a board you can **lose**. Everything else — selection, capture points, extraction, briefings, rewards — is content stacked on a loop that already closes.

The loop lives in four places, and the split is load-bearing:

| part | lives in | why there |
|---|---|---|
| **the rule** — won, lost, or ongoing? | `MissionRules` (`flow/`, static, pure) | Mirrors `LethalityRules`: one function reading a `BoardContext`, so the game, the headless Play API and the tests cannot each grow their own copy. |
| **the state** — the latches, the objective progress, the ending | `MissionController` (`flow/`, a game collaborator) | Everything a pure predicate structurally cannot hold, plus what the game *does* about an ending. |
| **what a mission requires** | `ScenarioData.objectives` | Authored content, saved with the board. |
| **where a requirement IS** | `ScenarioData.zones` (via `ZoneManager.Kind`) | Geometry. A capture point is a zone of size one. |
| **who the computer plays** | `ScenarioData.ai_factions` (#150) | Authored content, saved with the board — same shelf as `objectives`. Commanding is hotseat-gated, so a mission that declares nobody hands the player both sides rather than stalling — **which is a board the dev authors on purpose** (2026-08-26: *"controlling both sides is important to testing"*), so `BoardLint` warns about it and never refuses it. |
| **what it LOOKS like** | `ScenarioData.look_preset` (#253 part 2) | A preset NAME, not a `LookPreset` reference — a dangling `ext_resource` can fail the whole load rather than degrade, and a Resource field risks embedding the preset on save (#177's trap). Empty, or a name that no longer resolves, falls back to `Resources/DefaultLook.tres`, loudly — which the Moods tab can itself rewrite since #386, so "what an unnamed board wears" is authored rather than only editable by hand. `battle3d` applies it off `board_loaded`; a flat 2D launch has no host and applies nothing. |

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

Objectives **compose by AND**: every declared one must be MET. Authorable OR-composition is **unfiled scope** — it was #101's fork F and outlived that issue's close; see *What #101 did NOT ship* below for the grouping question (a flat flag can't express *"A and (B or C)"*).

An **empty list is a plain rout map**, which is what every scenario saved before objectives existed still is — that fallback is why the change broke nothing.

### Why explicit, when implicit worked

Slices 3–4 originally derived the objective from what was painted: a CAPTURE zone on the board *was* a capture objective. That was neat and it was wrong (dev, 2026-07-28), for three reasons that all showed up as soon as the question "how do I add a rout clause?" was asked:

1. **Rout has no geometry**, so an implicit-from-zones scheme cannot express it at all — rout could only ever be the fallback, never a clause alongside a capture point.
2. **A mis-picked Zone Kind silently rewrote the win condition.** A patrol zone typo'd as CAPTURE turned a rout map into a capture map with no diagnostic.
3. **No decorative or optional zones** — painting was load-bearing, so geometry could never be authored ahead of the rule that uses it.

Zones now supply **geometry only**. The cost is a second source of truth, which is what the guard below exists to close.

### Zones overlap, and a zone's kind locks at creation (2026-08-12)

Two authoring rules replaced the original one-zone-per-cell store: **zones overlap freely** — the motivating case is a patrol area containing a capture point — and **a zone's kind is fixed when its first cell is painted** (repainting never retypes; changing kind = delete and repaint, which closes the trap where continuing to paint under an existing name with a different Kind picked silently converted the whole zone). Consequences: "the zone at this cell" stopped being a well-formed question — the kind-sensitive reader is `MissionController.capturable_zone_at(cell)` (the uncaptured CAPTURE zone there, which the menu gate and `CaptureAction`'s stamp both read) — and brush erase is **scoped to the picked zone**, since an unscoped erase could never carve one zone out from under another. Where two capture zones overlap, claiming one leaves the other capturable from the shared cell.

### The guard: declared without painted

An objective ticked with no matching zone painted can never be met — the mission is unwinnable. Three things catch it, all reading the one rule (`MissionController.objectives_missing_geometry`):

- **Authoring time.** The dev Scenario tab's objective checkboxes render a live warning naming every declared-but-unpainted objective. This is the one that matters; it is cheaper than finding out mid-playtest.
- **On demand.** Scenario ▸ Properties ▸ **Check board** ([#390](https://github.com/Phaazoid/Godoiosis/issues/390)) reports it alongside the board's other authoring faults, and CI runs the same pass over every shipped mission.
- **Load time.** `MissionController.set_objectives` `push_error`s once per missing objective.

At runtime the unpainted objective reads **PENDING, not NONE** — deliberately. The map really is unwinnable, and silently dropping the objective would quietly convert a broken map into a *different, playable* one, which is a far worse failure than a loud one.

## Losing on purpose: the lose-condition list and the turn clock ([#101](https://github.com/Phaazoid/Godoiosis/issues/101), 2026-08-26)

#96 gave the game exactly one way to lose: the player has no active unit left. That is the floor, not the design — every interesting mission fails in a way that is *not* "everyone died". **The asymmetry is the point: win conditions are things the player DOES, lose conditions are things they fail to PREVENT**, and they are what make a map exert pressure. A capture point with no clock is a puzzle you solve at leisure.

**Fork A was called their own list** (dev, 2026-08-26), not negated objectives:

```gdscript
@export var lose_conditions: Array[MissionRules.LoseCondition] = []   # empty = only the floor
@export var round_limit := 0                                          # 0 = no limit
```

*"Protect unit X"* and *"unit X must survive"* really are the same statement, so the reason is not expressiveness — it is that the two are asked at **different moments** (an objective is checked for completion, a lose condition continuously) and that **a failure has to name a reason** for the banner, which an objective never does.

- **`SQUAD_LOST`** — the #96 floor. Always on, never authored.
- **`ROUND_LIMIT`** — the objectives were not met within `round_limit` rounds.
- **`NONE`** is a sentinel meaning *nothing fired*, not a condition.

**Lose conditions compose by ANY**, stated rather than inherited from a loop's shape: the first one that fires ends the mission. Losses are rarely conjunctive.

**`MissionRules.AUTHORABLE` is what the Scenario tab offers**, and it is a const rather than "every enum value" — so the sentinel and the always-on floor are excluded by a *decision* that a reader can see, the same way `CAPTURE` sits explicitly in `AIArchetype.MAIN_ACTION_NEVER`.

### The order two conditions are asked in

`evaluate` takes `failure` exactly as it already takes `progress` — `MissionController` computes it, the rule stays pure — and the order is load-bearing at both ends:

1. **The squad wipe is asked FIRST**, so mutual destruction is still a DEFEAT (unchanged doctrine) and a squad lost on the round the clock expires reports **SQUAD_LOST**, the more concrete thing that happened.
2. **Every VICTORY path is asked BEFORE an authored failure.** Finishing on the last allowed round is finishing *in time*; a clock must not steal a win the player earned.

`MissionController.failure_for` names the reason and `evaluate` decides the outcome. Both read the one `faction_has_active_units` predicate — `evaluate` keeps its own wipe branch because callers that pass no failure (the headless Play API) still need it.

### Where the clock lives — fork B

**The count is battle-scoped, the limit is authored**, the same split objectives already have: `MissionController._rounds_elapsed` (cleared by `reset()`, saved with the #87 snapshot) against `ScenarioData.round_limit`. A **round**, not a turn: the cycle is N-faction and rebuilt from the board each hand-off, so a round is the only stable unit.

**There is ONE increment point**, `game._on_round_completed`, beside the terrain tick. `TurnManager` emits `round_completed` before `turn_started`, so the very next `check()` — turn start, after the downed clocks tick — is the one that sees it. **No new evaluation seam was added**; fork E's three points still are the three points.

`round_limit = 0` means **no limit**, and that sentinel *is* the field's own default, so a board that never authored a clock cannot read as one that authored a zero-round one. A declared `ROUND_LIMIT` with no limit is the **unpainted-geometry guard's twin**: `MissionController.lose_conditions_missing_setup` is the one rule, read live by the Scenario tab, shouted once by `set_lose_conditions`, and reported as BLOCKS by `BoardLint`. It reads as broken and says so — it does not fire, and it is not silently dropped.

### What the player sees — forks C and D

Fork D's prerequisite was already built: [#134](https://github.com/Phaazoid/Godoiosis/issues/134)'s `MissionStatusPanel`. The clock is a row on it under its own **FAIL IF** header — a countdown listed among the objectives reads as something to achieve — and it is built off the declared list, so the next condition needs no panel edit.

**One bug this surfaced, worth knowing because it is the shape a HUD gate always has:** `game.refresh_mission_status` hid the whole panel on `objectives.is_empty()`. A mission authoring a clock and *no* objectives therefore rendered no countdown at all — precisely the unplayable state fork C exists to prevent. The gate asks about lose conditions too now.

**Fork C was called: colour the clock as it runs out, no modal** (dev, 2026-08-26). The threshold is a feel value, so it ships as a knob rather than a guess — `MissionStatusPanel.URGENT_ROUNDS` / `URGENT_COLOR`, two `GameKnobs.CLASS_KNOBS` rows under a **Mission** sub-tab. They are class rows and not property rows for a structural reason worth recording: `KNOBS` resolves node paths against the **Battle3D host**, and the status panel is 2D UI under the game's own `ui_layer`, so the node table structurally cannot reach it. Both rows re-apply through `game.refresh_mission_status` when written, or the slider would move nothing until the next turn — which is exactly when it is being dragged (#324's rule).

The **banner names the reason**: `MissionRules.defeat_reason` is the one place the wording lives, so the card holds no second copy of *"Your squad has fallen."*

### What #101 did NOT ship

**#101 is CLOSED** (dev, 2026-08-26): with the seam built, the rest of it was three unrelated features sharing one design capture, so they were split out and it closed rather than becoming an umbrella. That number is history now — the successors are:

- **[#571](https://github.com/Phaazoid/Godoiosis/issues/571) — defend a point.** An enemy taking a friendly zone. The first non-player-faction objective, and what *The AI and CAPTURE* below is waiting on. Its real cost is not the condition: **a captured zone has no OWNER** (`_captured_zones: Array[String]`, and `CaptureAction.execute` discards its own actor), so "captured" is a per-zone boolean that only works while the player is the only faction that can claim one.
- **[#572](https://github.com/Phaazoid/Godoiosis/issues/572) — protect a unit.** Escort and VIP. Same shape: the rule is nearly free on this seam, and the gap is that **`ScenarioUnitEntry` has no stable identity field**, so a mission has nothing to point at when it names a person.
- **Authorable OR-composition (fork F)** — grouped OR-lists inside an AND, so a mission can be won by *either* taking the point *or* routing. **Not filed**, deliberately: the lean was always *arriving only when a real mission design wants it*, and this section is the record until one does. A flat `require_all` flag is the version to avoid — it cannot express *"A and (B or C)"* and gets outgrown.

The Play API's blindness to all of this went to **[#46](https://github.com/Phaazoid/Godoiosis/issues/46)**, the Play API evergreen, rather than becoming a fourth issue.

Previewing *"this move loses"* in the queue is still fork B's question, now that the clock it was parked against exists.

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

**Zero surviving players reads PENDING, not MET (2026-08-12)** — the `counts.y == 0` twin of capture's unpainted-geometry guard. Without it `0 == 0` counted as everyone-extracted, which ticked Extract on the HUD during load (`set_objectives` refreshes the HUD before units spawn; `apply_scenario` now re-pushes the HUD once the board is fully built). For `evaluate()` the guard never decides anything — DEFEAT is checked first.

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

Capture turned out to be the cheap case to preview (a cell test against the resolved destination) and it still wasn't built — the question is better asked alongside [#101](https://github.com/Phaazoid/Godoiosis/issues/101)'s clock, because *"this move loses"* is the version that actually matters for fairness. **That clock now exists (2026-08-26) and the question is still open**: fork C shipped the countdown plus a colour cue as the whole warning, deliberately short of previewing a losing move.

## Mission start resets battle state (the #87 seam, finally executed)

The persistence seam has always said battle-scoped state resets each mission — but **nothing had ever fired a mission-start event**, so that rule had never run. `MissionController.reset()` is the first thing to do it, called from `ScenarioManager.clear_board()`.

**Resolved by [#87](https://github.com/Phaazoid/Godoiosis/issues/87) (2026-07-30), and the answer was NOT a flag on the load.** A scenario file *is* its board, so a load restores whatever the file recorded, and an authored mission simply recorded nothing — `reset()` runs first (via `clear_board()`), then `MissionController.restore_progress()` writes a mid-battle snapshot's captured zones, `contested` latch and round count (#101) back over the blank slate. `outcome` is deliberately not saved: it is derived from those plus the board, so the next `check()` re-reaches it.

The reset side stays real for the path that does not exist yet — the future roster → board flow, where units arrive off a persistent roster carrying no battle state *by construction*, because every battle-scoped field lives on the transient `Unit` or on a non-`@export` `WeaponInstance` var. *(Its character-file half is real since [#177](https://github.com/Phaazoid/Godoiosis/issues/177): the cast lives in `Resources/Units/` and an authored mission re-reads those files on every load. What is still future is results carrying **between** missions — and the mission-boundary concept that needs is [#70](https://github.com/Phaazoid/Godoiosis/issues/70)'s debt, not a roster feature.)*

`clear_board()` also empties the zone store, which `load_scenario` refills — without that, the Sandbox board inherited the previous mission's zones (and therefore its objectives' geometry).

## Mission select

The game boots into `MissionSelectScreen`, not a board. `TestBoard` was retired as the boot path (dev, 2026-07-28) and is a labelled dev row on the menu; `game.spawn_sandbox()` is its one remaining call site, so retiring it entirely is still a one-line deletion.

- **Missions** are scenarios under `Scenarios/missions/` — the folder convention `Scenarios/fixtures/` already set. `save_scenario` already creates directories, so saving a scenario named `missions/Camp` needs no new code.
- **Scenarios & fixtures** (everything outside `missions/`) are listed below the missions and are selectable — during development these *are* the content.
- A board arriving from the menu has nobody's turn *started* (`load_scenario` only restores whose turn it *was*), so `MissionController._begin_turn` fires the banner and `start_faction_turn`. Without it a mission saved on an AI faction's turn would sit there doing nothing, because `turn_started` only ever fires from `TurnManager.end_turn`.
- **A turn HANDOFF resets actions; a menu arrival trusts the file ([#144](https://github.com/Phaazoid/Godoiosis/issues/144)).** `reset_faction_actions` fires from `game._on_turn_started`, not from `start_faction_turn` — the menu paths call the latter, and a resumed save's restored `Squad.has_acted` must survive the arrival. It lived inside `start_faction_turn` until #144, which meant every menu-driven load silently handed acted squads their actions back; nobody saw it because only the dev-overlay Load (which skips `_begin_turn`) had ever loaded a mid-battle snapshot. Pinned both directions by `tests/flow/test_turn_handoff_reset.gd`.

## Player save slots (#144)

The [#87](https://github.com/Phaazoid/Godoiosis/issues/87) snapshot got its player doors on 2026-08-11: **Save Game** / **Load Game** rows on the pause menu, and a **Load Game** row on the title screen (shown only when a slot is filled). Three fixed slots at `user://saves/slot_N.tres` — `user://` because `res://` is read-only once exported, and anything under `Scenarios/` becomes a selectable board via the folder scan and #9's suite (the `BugReporter` precedent, and the same pin shape guards it in `tests/flow/test_save_slots.gd`).

- A slot is a `SaveGame` resource: the full `ScenarioData` snapshot (**`authored = false`** — the #177 reference mode records nothing for cast units, which is exactly wrong for resume) plus `mission_path`, `saved_at`, and `Build.version()`.
- **Resume aims `last_loaded_path` at the ORIGIN mission**, so Restart and F2 return to the mission start and no dev tool can ever point Update at a slot.
- Save rides Restart's gate (missions only — a sandbox save would have no origin). Whole-campaign saving (mission-to-mission carryover) is deliberately out of scope here; it needs [#70](https://github.com/Phaazoid/Godoiosis/issues/70)'s mission boundary and is filed separately.
- The queued action plan is still deliberately unsaved (#87's exclusion); the save screen says so to the player.
- The UI is `SaveLoadScreen` (one card, SAVE/LOAD modes) + `ConfirmCard` (the player-facing, in-viewport twin of `DevWidgets.confirm_delete`) for overwrite and lost-progress confirms.

The end-of-mission banner offers **Retry** (hidden when the board wasn't loaded from disk), **Mission Select**, and **Stay** — which unlocks the finished board for inspection with the dev tools while leaving the mission over and the turn cycle stopped.

## The AI and CAPTURE

`CAPTURE` sits in `AIArchetype.MAIN_ACTION_NEVER` for all three archetypes, and `tests/law/test_ai_action_coverage.gd` forced that to be an explicit decision.

**This is not the Burrow-style drift** (Rev shipped for Rushdown 2026-08-06; Burrow followed in
[#726](https://github.com/Phaazoid/Godoiosis/issues/726), 2026-09-03 — the drift is closed, and
the example is now historical). There is nothing for an AI faction
to *win* by capturing, because enemy objectives are out of #96's scope — the point is the player's. The AI contests it positionally, which it already does: Rushdown walks into the approach, and a Sentry squad zoned over the point defends it with no AI code at all. Revisit when non-player factions get objectives of their own, which is [#571](https://github.com/Phaazoid/Godoiosis/issues/571), *defend a point*.

## Known gaps

- **The Play API cannot see authored objectives, and now cannot see lose conditions either.** `play_session.mission_outcome()` calls the same `MissionRules.evaluate`, but with no `MissionController` it passes `Progress.NONE` and no `failure` — so headless runs evaluate every board as a rout map with no clock, and there is no `capture` command to queue. Headless coverage of the loop stops at rout/defeat. The clock is precisely the kind of rule headless play is good at pressure-testing, so this is worth closing before the conditions with geometry land. **Tracked on [#46](https://github.com/Phaazoid/Godoiosis/issues/46)**, the Play API evergreen — it is a headless-interface gap rather than a mission one, and it already had a home.
- **The end-of-mission banner's three choices are untested.** `_end_mission` awaits `MissionEndBanner.show_banner`, and a button press cannot be given headlessly, so RETRY (reload + re-begin the turn), MISSION_SELECT (back to the front door) and STAY (unlock the board, mission stays over) are verified only in play. Coverage stops at the board reaching `MISSION_OVER` with input locked. *(The rest of `MissionController` IS covered as of 2026-07-29 — `tests/flow/test_mission_controller.gd`, 31 cases on a real game scene, pinning both latches, AND-composition, whole-zone capture, extraction counting the downed, declared-but-unpainted reading PENDING, and DEFEAT beating a met objective in the same pass; falsified against seven mutations, each caught by its own test. The "game scene segfaults in the runner" belief that had blocked this was false — see [#114](https://github.com/Phaazoid/Godoiosis/issues/114).)*
- ~~**No mission-status UI.**~~ BUILT [#134](https://github.com/Phaazoid/Godoiosis/issues/134) (2026-08-11) — `MissionStatusPanel` shows every declared objective and its live progress. The prerequisite [#101](https://github.com/Phaazoid/Godoiosis/issues/101) fork D named is now in place.
- **`CaptureAction`'s icon is a placeholder** (the board target marker).

## Not in scope for #96

Campaign layer (mission ordering, unlocks, roster carried between missions, between-battle recovery) · objectives for non-player factions · story/briefing framing, rewards, acquisition · ~~**lose conditions beyond the last unit falling**~~ — the SEAM and the turn clock landed as [#101](https://github.com/Phaazoid/Godoiosis/issues/101) (2026-08-26, see *Losing on purpose* above); defend-a-point is [#571](https://github.com/Phaazoid/Godoiosis/issues/571) and protect-a-unit [#572](https://github.com/Phaazoid/Godoiosis/issues/572).

## What this unblocks

- [#70](https://github.com/Phaazoid/Godoiosis/issues/70) — between-missions-only job swap, blocked purely because no mission-boundary concept existed (`set_main_job`/`set_sub_job` carry a `TODO(campaign layer)`).
- [#87](https://github.com/Phaazoid/Godoiosis/issues/87) — the mid-battle-save split above. **BUILT 2026-07-30**; `restore_progress()` is the restore half, and `ScenarioData` now carries the captured zones, the `contested` latch and the round count (#101).
- ~~[#101](https://github.com/Phaazoid/Godoiosis/issues/101) — lose conditions.~~ **BUILT and CLOSED 2026-08-26** (see *Losing on purpose* above); it did reuse `check()` and the objectives list wholesale, exactly as predicted. Its unbuilt half became [#571](https://github.com/Phaazoid/Godoiosis/issues/571) and [#572](https://github.com/Phaazoid/Godoiosis/issues/572).

Cross-refs: [level-concepts.md](level-concepts.md) (the set-piece pool missions will draw from), [will-and-death.md](will-and-death.md) (why all-downed is terminal, and why extraction counts the downed), [ai-tactics.md](ai-tactics.md), [resolution-pipeline.md](resolution-pipeline.md) (the persistence seam).
