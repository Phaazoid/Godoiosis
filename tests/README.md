# Iosis tests

Pins the **settled** systems (the squad spec) as executable invariants so they don't regress while elemental/Will work churns the same files. Mirrors the spec numbering: squad invariants **I1–I7**, counter rules **C1–C7**, volley semantics, plus two **Law guards**.

> **Status (2026-06-16): gdUnit4 GREEN, Tier-1 + Tier-2.** 33 test cases, 0 failures, **0 orphans, exit 0** (headless, Godot 4.6). Tier-1 pure-logic (`unit/test_grid_utils.gd`), Tier-2 node-fixture squad/counter/volley invariants (`squad/`), and the Law guards (`law/`) all pass.

## Running the tests

One command (PowerShell), from anywhere in the repo:

```
powershell -File tests\run_tests.ps1                     # whole tests/ tree
powershell -File tests\run_tests.ps1 res://tests/squad   # one folder or suite
```

`run_tests.ps1` runs Godot headless against gdUnit4 and returns the suite's exit code. It defaults to `C:\Godot\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`; override with `$env:GODOT_BIN`. The raw command it runs:

```
<godot-console-exe> --path . --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
```

**Exit codes (from gdUnit4's `report_exit_code`):** `0` = clean pass · `100` = test failures **or** caught engine errors (e.g. a `push_error`/runtime error during a test) · `101` = passed but **orphan nodes** were detected. Treat anything non-zero as "fix it" — see orphan-node hygiene below.

## Gotchas (learned the hard way — don't re-discover)

- **Use the `_console.exe`** Godot build on Windows, or you capture no stdout.
- **`--ignoreHeadlessMode` is required** — gdUnit4 refuses headless runs without it. UI/input tests don't work headless, but pure-logic and node-state tests do.
- **After adding a new global `class_name`, run a one-time import** or you'll hit `Could not find type "X" in the current scope`:
  ```
  <godot-console-exe> --headless --path . --import
  ```
  These suites avoid that entirely: shared helpers are **`preload`ed, not `class_name`d** (`const H := preload("res://tests/support/squad_fixtures.gd")`), and test suites only `extends GdUnitTestSuite`. Editing test bodies or adding new `test_*` files needs no import — gdUnit4 rescans `tests/` at run time.
- **`--remote-debug` needs a real port** (1–65535); `tcp://127.0.0.1:0` is rejected in 4.6, so we don't pass it.
- **Orphan-node hygiene = the exit code.** gdUnit4 counts "orphan nodes" (`root.get_orphan_node_ids()` — any `Node` not in the SceneTree) sampled *during* each test, and returns `101` if any remain. So a fixture that `Node.new()`s something must keep it **in the tree** or `auto_free` it. The big trap here: `SquadManager` creates `Squad` nodes as *its own* children, so if the manager itself is orphaned (not in the tree) every squad it makes is an orphan too. `make_manager` therefore stands the manager up **inside the tree** (see fixtures below). Counterpart: `queue_free()` only works for in-tree nodes, which is a second reason to keep the graph in-tree.
- **RefCounted reference cycles leak** (no GC). A volley's `AttackAction.volley` array references every sibling including itself, so a volley is a self-referential cycle that never frees — the volley suite breaks it in `after_test` (`attack.volley = empty`). See findings; this is a real (small) gameplay leak too.

## Install (already done; recorded for reproducibility)

gdUnit4 was vendored from `github.com/MikeSchulze/gdUnit4` into `addons/gdUnit4/` (its own `test/` folder dropped to keep it lean) and enabled in `project.godot` `[editor_plugins]` next to AsepriteWizard. In a headless run gdUnit4 detects the CI environment and skips its editor plugin automatically. `reports/` (generated) is gitignored.

## Layout

```
tests/
  README.md            <- you are here
  run_tests.ps1        <- one-command headless runner
  support/
    squad_fixtures.gd  <- preloaded fixtures (in-tree SquadManager, Unit factory)
  unit/                <- Tier-1 pure-logic suites (no scene)
    test_grid_utils.gd
  squad/               <- Tier-2 node-fixture invariants
    test_counters.gd     C1–C7
    test_invariants.gd   I1–I7
    test_volley.gd       AoE / volley semantics
  law/                 <- cross-cutting Law guards
    test_resolution_laws.gd   determinism + preview==execution
```

## Fixtures (`support/squad_fixtures.gd`)

The hard part of Tier-2 was standing up real `Unit`/`SquadManager` nodes cheaply. The reusable moves, all encoded here:

- **`spawn_unit` / `spawn_solo`** — instance `Scenes/unit.tscn`, set `unit_data` *before* it enters the tree (else `_ready` push_errors), `auto_free` it, then place it by writing `movement.cell` **directly** (a plain field — no grid/`TileMapLayer` needed, since we never call `movement.set_cell`). `spawn_solo` also wraps it in its own squad.
- **Pattern-less weapons** — `make_weapon()` leaves `attack_pattern` null, so `CombatComponent` reach falls back to Manhattan range 1. Counter geometry becomes trivial: distance ≤ 1 can hit, ≥ 2 cannot.
- **`make_manager`** — builds a tiny in-tree graph so the manager's `@onready` siblings resolve and its squads aren't orphans:
  ```
  GameRoot (Node, added to the suite tree + auto_free'd)
  ├── Grid (TileMapLayer)            # satisfies $"../Grid"
  ├── OverlayManager (+ 9 Node2D overlay children)   # satisfies $"../OverlayManager"
  └── SquadManager (the real one)
  ```
  The `OverlayManager` is the *real* class with bare `Node2D` children (its `_ready` only sets each child's `modulate`). No test calls into overlay/grid; these just satisfy the wiring. The whole subtree frees via the one `auto_free(GameRoot)`.

## Test plan & coverage

**Tier 1 — pure logic, no scene** (`unit/test_grid_utils.gd`, 10 cases): `manhattan_distance`, `cardinal_direction_between`, and `cells_within_manhattan_range` (incl. the `range`-shadow probe — see findings).

**Tier 2 — node fixtures** (all green):

| suite | asserts | spec |
|---|---|---|
| `squad/test_counters.gd` | C1–C7 via `can_counter` / `choose_counter_target` / `calculate_counterattacks_for_squad` | Counter rules |
| `squad/test_invariants.gd` | I1–I7 lifecycle (create/join/leave/detach/reassign/disband) | squad-system.md Invariants |
| `squad/test_volley.gd` | one `AttackAction` per victim, shared `volley`, primary vs secondary | AoE / volley |

**Law guards** (`law/test_resolution_laws.gd`, see `docs/design/resolution-pipeline.md`): **R2 determinism** — deriving counters from the same plan twice is identical; **R3 preview==execution** — the damage previewed at plan time equals what `combat.apply_damage` subtracts. These are the hooks elemental/Will plug into.

## Findings (spec-vs-code drift — record, don't silently "fix")

- **`GridUtils.cells_within_manhattan_range` `range` shadow — RESOLVED, benign.** The parameter named `range` shadows the built-in, but the probe (`test_cells_within_manhattan_range_*`) passes: GDScript resolves the built-in `range()` at the call site regardless, so it's a cosmetic lint warning, not a bug. (Renaming it would silence the warning; not urgent.)
- **Volley `AttackAction` cycle leak — [#35](https://github.com/Phaazoid/Godoiosis/issues/35).** `create_volley` points every sibling's `volley` at the shared array that contains them, forming a RefCounted cycle. After a volley executes and the queue clears, those `AttackAction`s never free (no GC) — a small per-AoE leak that accumulates over a session. Tests break the cycle in `after_test`; **gameplay code has no such break** (candidate fix: clear/`= []` the volley refs after execution, or weak-ref them).
- **I2 chokepoint — RESOLVED ([#23](https://github.com/Phaazoid/Godoiosis/issues/23)).** Member removal now funnels through `Squad._erase_member()` (the sole `members.erase` caller); both `_detach_from_current_squad` and `disband_squad` route through it. The I2 test pins the *observable* detach contract; the single-eraser property is a greppable static check (`members.erase` appears exactly once).
- **I7 scope** — `spawn_unit` lives in `game.gd` (full scene); the suite pins its core contract (`create_squad` → registered solo squad) and documents the gap.
- **`WeaponData.can_counter` honored — RESOLVED ([#34](https://github.com/Phaazoid/Godoiosis/issues/34)).** `SquadManager.can_counter` now gates on both the *component* flag (`countering_unit.combat.can_counter`) **and** the weapon's own `can_counter` policy field (`SquadManager.gd:323`), so the authoring-tool toggle works. (Still wants a C6-style test: armed in-range defender whose weapon has `can_counter=false` → zero counters.)
- **"Class 'Unit' hides a global script class"** printed once during a forced `--import`, not during test runs; grep confirms a single `class_name Unit`, so it's a benign reimport-ordering artifact.
