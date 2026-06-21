# Play API — a headless interface for Claude (and the future squad AI) to play Iosis

**Status:** Draft / captured design (not locked) — 2026-06-20.
**Decisions taken** (with the user): build an **interactive headless core first**, designed so a
**watchable live bridge reuses the same core** later; **factor the move/target legality rules out of
`game.gd`** into a shared module.

## Why this exists

Let Claude actually *play matches headless* — to playtest balance, rules correctness, reachability,
and squad / counter / elemental interactions, then synthesize findings. The goal the user cares about
is **the playtest output**, not the plumbing.

This is **not new architecture.** Design **Law #3** already says *"AI issues orders exclusively
through `SquadManager.queue_action` — no side channels."* The Play API is just the concrete surface of
that contract. The future archetype AI (Milestone A) uses the *same* surface — build it once.

Feasibility is high and already proven: the gdUnit suite stands up real `Unit`s + `SquadManager`,
queues actions, and resolves them with **no grid or visuals**
([`tests/support/squad_fixtures.gd`](support/squad_fixtures.gd)). A play driver is that pattern scaled up.

## The seams this rides on (already in the code)

- **Orders** → `SquadManager.queue_action(squad, action)` with `MoveAction` / `AttackAction`
  (`AttackAction.create_volley` for AoE). The one true entry point.
