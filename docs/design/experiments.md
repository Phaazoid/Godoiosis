# Experiments (feature-flag harness)

A lightweight way to build a proposed feature behind a toggle, *feel* it in play, and turn
it on/off without committing to it. Lets us carry several "maybe" systems in the codebase
at once and decide by playing, not arguing.

**Canon checked through #68 (2026-07-16).**

## Shape

One registry, read statically anywhere, toggled from a dev tab. **No autoload** — GDScript
`static var` provides the global mutable state, mirroring how `Stats` / `Elemental` are
class-level statics.

| Piece | File | Owner | Status |
|---|---|---|---|
| Registry: `enum Flag`, `DEFS` metadata, `is_on()` + state | `Classes/dev/Experiments.gd` | infra | **built** |
| Dev tab: a live toggle per flag | `Classes/dev/ExperimentsTool.gd` + `Scenes/DevOverlay.tscn` | UI | **not built** — no such file, no tab wired into `DevOverlay.tscn` |
| Persistence | `user://experiments.cfg` (keyed by flag name) | infra | **built** |
| Guards | `tests/experiments/test_experiments.gd` | infra | **built** |

**Found stale 2026-07-16:** this doc previously read as describing a complete, working harness. Only the registry + persistence + test guard exist — there is currently no in-game way to toggle a flag; use `Experiments.set_on(flag, value)` from code, or hand-edit the `.cfg`, until the dev tab is built.

## Add an experiment

1. Add a value to `Experiments.Flag` (anywhere — see "flags are meant to be culled" below).
2. Add its metadata to `DEFS` (`title`, `desc`, `default`).
3. Read it where the feature lives:

   ```gdscript
   if Experiments.is_on(Experiments.Flag.MY_FEATURE):
       # new behaviour
   else:
       # current behaviour
   ```

**No dev tab exists yet** to pick this up automatically (see the Status column above) — for
now, toggle via `Experiments.set_on(Experiments.Flag.MY_FEATURE, true)` from code, or hand-edit
`user://experiments.cfg`. Toggle state persists across launches and survives F2 reset either way;
once a dev tab is built, it would iterate the registry and need no per-flag wiring.

## Reading a flag — the determinism contract

Laws #1 and #2 say **preview must equal execution**. Experiments that change combat
resolution must not break that — and they don't, *if you read them in the right place*:

- `PlanResolver` bakes results into `ResolvedOutcome`, and `AttackAction` is pure playback
  of `.resolved`. So a flag read **inside the resolution layer** is captured at resolve
  time — preview and execution see the same value even if the flag is toggled in between.
- **Rule:** read a resolution-affecting flag only inside `PlanResolver` /
  `SquadManager.resolve_plan`, never re-read it at execution / animation time.
- **Safety (build it alongside the first resolution-affecting flag):** toggling such a flag
  should invalidate any queued-but-unexecuted plan so the on-screen preview re-resolves
  under the new value. v1's sample flag is inert, so this hook isn't wired yet. Likely seam:
  the dev-tab toggle handler asks the active squad to re-resolve.

Flags that only affect dev visuals, logging, or non-combat UI are unconstrained.

## Flags are meant to be culled

Unlike `Stats.Stat` / `Elemental.Element`, the `Flag` enum is **intentionally NOT
append-only**. Nothing in saved game content (`.tres`) ever references a `Flag`; the only
serialization is the dev-only `user://experiments.cfg`, keyed by the flag's **name**, so
deleting or reordering flags can't corrupt anything.

So every experiment has an end state:

- **Promote** — you want it: delete the flag, make the new branch the only branch, drop the
  `is_on` checks.
- **Cull** — you don't: delete the flag and the code behind it.

Leaving a flag in place forever is the failure mode; a stale flag is debt.

## Persistence

`user://experiments.cfg`, section `[experiments]`, one `FLAG_NAME=bool` line per
explicitly-set flag. Unset flags fall back to their `DEFS` default, so the file only lists
deviations from default. Human-readable and hand-editable.
