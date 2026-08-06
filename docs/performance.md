# Iosis — Performance Notes

Where the frame time actually goes, how it was measured, and which optimisations must not be
undone. Started 2026-07-26 after a player-reported hitch on Group Move.

**Why this file exists:** the measuring is the expensive part, not the fixing. Every number below
came from a headless profiling run against a real scenario; without them the obvious suspect was
the wrong one (see *What we guessed wrong*). Re-measure before acting on any perf hunch — and add
what you learn here so the next person doesn't repeat the run.

**Rule of thumb for this codebase:** the board is tiny (single-digit units, and the biggest map is
2560 cells). Almost nothing is slow because of *data volume*. It's slow because a cheap operation
is being repeated far more often than anyone intended — usually via a signal fan-out.

---

## How to re-measure

```bash
"C:/Godot/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe" --headless --path "C:/Iosis/Godoiosis" --script res://tools/profile_group_move.gd
```

`tools/profile_group_move.gd` boots the real `Main.tscn`, loads Castle Assault, and times the
Group Move click end to end plus each stage. It lives outside `tests/` so the suite runner never
tries to discover it. Copy it as the starting point for profiling anything else — the useful parts
are the pattern (boot the real scene, load a real scenario, `Time.get_ticks_usec()` around the
real call) and `_plan_signature()`, which is how you prove an optimisation didn't change behaviour.

**Always capture a plan signature before optimising.** It is the difference between "it's faster"
and "it's faster and still correct". Both fixes below were verified against a signature recorded
before any change. It is just as useful in the other direction: #115 *added* work to the solver, and
the signature is what proved the added work changed no formation (see below).

**One run is not a measurement.** Four consecutive runs of this profiler on identical code put
`GroupMoveSolver.plan` between **5.6 and 7.0 ms** — a ~25% spread. Anything smaller than that is
invisible here, so take 3–4 samples and compare *ranges*, not single numbers. Sub-millisecond claims
need a tighter harness than this one.

---

## 2026-07-26 — Group Move click (Castle Assault, 5-member squad)

Reported as "a small but noticeable lag between clicking the destination and the units showing up".
Real: **232 ms**, about a 14-frame hitch at 60 fps. Neither cause was introduced by that week's
refactoring — both were verified present at HEAD beforehand.

| Stage | Before | After |
|---|---|---|
| `GroupMoveSolver.plan` | 37.0 ms | **6.2 ms** |
| `queue_action` × 5 members | 186.6 ms | *(coalesced)* |
| `refresh_action_queue` (each) | 8.9 ms | **4.6 ms** |
| **Whole click** | **232.3 ms** | **64.9 ms** |

### What we guessed wrong

The instinct was that the *formation solver* was the problem — it's the only thing that looks like
an algorithm. It was 16% of the cost. **80% was the click repainting the world five times**, which
no amount of reading the solver would have found.

### Cause 1 — per-order fan-out (the 80%)

`queue_group_move` queued each member's move individually. Every `queue_action` emits
`action_queued`; `game._on_unit_action_queued` responds by re-validating, redrawing the leader
range, redrawing squad icons, and calling `refresh_action_queue` — which resolved the whole plan
**twice** (once for the queue rows, once for `_preview_plan_effects`).

Five members → **12 full plan resolutions and 11 full re-validations for one click.**

Fixed by `SquadManager.batching` + a single resolve in `refresh_action_queue`.

### Cause 2 — unbounded BFS (the 16%)

`GroupMoveSolver._path_hops` walked the map's entire `used_rect` (2560 cells) once per member, to
answer roughly twenty distance queries each. Two independent bounds were available; both apply.

Also found in the same loop: `board.grid.get_used_rect()` was re-fetched **per neighbour**, and the
`[UP, DOWN, LEFT, RIGHT]` array was reallocated on every cell visit.

---

## Invariants — do not undo these

**`SquadManager.batching` must stay synchronous.** It is safe *only* because no frame is drawn
between the individual queues, so every intermediate state it skips was unobservable. Law #2 is
about what the player can SEE. If a batch ever spans a frame (an `await`, a `call_deferred`), the
queue panel goes stale and the guarantee is gone.