- **Outcomes are pure** → `SquadManager.resolve_plan(squad)` → `PlanResolver.resolve()` reads a
  snapshot, derives counters, writes one `ResolvedOutcome` per action, **zero RNG**. Because the game
  is deterministic (Law #1), the API can *preview exact results before committing.*
- **State application separates from animation** → a move is `movement.cell`; an attack is
  `combat.apply_damage()` + element-state deltas once `.resolved` is set
  ([`AttackAction.gd:51`](../Classes/actions/AttackAction.gd)). The `await … lunge`/tween parts are
  cosmetic only — a headless executor skips them.

## Architecture: one core, swappable transports

### 1. `RulesService` — NEW gameplay module (extracted from `game.gd`)

Pure board rules, currently tangled with `game.gd`'s grid + input layer. Extract so **both `game.gd`
and the Play API call one source of truth** (protects Law #2 — "the queue never lies").

Move out of `game.gd` (≈ lines 591–808), taking a **board context** (grid + a unit-occupancy lookup)
as parameters instead of reading `game.gd` globals:

- `compute_move_range(unit, board)` → `{reachable, came_from, squad_unreachable}`
- `reconstruct_path(came_from, start, goal)`
- `movement_cost(cell, unit, board)`
- `gather_attack_victims(attacker, affected_cells, board)`

Attack *geometry* already lives in `CombatComponent` (`get_attack_cells_from`,
`get_affected_cells_from`, `can_hit_cell_from`) — reuse as-is, no extraction needed.

### 2. `PlaySession` — NEW scaffolding (transport-agnostic)

Owns the player's whole turn vocabulary, calling the **real** `SquadManager` / `TurnManager` /
`PlanResolver` / `RulesService`. No side channels. Methods compute **structured** results internally
(for `execute`, tests, and the live bridge), but the channel Claude reads is a **compact rendered text
view**, not raw JSON — see *State representation*. Command vocabulary:

| Command | Returns |
|---|---|
| `describe_state()` | full board snapshot (rendered view — see below) |
| `legal_moves(unit_id)` / `legal_targets(unit_id)` | reachable cells / hittable cells + victims |
| `squad_up / join / leave / disband` | new squad state |
| `queue_move(unit_id, dest)` / `queue_attack(unit_id, aim_cell)` | validity + updated plan |
| `cancel(unit_id)` / `wait(unit_id)` | updated plan |
| `preview()` | `resolve_plan(active_squad)` outcomes **without applying** (damage, state deltas, deaths, counters) |
| `execute()` | apply the resolved plan headlessly; return the event log |
| `end_turn()` | new turn/faction |

`preview()` is the playtesting superpower: deterministic look-ahead at exact damage/deaths before I
commit.

### 3. Transport hosts — "are 1 and 3 exclusive?" → no

- **`HeadlessHost` (now):** a `SceneTree`/`MainLoop` script run like the gdUnit runner (`-s …`), that
  builds the minimal node graph (`Grid` + `SquadManager` + `Units` + `TurnManager`, per the
  `make_manager` pattern), loads a `ScenarioData` for terrain + units, runs `PlaySession`, and drives
  the file bridge. **This is what Claude drives now.**
- **`LiveBridge` (later):** the real running game adds the *same* bridge node pointed at its live
  `SquadManager`. Same commands → Claude plays, **user watches on screen**. Option 3 for free.

## File bridge — how Claude actually drives it

A persistent headless process can't be fed stdin across separate tool calls, so the transport is a
**file handshake** (which also generalizes to the live bridge):

- A run dir holds `command.json` (Claude writes) and `state.json` (host writes).
- Claude writes `{ "id": N, "cmd": "...", "args": {...} }`.
- The host polls in `_process`, executes via `PlaySession`, and writes back the **rendered text view**
  (board + legend + affordances/result) plus a small status envelope (`last_id`, `ok`, `error`). Raw
  structured state stays available for tests, but is not the channel Claude reads.
- Claude polls the output until `last_id == N`. The monotonic `id` is the handshake — no half-reads,
  no missed responses.

**Batch mode** is the same core fed a *list* of commands at once, dumping one final trace — used
**first** to validate `PlaySession` cheaply before the interactive loop is wired.

## State representation — a rendered text view (not raw JSON)

Raw JSON is the wrong channel for the *player*: a per-tile object list is token-heavy and forces Claude
to rebuild a 2-D layout from flat coordinates (poor spatial reasoning). Instead the host renders a
**compact, spatial, affordance-rich text view**; structured data stays internal (for `execute`, tests,
the live bridge). A board is a picture made of tokens — render the picture.

**Glyphs.** One char per cell. `UPPERCASE` = player unit, `lowercase` = enemy (digits = OTHER faction
if it ever matters); each unit gets a unique letter handle used in commands. Terrain: `.` floor,
`#` unwalkable, with a small per-scenario legend (water / cover, once terrain types land). A legend
table carries what a glyph can't (name, hp, squad/leader, weapon). Unit handles are session-stable ids
assigned by `PlaySession` — units have no persistent id today.

**Layered views — pull detail only where you act** (token discipline):
- **Overview** (`describe_state`): ruled board + one-line-per-unit legend + turn / squad status. The default; small.
- **Focus** (`focus(unit)`): board re-rendered with that unit's **move range** (`+`) and **attack range** (`×`) overlaid; the unit's full stats / weapon / states; its legal actions; and (if squadded) the leader LDR range.
- **Preview** (`preview`): the **resolved** outcome of the current/hypothetical plan — exact damage, deaths, counters, net board change — as a concise diff, not a re-dump. The deterministic-engine payoff.
- **Result** (`execute`): the event log (equals the preview, by Law #2) + a fresh overview.

Micro-commands (`queue_move`, `cancel`) return a one-line ack + plan delta, **not** a full re-render —
the board is redrawn only on overview / focus / preview / result / turn-change.

**Targeting.** Commands use **game coordinates** (no rebasing — one coordinate system kills a whole bug
class). The board carries x / y rulers; exact targets are confirmed by the affordance overlay plus a
**validation envelope** — an illegal `queue_move` returns *why* (and the nearest legal option), so
mis-targets are cheap to correct.

**Mock — the current `spawn_test_units` board** (positions real; hp/weapon detail illustrative):

```
Turn: PLAYER     to act: A B C (player, solo) · a b (enemy, solo)
        x: -8 -7 -6 -5 -4 -3 -2 -1  0  1  2  3  4
 y=-5     C  .  B  .  .  .  .  A  .  .  .  .  .
 y=-4     .  .  .  .  .  .  .  .  .  .  .  .  .
  ⋮                        (open floor)
 y= 4     .  .  .  .  .  .  .  .  .  .  .  .  a
 y= 6     .  .  .  .  .  .  .  .  .  .  .  .  b

A GoodGuy1       P hp?/?  solo Chainsword[pow,STR,SHOCK,ctr]
B GoodGuy 2      P hp?/?  solo (unarmed)
C GoodGuyThree   P hp?/?  solo (unarmed)
a BadGuy1        E hp?/?  solo ChainSword
b BaddyNumeroDos E hp?/?  solo (unarmed)
```

`preview` of "A moves next to a, then attacks":

```
A move (-1,-5)->(3,4);  A attack aim (4,4)
  A -> a (BadGuy1): N dmg → dies/survives at H/M   [+SHOCK if applicable]
  counter: a -> A : C dmg  (or none, if a is dead first)
  net: <one-line board delta>
```

This is what "affordances so Claude can play properly" means concretely: I see the *shape* of the
board, the *reachable/attackable* overlay for the unit I'm moving, and the *exact resolved outcome*
before I commit — all in a few hundred tokens, not a multi-KB dump.

## Setup / fixtures

Reuse `ScenarioData` `.tres` (terrain + units + squads). **`ScenarioManager.load_scenario` can't be
used as-is headless** — it calls `game.spawn_unit` and touches `dev_overlay` / `overlay_manager`. The
`HeadlessHost` gets a small loader that mirrors the essential spawn + squad-rebuild from it, minus the
visual calls. Saved scenarios under `res://Scenarios/` become playtest fixtures.

## Build milestones (ownership)

| # | Milestone | Status | Notes |
|---|---|---|---|
| **M1** | `RulesService` extraction from `game.gd` | ✅ done (committed) | Lives in `Classes/board/`; `game.gd` delegates via wrappers; advances #22. |
| **M2** | `PlaySession` + view renderer + headless scenario loader | ✅ done 2026-06-20 | `play/{play_session,board_view,board_builder,play_host}.gd`; 3-char `[actor][terrain][overlay]` view; loads `.tres` scenarios (real Castle Assault verified). |
| **M3** | File-bridge interactive loop | ✅ done 2026-06-20 | `play/play_bridge.gd`: polls `playrun/command.json`, writes `playrun/state.txt` with a monotonic `id` handshake. Cmds: new/load/overview/focus/move/attack/cancel/preview/execute/endturn/quit. |
| **M4** | `LiveBridge` node in the real game | ⬜ next / optional | Host the same bridge inside the running game so a human can watch. |
| **tests** | `tests/play/` + `tests/rules/` | ✅ green | preview == execute (Law #2); no mutation outside `execute()`; scenario round-trip. Full suite 60+/60+, 0 orphans. |

## Limits (honest scope)

Headless **cannot** judge feel, animation timing, readability, or input UX. It **can** judge balance,
determinism/correctness, reachability/softlocks, squad/counter/elemental interactions, and scenario
win/loss. Until enemy AI exists, Claude plays **both sides** (hotseat-as-Claude) — itself a way to
pressure-test scenarios — through the exact API the archetype AI will later use.

## Open questions

- Run-dir location: `user://playruns/<id>/` vs. a `res://` path under the repo (gitignored).
- Does `PlaySession` live in `Classes/` (gameplay-adjacent) or a new `tools/`/`play/` dir?
- Per-command id transport details / timeout + error envelope.
