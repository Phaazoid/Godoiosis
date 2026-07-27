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
before any change.

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
