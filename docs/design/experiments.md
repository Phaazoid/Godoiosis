# Experiments (feature-flag harness)

A lightweight way to build a proposed feature behind a toggle, *feel* it in play, and turn
it on/off without committing to it. Lets us carry several "maybe" systems in the codebase
at once and decide by playing, not arguing.

**Canon checked through #1176 (2026-10-01); #508's gas mixes folded in 2026-10-02.**

## Shape

One registry, read statically anywhere, toggled from a dev tab. **No autoload** — GDScript
`static var` provides the global mutable state, mirroring how `Stats` / `Elemental` are
class-level statics.

| Piece | File | Owner | Status |
|---|---|---|---|
| Registry: `enum Flag`, `DEFS` metadata, `is_on()` + state | `Classes/dev/Experiments.gd` | infra | **built** |
| Dev tab: a live row per flag (checkbox or dropdown) | `Classes/dev/ExperimentsTool.gd`, the dev tools' Session > Experiments leaf (#382) | UI | **built** |
| Persistence | `user://experiments.cfg` (keyed by flag name) | infra | **built** |
| Guards | `tests/experiments/test_experiments.gd` | infra | **built** |
| Choice rows (#508) | `options` in a `DEFS` entry; the tab draws a dropdown | infra + UI | **built** |

**The dev tab is built (#382)**: Session > Experiments draws a row per flag straight off the registry -- a checkbox for a toggle, a dropdown for a choice -- so a new flag needs no UI wiring. (This doc said otherwise from 2026-07-16 until #955's sweep.)

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

The Experiments page picks it up automatically. Toggle state persists across launches and survives F2 reset.

### A CHOICE between several treatments (#508)

A flag is a toggle unless its `DEFS` entry declares `options`, which makes it a **choice**: `default`
is then an option INDEX and the tab draws a dropdown. #508's `GAS_STYLE` is the first (four looks
for gas, then four mixes of the one that won, compared in play); `GAS_OVER_UNITS` beside it stays a toggle. It is `PlayerSettings`' row
kind, same shape, and it brings the same refusal (#647): **each typed facade turns the other kind
away** -- `is_on` / `set_on` / `default_of` push an error on a choice, `choice_of` / `set_choice` on a
toggle -- because the coercions underneath are silent: `bool(2)` is `true`, so a caller left on
`is_on` reads every non-zero option as ON. `value_of` is the kind-blind read for a caller walking
every flag (the test fingerprint, a reset).

```gdscript
match Experiments.choice_of(Experiments.Flag.MY_CHOICE):
    0: pass   # one treatment
    1: pass   # another
```

A choice ends the way a toggle does: the winning option becomes the only code path and the flag
goes.

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

`user://experiments.cfg`, section `[experiments]`, one `FLAG_NAME=value` line per
explicitly-set flag -- a bool for a toggle, an option INDEX for a choice. `load_state` answers a
choice BEFORE the toggle's `bool()` (which would read a saved 2 back as `true`, on every relaunch)
and drops an index out of range, so a choice that lost an option falls back to its default. Unset flags fall back to their `DEFS` default, so the file only lists
deviations from default. Human-readable and hand-editable.
