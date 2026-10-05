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
- `gather_attack_victims(attacker, affected_cells, board, attack)` — `attack` since #102; friendly-fire is read off it, never off the attacker's live pick

Attack *geometry* already lives in `Reach` (`get_attack_cells_from`,
`get_affected_cells_from`, `can_hit_cell_from`) — reuse as-is, no extraction needed.

### 2. `PlaySession` — NEW scaffolding (transport-agnostic)

Owns the player's whole turn vocabulary, calling the **real** `SquadManager` / `TurnManager` /
`PlanResolver` / `RulesService`. No side channels. Methods compute **structured** results internally
(for `execute`, tests, and the live bridge), but the channel Claude reads is a **compact rendered text
view**, not raw JSON — see *State representation*. Command vocabulary:

| Command | Returns |
|---|---|
| `describe_state()` | full board snapshot (rendered view — see below) |
| `legal_moves(unit_id)` / `legal_targets(unit_id, attack?)` | reachable cells / hittable cells + victims, the latter for the NAMED attack (else the default) and saying which. **Each calls the predicate its own gate calls** — `compute_move_range` for moves, `can_hit_cell_from` + `gather_attack_victims` for aims — so a cell offered can never be one the queue refuses. A second derivation here would be Law #4 with a silent failure mode, and `tests/play/test_affordances.gd` drives both sides to keep them honest. Named a WATCH attack, `legal_targets` answers where the watch may be set (overwatch's own `Reach.can_aim_at` gate), each spot with the cells it would watch and the hostiles standing in them now, who it fires on the moment it is armed (#46). An aim that hits nobody but lands on the map says "only the ground", and a directional aim is labelled by its facing (N/E/S/W), printed once per facing with a count of the cells that aim the same way |
| `status()` | whose turn, which squad holds the activation and what it has queued, which squads are spent. Rides every frame rather than being asked for. A squad is named `sq` + its leader's handle (#46): it was the squad's index in the manager's list, which renumbered every squad behind one that was destroyed |
| `squad_up / join / leave / disband` | new squad state |
| `queue_move(unit_id, dest)` / `queue_attack(unit_id, aim_cell, attack?)` | validity + updated plan. `attack` names which attack fires — see *Choosing an attack* below. A squad LEADER's move that would leave a squadmate unable to follow is refused, naming who, as the game's move mode greys it (#46); `legal_moves` reports those cells under `stranding` rather than offering them |
| `group_move(unit, x, y)` | the game's Group Move (#46): the leader's destination, and `queue_group_move` places the whole formation. Every gate is asked BEFORE the squad's queued moves are cancelled, so a refused formation leaves the plan as it was |
| `overwatch(unit_id, aim_cell, attack?)` | stand watch with the NAMED watch attack, else the unit's first (a weapon normally carries one). A facing that watches no cell with a surface, off the board's edge or only over a hole, is refused and is not offered by `legal_targets` (#1228) |
| `deploy(unit, cell)` / `undeploy(unit)` / `reposition(unit, cell)` / `begin()` | the PRE-MISSION phase (#46) -- see *Pre-mission* below |
| `give(from, slot, to)` / `job(unit, job)` / `fit(unit, slot, mod, space)` / `unfit(unit, slot, mod)` / `kit(unit)` | the pre-mission loadout: gear, jobs and mods, and the view that reads them back (#46) -- see *Pre-mission* below |
| `equip / wear / use / toss (unit, slot)` / `unequip / remove_armor (unit)` | the inspect dock's verbs, in either phase (#46) -- see *The inspect dock* below |
| `rescue / reload / rev / burrow / guard / capture` | the side-channel main actions, one verb each — the argument-taking ones (`rescue(a, b, x?, y?)`, `guard(a, ward)`) stay separate from the argument-free ones for the reason `game.queue_simple_action` does. Each gates on the same `RulesService` query the menu's row is built from. A rescue may name the bank to haul the body to (`x`/`y`, checked against `RulesService.rescue_landings`); without one it takes the first, and the reply lists the others. `capture(unit)` queues the real `CaptureAction` for the zone under the unit's projected cell, refused in that action's own words (#46) |
| `ranges(unit?)` | the game's enemy-ranges view (the V key, #46): where the enemy can stand and where it can strike, through the same `ThreatField.for_viewer` the game builds its field with, and for every one of your units at its PLANNED cell, who can hit it. `unit` narrows it to one enemy. The viewer is whoever's turn it is; the game always draws the player's, which differs only in hotseat |
| `cancel(unit_id)` / `wait(unit_id)` | updated plan |
| `preview()` | `resolve_plan(active_squad)` outcomes **without applying**, as the game's queue panel shows them (#46): `rows` walks `ActionQueueDisplayEntry.build_for`, the panel's own sections and nesting (a watch shot under the walk or the order that set it off, a payload under its hit, a sinking under what melted the ice, END OF TURN last), each row by handle with the HP readout the panel prints; `terrain` is what the pass leaves on the ground, `ResolvedPlan.pending_deposits`, which the board ghosts. The rendered text prints only those two, so it hides what the panel hides (a skipped counter or watch shot); the structured `attacks` / `counters` / `side_actions` / `tile_hits` / `sinks` keys still carry everything |
| `execute()` | apply the resolved plan headlessly, through the game's own state steps (#46 — see *Headless executes a pass the way the game does* below); return the event log — plus a `mission` key the pass that ends the mission (#96) |
| `end_turn()` | new turn/faction, through the whole turn boundary the game runs (the burn, the round's tile tick, the turn-start ticks — see *The turn boundary* below); refuses once the mission is over |
| `mission_outcome()` / `mission_tag()` | won / lost / ongoing — the session's own `MissionState`, the object the game's `MissionController` holds (#46): every objective, the clock and every lose condition, with the ending latched on the first answer that is not ongoing |

`preview()` is the playtesting superpower: deterministic look-ahead at exact damage/deaths before I
commit.

**Choosing an attack (#615).** `attack`, `overwatch` and `legal_targets` take an optional
`"attack": "<name>"`, the attack's `display_name` as the unit line lists it; omitted, they use the
default (a weapon's main, a rune's first carving) and the first watch. A name is looked up in the
list its verb fires from — `Unit.fire_attack_named` / `Unit.watch_attack_named`, the same lookup the
replay viewer uses — so a watch-only attack cannot be fired and a fire attack cannot stand watch
(#590). The pick is armed for that one command and cleared after, the way the menu's aiming mode
clears it, so a later unnamed `attack` fires the default again. An attack that cannot fire right now
is refused in `attack_block_reason`'s words, the reason the menu greys its row with. The preview and
`legal_targets` name the attack they answer for.

```bash
play/send.sh attack '{"unit":"A","x":23,"y":15,"attack":"Splash"}'
```

**Refusals name their reason (#662).** The order verbs (`move`, `attack`, `overwatch`, `rescue`,
`guard`, `reload`, `rev`, `burrow`) are refused in the words of the gate that refused them, through
`SquadManager.try_queue_action`, the one order chokepoint the game, the AI and the replay viewer use.
So a move after a queued main action says so, rather than blaming another squad. **One squad plans
at a time**, as in the game: while one squad holds orders, ordering another squad's unit is refused
until those orders are executed or cancelled.

**Pre-mission (#46).** Loading a mission that names a Roster opens the same pre-mission phase the
game opens, unless the mission's *Pre-mission screen* box is unticked: then its roster's authored
draw stands, `load` says so, and the battle has begun (`PreMissionPhase.opens`, the rule both hosts
ask). Otherwise: the whole roster is drawn, as many as the cap allows stand on the DEPLOYMENT zone (the
authored walk), and the rest wait in reserve with handles of their own. The overview shows
`deployed N/cap`, the open cells, the reserve, and the zone as `D`; the status line leads with
`phase=PRE_MISSION`. Until `begin`, every battle verb refuses ("the mission has not begun") and a
reserve unit takes no squad or battle verb. `deploy` / `undeploy` / `reposition` / `begin` judge
through the rules the loadout screen uses, refusing in its words -- they are ONE implementation,
`PreMissionPhase`, which the game drives with `game.gd` as its host and the Play API with
`PlaySession` (`tests/flow/test_pre_mission_two_hosts.gd` holds the two to one answer). `load` with
`"resume": true` skips the draw, for a mid-battle snapshot whose `roster` would otherwise stand a
second force on top of the saved one.

```bash
play/send.sh load '{"path":"res://Scenarios/missions/Level_1.tres"}'
play/send.sh --batch '[{"cmd":"undeploy","args":{"unit":"C"}},{"cmd":"deploy","args":{"unit":"F","x":29,"y":3}},{"cmd":"begin"}]'
```

**The loadout (#46 slice 2a).** The screen's writes, each through the door the screen calls, and
each refused in its words:
- `give {from, slot, to}` moves gear through `Loadout.move`; `"stash"` names the stash at either end.
- `job {unit, job}` picks a job by id (`""` for none) through `Loadout.set_job`, from the mission's
  offer plus whatever the unit already holds -- the list the card's picker shows.
- `fit {unit, slot, mod, space}` / `unfit {unit, slot, mod}` fit and remove weapon mods. The mod is
  named by its catalogue key and must be in the fitting card's own library
  (`WeaponModCatalog.offerable_for` with the mission's pool, where an empty pool offers none since
  #1222); every refusal is
  `WeaponInstance.fit_block_reason`'s. `unit` may be `"stash"` for a stash weapon.

`slot` counts from 0, as the recorded gear `index` does; `space` counts from 1, as every
`fit_block_reason` sentence does. A unit's six slots are fixed, but the stash is a list, as on the
screen: when a piece leaves it, everything after moves up one, so re-read `kit stash` before the
next stash `slot`. All four are pre-mission only (fitting is read-only in battle,
#1152) and take any roster unit, deployed or in reserve, as the screen's cards do.

`kit {unit}` reads it back: each slot with `(E)` / `(W)`, why this unit cannot use a piece, each
weapon's spaces (`1 [1/2: Line Sniper]`, `off` past the wielder's proficiency), and while the phase
is open the offered jobs and mods. `kit stash` lists the stash.

```bash
play/send.sh --batch '[{"cmd":"kit","args":{"unit":"stash"}},{"cmd":"give","args":{"from":"stash","slot":0,"to":"A"}},{"cmd":"kit","args":{"unit":"A"}}]'
```

**The inspect dock (#46 slice 2b).** The dock's six buttons, named as a run records them:
`equip`, `wear`, `use` (a vial) and `toss` take `{unit, slot}`; `unequip` and `remove_armor` take
`{unit}`, being about the unit rather than a slot. They work in **either phase**, as the dock does.
Each goes through `GearVerbs`, the one rule the dock's buttons and the replay viewer ask, and refuses
in the gate's own words (`can_equip_reason`, `use_block_reason`, `remove_block_reason`).

Who may use it is `game.can_control`'s rule, `RulesService.command_block_reason`: a standing unit on
the side whose turn it is. A reserve unit is refused, because the dock is reached from the board.
A change re-resolves an open plan (game.gd's `loadout_changed` wire), so with orders queued the
reply carries the preview.

```bash
play/send.sh --batch '[{"cmd":"give","args":{"from":"stash","slot":0,"to":"G"}},{"cmd":"wear","args":{"unit":"G","slot":1}},{"cmd":"kit","args":{"unit":"G"}}]'
```

**Restart keeps the loadout (#46 slice 3).** `restart` reloads the loaded mission back into its
pre-mission phase, the game's Restart (#763):
- **after `begin`**, the last loadout stands again: who stood where, the squads, and every unit's
  gear, jobs and mods, plus the stash they came out of;
- **from inside the phase** it is *Reset Loadout*: the buffer is dropped and the mission's own draw
  stands.

The buffer is what the last `begin` captured, and the bridge keeps it across boards, as the game
keeps it across a board swap. `load` replays it too when it was taken on the same mission, as
re-entering a mission from the title does in the game, and the reply says so. Which buffer a load
replays and what a restart leaves of it are `PreMissionPhase.replay_for` and `kept_by_restart`, the
two rules the game's own doors ask. A `new` board has nothing to reload, so `restart` refuses there.

```bash
play/send.sh --batch '[{"cmd":"undeploy","args":{"unit":"C"}},{"cmd":"deploy","args":{"unit":"F","x":29,"y":3}},{"cmd":"begin"},{"cmd":"restart"}]'
```

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
`BoardView.GROUND` (#46): `.` grass, `,` tall grass, `:` dirt, `'` plain ground, `~` mud, `w` / `W`
shallow / deep water (split on walkability, so deep water no longer draws as rock), `#` rock or any
other impassable tile, `T` tree, blank a hole or off the map. **A tile state draws over its ground**:
`^` burning, `_` frozen, `;` scorched, `n` cover, so a fire spreading toward you and a frozen-over
river are on the board. A `Ground:` line under the board names only the glyphs it holds. Walkability
is still the board's (`BoardContext.is_walkable`, #109), and so is a cell's move cost
(`BoardContext.move_cost_at`, #1223, which charges ice 1), so the view and the rules cannot disagree
about a frozen cell. Height does not fit in a 3-char cell: when the board has relief or gas the
overview says so and the `terrain` view draws it. A legend table carries what a glyph can't (name,
hp, squad/leader, weapon). Unit handles are session-stable ids
assigned by `PlaySession` — units have no persistent id today.

**Layered views — pull detail only where you act** (token discipline):
- **Overview** (`describe_state`): ruled board + one-line-per-unit legend + turn / squad status. The default; small.
- **Focus** (`focus(unit)`): board re-rendered with that unit's **move range** (`+`) and **attack range** (`×`) overlaid, then the unit's numbers as the game derives them, gear and jobs included (HP, MOV, STR/DEX/PER/CON/BLD, DEF, LDR, squad size against capacity, leash), and each attack it can fire or watch with in `Unit.attack_detail`'s words, the game's own hover readout (#46). A unit still in reserve has no range to draw and answers in words, pointing at `kit`.
- **Terrain** (`terrain`): each cell's height in the rules' half-level units (`Terrain.UNITS_PER_LEVEL` to a level), with `n`/`e`/`s`/`w` for the side a ramp rises toward or `*` for a corner form, then the gas lying on each cell and how thick (#46). Read through `PlaySession.height_at` / `gas_at`, i.e. `BoardHeights` and `GasField`.
- **Preview** (`preview`): the **resolved** outcome of the current/hypothetical plan — exact damage, deaths, counters, net board change — as a concise diff, not a re-dump. The deterministic-engine payoff.
- **Result** (`execute`): the event log (equals the preview, by Law #2). No overview — see below. A hit logs the states it gave and took (`b gains Wet`, `b loses Wet`); a side-channel order logs its actor, verb and target by handle ahead of the game's own words (`A GUARD -> B: Warden guards Warden`), so two units sharing a name stay apart (#46).
- **Affordances** (`legal_moves(unit)` / `legal_targets(unit, attack?)`): where this unit may go, and
  which aims of a given attack hit whom. Cell lists grouped by row (`y=13: 19-23`), a few hundred bytes where the only way
  to ask used to be `focus`, which renders a 2 KB board to say it.

Micro-commands (`queue_move`, `cancel`) return a one-line ack + plan delta, **not** a full re-render —
**the board is redrawn only on `overview` and `focus`, both on request** (#613, 2026-08-28).

`result` and `turn-change` used to redraw too, and that was 63% of all output measured over a real
run: terrain is static, and what a pass changes is a handful of positions and HP, which the event log
already names. Redrawing on every action also crowded out the state that actually gates the next
command — see below.

**Every frame carries a status line**, failures included, because a refusal is exactly when it is
wanted:

```
[turn=PLAYER  active=sqA(2 queued)  free=sqB,sqC  acted=sqD]
```

Measured over five logged playthroughs before this existed, a third to a half of every command was
*rejected* — `move` 55%, `attack` 61% — and the three largest causes were all answerable from this
line plus the two affordance queries: guessing at reach (62), not knowing which squads were spent or
which held the activation (43), and executing with nothing queued (34). The rendered board carried
none of it.

**Batching — and this is how you should drive the bridge, not a feature to reach for occasionally.**
`{"id": N, "cmds": [{...}, {...}]}` runs a list in order and returns one envelope. It **stops at the
first failure**: a refusal is nearly always a wrong belief about turn state, so everything after it
rests on the same wrong belief.

Use `play/send.sh`, which does the write-and-poll:

```bash
play/send.sh overview
play/send.sh move '{"unit":"A","x":22,"y":7}'
play/send.sh --batch '[{"cmd":"legal_moves","args":{"unit":"A"}},{"cmd":"preview"}]'
```

**Why this matters more than convenience (#666).** The protocol is write-then-poll, and every
playtest driver measured so far wrote its own poller in Python and ran it in a loop — 69 of 72 shell
calls in one logged run, 54 of 61 in another. The single run that batched aggressively needed
**three** shell commands and no Python at all. The scripting tracks round-trip count and nothing
else. An agent that must run arbitrary `python3` cannot be given a narrow permission allowlist, so an
unattended playtest needs blanket approval — which removes the guard that stops a session that is
supposed to be *playing* the game from editing it. One batch per turn, through `send.sh`, keeps the
whole allowlist to two entries.

**Running a playtest experiment** — isolating an unattended session, what to measure, and the
several ways an obvious setup produces a wrong answer: [`playtest-experiments.md`](playtest-experiments.md).

**The opponent acts (#665).** `endturn` runs the incoming faction's AI when the board declares it in
`ScenarioData.ai_factions`, and reports what it did as an event log — the same account `execute`
gives of your own pass:

```
Turn -> PLAYER
  b moves to (22, 16)
  d moves to (18, 15)
  Thug6 revs up
```

Before this, `end_turn` advanced the faction and nothing else: the enemy stood still for the whole
match. Playtest reports read like real engagements because the counters in them are derived from the
driver's *own* attacks during resolution, never an enemy taking a turn.

**The turn boundary (#898).** `endturn` runs what the game runs between two turns, through the same
`TurnBoundary` statics the game calls, in the game's order: the side that just played burns if it
is standing in fire (your own units first in the log, each AI faction's after its turn); when the
round completes the tile clocks tick, so fires spread, burn out and scorch; then the incoming
faction's turn-start ticks run (downed clocks, stat effects, Crisis surge, weapon rev, Guard and
watch lapse) and the cohesion sweep ejects anyone out of contact. Until #898 none of it ran
headlessly: a fire never went out or hurt anybody, a downed body never bled out, a Guard never
lapsed. A body whose clock runs out is logged `x bleeds out` in the hand-off that ran it (#46). A burn that ends the mission stops the turn there, and the result then carries a `mission`
key and a `MISSION` line, as `execute` does. A burn is the only thing at the boundary that can end a
headless mission today: a downed unit already counts as lost, so its clock running out changes
nothing until #46 brings authored lose conditions (a protected unit's death) headless. The log is
still returned as `ai_events`, though it now carries the burns as well.

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
Plan preview (sqA):
  MOVE
    A -> (3, 4)
  ATTACK
    A -> a (Chainsword): N dmg (H -> H')   [+Wet]
  REACTION
    a -> A (ChainSword): C dmg (H -> H')
  TERRAIN
    (4, 4) becomes Burning
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
| **M3** | File-bridge interactive loop | ✅ done 2026-06-20 | `play/play_bridge.gd`: polls `playrun/command.json`, writes `playrun/state.txt` with a monotonic `id` handshake. Cmds: new/load/overview/focus/move/attack/cancel/preview/execute/endturn/quit (+ rescue/join/leave/disband). |
| **frames** | Frame persistence (audit trail) | ✅ done 2026-07-08 | `play/frame_log.gd`: every state write also lands in `playrun/frames/run-<stamp>/NNNN-<cmd>.txt` — a playtest is a replayable frame sequence. Tests: `tests/play/test_frame_log.gd`; smoke-verified through the live bridge. |
| **M4** | `LiveBridge` node in the real game | ⬜ next / optional | Host the same bridge inside the running game so a human can watch. |
| **tests** | `tests/play/` + `tests/rules/` | ✅ green | preview == execute (Law #2); no mutation outside `execute()`; scenario round-trip. Full suite 60+/60+, 0 orphans. |

## Limits (honest scope)

Headless **cannot** judge feel, animation timing, readability, or input UX. It **can** judge balance,
determinism/correctness, reachability/softlocks, squad/counter/elemental interactions, and scenario
win/loss (real since #96 — `mission_tag()` reports it). Claude can play **both sides**
(hotseat-as-Claude) — itself a way to pressure-test scenarios — through the exact API the
archetype AI uses.

**Headless scores a mission the way the game does (#46).** `PlaySession` owns a `MissionState`,
the object the game's `MissionController` holds, filled from the scenario by the same
`MissionState.apply_scenario` the game's loader calls. So a CAPTURE or EXTRACT map is not won by a
rout, the clock counts the session's own completed rounds, a protected unit's death latches through
the session's death handler, and a hostile on a defended point loses it. The ending LATCHES on the
first answer that is not ongoing, as it does in the game, which is why the session asks only where
the board has settled: the end of `execute()`, the end-of-turn burn and the hand-off. The overview's
mission block shows the HUD's own briefing rows (`MissionStatusPanel.briefing`), so a driver reads
progress in the words the player does. Both loaders also apply each unit's placement through one door,
`ScenarioUnitEntry.apply_placement`, so a saved Sentry or Hold squad plays its own archetype here and
the board contexts carry the zone store a Sentry's patrol is read from. `tests/flow/test_mission_two_hosts.gd`
loads one mission in both hosts and requires them to agree.

**Headless executes a pass the way the game does (#46).** `execute()` used to hand-copy the game's
attack code, and the copy had drifted: a heal restored nothing, a counter the pass skipped still
spent its ammo, a wader was never soaked, squads never split at pass end, and a unit rescued in the
same pass stood up unspent. Now it calls what the game calls: an attack is `AttackAction`'s
`open_playback`, `land`, `remove` and `settle`; the walk phase is `ResolvedPlan.walk_moments`, a
walk's soaking included; the pass end is `SquadManager.settle_downed` per downed unit, then
`enforce_contact`. The one declared difference is that a shoved body TELEPORTS to its landing where
the game slides it. `tests/flow/test_execute_two_hosts.gd` runs one board through both executors and
requires every unit to come out the same.

**Every verb the game offers in battle, the API has (#46).** `capture`, `group_move` and a rescue's
bank pick closed the last gaps, so every shipped mission can be won or lost headlessly. Three
things keep a headless plan the game's plan rather than a lookalike. The plan **re-resolves after
every order**, on the same `SquadManager` signals the game's queue panel hangs its refresh on
(`PlaySession._refresh_plan`), so the next order is judged against the shoves and downs the plan
already publishes. **Hold orders** are queued by `SquadManager` itself the moment a squad's plan
opens, for every host, so the headless plan carries the same filler the game's does. And the
**loader** goes through the game's own doors (`valid_entries`, the spawn gate, `apply_placement`,
`relink_guards`), so armed Guards and cast provenance survive a headless load.

## Open questions

- Run-dir location: `user://playruns/<id>/` vs. a `res://` path under the repo (gitignored).
- Does `PlaySession` live in `Classes/` (gameplay-adjacent) or a new `tools/`/`play/` dir?
- Per-command id transport details / timeout + error envelope.

## ~~BREAK doctrine hooks~~ — REPEALED 2026-08-09 (was: R9, 2026-07-05 — see [resolution-pipeline.md](design/resolution-pipeline.md))

The BREAK doctrine is repealed ([#155](https://github.com/Phaazoid/Godoiosis/issues/155)) and Crisis — the only player-side choice-point — becomes a deterministic equipped ability ([#158](https://github.com/Phaazoid/Godoiosis/issues/158)), so **neither hook below will ever be built**. Kept as the record of what the repeal saved:

- ~~`execute()`'s event log gains **BREAK entries**~~ — plans no longer diverge; the event log stays a replay of the previewed plan.
- ~~The `answer(choice_id, accept: bool)` verb for a player-side choice-point~~ — with no mid-execution choice anywhere in the game, **the bridge needs zero mid-execution input, permanently**. A headless driver authors a plan, calls `execute()`, and reads results; nothing ever blocks on it mid-pass.