**`action_queued` must keep firing per order.** It is tempting to suppress the signal itself during
a batch. Don't: `game._on_unit_action_queued` does one cheap per-*unit* job — swapping the real
sprite for the projected ghost — and skipping it would leave every member but the last rendered
twice. Only the expensive squad-level repaint (`game._repaint_squad_plan`) is coalesced.

**The COHESION field must ask `RulesService.can_traverse`, not `movement_cost`** (#115, 2026-07-29). It
takes a unit now, because traversal is per-unit — a Waterwalker's connected region includes water,
and building one shared field from the bare cell predicate silently un-did the ability for any unit
moving with its squad. Routing it through `movement_cost` instead is the obvious-looking
simplification and is **wrong**: that adds the enemy-occupancy rule, which would let a single enemy
body sever the cohesion field and change formations near any enemy. Occupancy blocks a move; it is
not terrain, and it moves every turn. Pinned by `test_an_enemy_body_does_not_sever_the_cohesion_field`.

**…but occupancy-awareness is now an OPT-IN parameter, and the default is the load-bearing half**
(`path_hops(…, block_on_occupancy := false)`, #127, 2026-08-06). The paragraph above is a rule about
the *cohesion caller*, not about the function: the AI's approach picker needs the opposite answer,
because it is estimating the route a unit will actually walk, where a standing enemy genuinely must
be gone around. Both are one question — hop distance under a traversal rule — so the rule is a
parameter each caller states rather than a second BFS to hand-copy.

**Which side each caller takes, and why it is not negotiable per-caller:**
- `GroupMoveSolver` (cohesion, ×2) — **blind**, for the #115 reason above. The pin calls the default
  form, so flipping the default goes red.
- `AITactics.nearest_enemy` (via `_approach_distances`) — **aware**, but only because it stopped
  routing to enemy *squares*. Routing to a square with occupancy on scores every enemy `UNREACHABLE`
  (an active enemy blocks passage) and collapses selection to the raw-distance tie-break; routing to
  each enemy's standable **firing cells** is what makes the honest metric usable here. Still one BFS
  for all enemies — the `until` set is the union of every firing cell. Keeping it blind was the
  original #127 answer and was wrong for a subtler reason: it made target selection and the approach
  picker disagree about which enemy was closest.
- `AITactics._best_approach` (**both** approach callers — attack *and* Sentry's walk home) — **aware**,
  unconditionally. This half is deliberately NOT keyed off the attack-specific `route_target`: keying
  it there welded two unrelated questions to one flag and left `closest_reachable_cell_to` unable to
  reach the fix. A sentry walking home through a corridor an enemy is holding stalls in exactly the
  same way, and is pinned separately by
  `test_walking_home_routes_around_a_body_holding_the_corridor`.

**The cohesion (leash) field is computed per member, and that is not a regression to "fix".** It was
one shared call before #115. Cost of the change, measured over four runs against a single-run 5.75 ms
baseline: `plan` came in at 5.6–7.0 ms, i.e. **inside the harness's own noise** — the extra
depth-bounded walks are far cheaper than the `compute_move_range` call sitting beside them in the
same loop (~1 ms per member, essentially all of `plan`'s time). The plan signature was **IDENTICAL**
on all four runs, which is the part that matters: Castle Assault has no Waterwalkers, so any
signature change would have meant ordinary formations moved.

**`_path_hops`' two stopping rules only skip work whose answer was already discarded.**
- `max_depth` — the caller only compares the result against a threshold, so a cell beyond the bound
  is absent, and an absent read is `UNREACHABLE`, which fails the same comparison a real larger
  distance would.
- `until` — stops once every requested cell has a distance. A genuinely unreachable request can
  never satisfy that, so the walk degrades to the full connected region: correct, just not faster.

If a future caller needs the *whole* field, give it an unbounded call rather than widening these.

**Pinned by:** `tests/squad/test_group_move_batching.gd` (batched == unbatched, flag cleared,
orders still validated, exactly one repaint per group move, single orders unaffected) and the BFS
bound tests in `tests/ai/test_ai_control.gd`.

---

## Known-and-accepted costs

**`game.get_unit_at_cell` is a linear scan**, called ~18 times, twice from inside loops
(`draw_joinable_squads` is O(units² × cells)). Reviewed 2026-07-26 and deliberately left: boards
are single-digit unit counts, so the whole sweep is free. A cell→unit index would be O(1) but adds
a cache to invalidate on every spawn, move, knockback and death — a new invariant for no measurable
gain. Revisit if a handcrafted level ever fields enough units to show up in a frame.

**What's left in the 64.9 ms**, if it ever needs another pass:
- `compute_move_range` once per member (scales with squad size, not map size)
- `_on_squad_became_active`'s `refresh_action_queue` — fires mid-batch and is *not* coalesced
- `exit_current_mode`'s own validate + refresh

Scaling note: after the BFS bounds, the per-member walk is proportional to *candidate count*, not
map size, so a bigger map barely moves this. What scales is **squad size** — a 10-member squad
costs roughly double, not eight times.

---

## 2026-08-04 — the Group Move feasibility sweep

Group Move gained a second question — *"can the whole squad follow to that cell?"* — so unfollowable
destinations get painted red instead of accepting a click that quietly does nothing. Measured on the
same board and destination as the 2026-07-26 run:

| Call | Cost |
|---|---|
| `GroupMoveSolver.plan` (5 members) | 7.7 ms |
| `followable_destinations`, **38 destinations** | 7.5 ms |
| `followable_destinations`, **1 destination** | 6.8 ms |
| **Whole click** | **77.7 ms** (was 64.9) |

**The shape that matters: the sweep costs the same for one destination as for thirty-eight.** It is
one `compute_move_range` per member (~1 ms each) plus a dilation over that member's standable
footprint; the destination count barely enters. That is the whole reason it is not a `plan()` per
cell, which would be 4–6 ms *each* — 176 ms to filter a 44-cell range, a visible hitch on mode entry.

**Plan signature unchanged.** The same run verifies the solver's new most-constrained-first
assignment order against the recorded baseline: `IDENTICAL -> true`. The ordering fixes formations
that were previously dropped (6 of 16 destinations for one Castle Assault squad) without altering
any formation that already worked.

**Where the +12.8 ms went.** `_click_choosing_group_move` and `_hover_choosing_group_move` each call
`followable_destinations` for their single cell *and* `plan()`, so the per-member
`compute_move_range` runs **twice**.

**FIXED the same day by `game.group_move_followable`**, a mode-entry cache. `enter_group_move_mode`
already swept the whole range to paint the overlay; the set is now kept and both the hover and the
click read it instead of re-sweeping their one cell. Three runs before and after, 12-destination
sample, warmed:

| per hover cell-change | before | after |
|---|---|---|
| run 1 | 15.05 ms | **7.77 ms** |
| run 2 | 14.99 ms | **8.17 ms** |
| run 3 | 14.75 ms | **8.06 ms** |
| whole click | ~76.5 ms | **65.1 / 68.0 / 72.3 ms** |

**~6.9 ms per cell change, 46%** — and the number that mattered was never the percentage but which
side of the 16.7 ms frame budget hover lands on. At ~14.9 ms a fast mouse sweep spent a near-whole
frame per cell on top of everything else that frame did; at ~8.0 ms it is half a budget. The click
is back to its 2026-07-26 figure (64.9 ms). Mode entry is unchanged — the sweep it already ran
*became* the cache build. Plan signature `IDENTICAL -> true` throughout.

What remains in the ~8.0 ms is `plan()` itself, and it is irreducible: it depends on the hovered
cell and it IS the formation preview.

**Why the cache is safe, and the one thing that would break it:** nothing on the board can move
while `CHOOSING_GROUP_MOVE` is up — no order is queued, no unit relocates — so the set cannot go
stale within the mode. It is built at the mode's single door (`enter_group_move_mode`, one
production caller) and cleared in `exit_current_mode`, the same lifecycle as `selected_unit` and
`last_clicked_cell`. **An empty dict means "the squad can follow nowhere", not "unset"**, so there is
deliberately no recompute-if-empty fallback: a caller that skips the door must fail visibly rather
than silently pay the cost back. The profiler's second hover stamp is that avoided cost — if it ever
climbs back toward the first, something stopped reading the cache.

A cheaper half-measure, if the cache looks like too much: flip `followable_destinations`' inner loop
to iterate *destinations × diamond* rather than *standable cells × diamond*. Same answer, and the
single-cell query stops paying for the whole footprint — worth ~2.6 ms of the 6.8. It does not touch
the duplicated `compute_move_range`, which is the real cost.
