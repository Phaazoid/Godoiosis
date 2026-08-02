# Iosis tests

Pins the **settled** systems (the squad spec) as executable invariants so they don't regress while elemental/Will work churns the same files. Mirrors the spec numbering: squad invariants **I1–I7**, counter rules **C1–C7**, volley semantics, plus two **Law guards**.

> **Status (2026-06-16): gdUnit4 GREEN, Tier-1 + Tier-2.** 33 test cases, 0 failures, **0 orphans, exit 0** (headless, Godot 4.6). Tier-1 pure-logic (`unit/test_grid_utils.gd`), Tier-2 node-fixture squad/counter/volley invariants (`squad/`), and the Law guards (`law/`) all pass.

## Running the tests

One command (PowerShell), from anywhere in the repo:

```
powershell -File tests\run_tests.ps1                     # full tree            ~155s (see note)
powershell -File tests\run_tests.ps1 fast                # the fast tier        ~42s
powershell -File tests\run_tests.ps1 weapons items       # one or more areas    ~0.26s per case
powershell -File tests\run_tests.ps1 res://tests/squad   # explicit path (back-compat)
```

**Tiers** (added 2026-07-24) are named in `run_tests.ps1`'s `$Tiers` table — edit it there, it's the only definition:

- **`fast`** = `law` + `rules` + `stats` + `unit` + `util` — 149 cases. The invariant core: the Law guards (action-registry completeness, AI action coverage, damage floor, DEF mitigation) plus the pure rule/math layers. This is the "did I break something cross-cutting" check for the inner loop, **not** a substitute for the full run before a commit.
- **`full`** = the whole tree (the default).
- Anything else is treated as an **area** — a folder name under `tests/`. A typo'd area is a hard error, deliberately: gdUnit4 treats an unmatched `-a` path as "zero suites" and still **exits 0**, which reads as a clean pass.

`-a` is repeatable (`GdUnitTestCIRunner.add_test_suite` appends), which is what makes multi-area runs work.

`run_tests.ps1` runs Godot headless against gdUnit4 and returns the suite's exit code. It defaults to `C:\Godot\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`; override with `$env:GODOT_BIN`. The raw command it runs:

```
<godot-console-exe> --path . --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
```

> **⚠ Ignore gdUnit4's `Total execution time` line — it is not wall clock.** It printed `1min 55s` for a 573-case run immediately after a cache clear, then `12s` for the *identical* run warm. It is wrong in both directions, so don't read it as an upper *or* lower bound. `run_tests.ps1` prints its own stopwatched `Elapsed` line; trust only that one.
>
> **Measured on `Elapsed`:** full run **153–157s** (eleven consecutive runs 2026-07-26 at 605 cases; independently **158s** at 610 cases on 2026-07-27) — budget ~2.5 minutes. `fast` is **42s** (156 cases) and three areas together **51s** (both 2026-07-27).
>
> That works out to **~0.26s per case in every tier** — the cost is flat per-case, not a fixed startup you can amortize, so a tier only helps in proportion to how many cases it skips. The same suite passes **Linux CI in a 34s total job** while the case count only grew 573 → 610, so the ~4.5x gap is a Windows/environment factor rather than suite size. **Cause unconfirmed**; antivirus scanning the repo tree and `.godot` cache state are the untested suspects. (Earlier notes here claimed ~20s full / ~7s fast / ~3-5s per area, taken from gdUnit4's warm number; corrected 2026-07-27.)
>
> **Observation, 2026-07-27 (Unit.gd review session):** three consecutive full runs measured **19.5s / 19.9s / 20.9s** at 610–612 cases, hours after the 158s reading above and on the same machine. The session had just run `godot --headless --import` (to register a new `class_name`), and the speed persisted across later runs that did *not* re-import — a data point for the `.godot`-cache suspect. **The 153–158s figures above stand**: the slow behaviour keeps recurring and the fast state has not been shown to last. Treat this as "try an import pass before you accept a 2.5-minute loop", not as a new baseline.

**Exit codes (from gdUnit4's `report_exit_code`):** `0` = clean pass · `100` = test failures **or** caught engine errors (e.g. a `push_error`/runtime error during a test) · `101` = passed but **orphan nodes** were detected. Treat anything non-zero as "fix it" — see orphan-node hygiene below.

> **The runner reports gdUnit4's verdict, not the process exit code** (changed 2026-07-29, [#93](https://github.com/Phaazoid/Godoiosis/issues/93)). Godot can die with an access violation *while tearing the engine down* — after every test has run and been counted — which made a clean pass report failure. `run_tests.ps1` now parses gdUnit4's own `Exit code: N` line and exits with that, printing a loud yellow NOTE when the process disagreed. This is strictly **more** truthful than trusting the process, in both directions:
>
> | situation | process | runner exits | how you see it |
> |---|---|---|---|
> | clean pass | 0 | **0** | normal |
> | clean pass + teardown crash | `-1073741819` | **0** | yellow NOTE naming #93 |
> | real test failure | 100 | **100** | the failures themselves |
> | real failure + teardown crash | `-1073741819` | **100** | the failures themselves |
> | crash *before* gdUnit4 reports | non-zero | **non-zero** | red "never reported a verdict" |
>
> The last row is the safety property: a run that dies mid-flight produces no verdict line, and **no verdict is treated as failure** — the fix cannot swallow a genuine crash. Verified against all four cases, including a deliberate `OS.crash()` mid-suite.
>
> **CI carries the same logic** (`.github/workflows/tests.yml`), because it invokes Godot directly rather than through this script. The full-tree run happens not to trigger the crash today, but that masking is incidental — it depends on how many suites are loaded and shifts whenever anyone adds one. Keep the two in step: if you change the verdict rule here, change it there.

## Writing a new test suite — quick-start

1. **Pick where it lives.** Mirror the existing folders: `unit/` (pure logic, no scene), `squad/` (node-fixture squad/counter/volley invariants), `law/` (cross-cutting guards), or a new domain folder (`weapons/`, `jobs/`, `ai/`, ...) if none fit. `run_tests.ps1 res://tests/<folder>` runs just that folder while iterating.

2. **Decide which fixture helper you need** (`support/squad_fixtures.gd`, `const H := preload(...)`). Does the code path under test call `get_projected_destination()` — directly or transitively (`PlanResolver`, `AttackAction.execute()`, anything squad-membership-aware)?
   - **Yes** → `H.spawn_solo(suite, manager, faction, cell, ...)` + `H.make_manager(suite)` in `before_test()`.
   - **No** (plain unit-level helpers/gates) → bare `H.spawn_unit(suite, faction, cell, overrides={}, give_weapon=true, weapon_power=3)` is enough and much less setup.

   Getting this right up front avoids standing up a `SquadManager` fixture you didn't need.

3. **Never call `AttackAction.execute()` directly in a test.** It `await`s `actor.visuals.play_attack_lunge(...)`, an animation coroutine. Call `PlanResolver.resolve()` and assert `.resolved.damage`/`.resolved.lethality` instead, or call the specific method `execute()`'s body would call. Side-channel actions with no animation (`IntimidateAction`, `ReloadAction`, `RallyAction`) don't have this problem — call `execute()` directly on those.

4. **Build content ad hoc — never load a `.tres`.** Construct `WeaponData`/`WeaponAttackData`/`UnitData` directly via `.new()` in a local helper function: throwaway, not catalog-registered (mirrors `make_unit_data` in the fixtures file).

5. **New global `class_name`?** See the import gotcha below — prefer `preload()` in test-only support files to sidestep it entirely.

6. **Assertion idioms used across the suite:** `assert_bool(x).is_true()/.is_false()`, `assert_int(x).is_equal(y)`, `assert_array(x).contains_exactly([...])`, `assert_object(x).is_same(y)` (reference identity, not value equality), `assert_that(x).is_equal(y)` for enums.

7. **Run it:** `powershell -File tests\run_tests.ps1 res://tests/<your-folder>`. On a large run, redirect to a file and search it (`... *> out.txt`) rather than trusting a truncated terminal capture. Always re-run after fixing a failure — see the truncation gotcha below.

## Gotchas (learned the hard way — don't re-discover)

- **Use the `_console.exe`** Godot build on Windows, or you capture no stdout.
- **`--ignoreHeadlessMode` is required** — gdUnit4 refuses headless runs without it. UI/input tests don't work headless, but pure-logic and node-state tests do.
- **After adding a new global `class_name`, run a one-time import** or you'll hit `Could not find type "X" in the current scope`:
  ```
  <godot-console-exe> --headless --path . --import
  ```
  These suites avoid that entirely: shared helpers are **`preload`ed, not `class_name`d** (`const H := preload("res://tests/support/squad_fixtures.gd")`), and test suites only `extends GdUnitTestSuite`. Editing test bodies or adding new `test_*` files needs no import — gdUnit4 rescans `tests/` at run time.
- **`--remote-debug` needs a real port** (1–65535); `tcp://127.0.0.1:0` is rejected in 4.6, so we don't pass it.
- **A suite ABORTS at its first failing test, and the console count hides it** (measured 2026-08-02). A 19-case suite that fails at case 15 prints `Statistics: 14 test cases | 2 failures`; cases 16–19 never run and emit nothing. The report XML header carries the honest total (`tests="19"`). So **a failure count is a floor, never a total** — after a refactor, "only one test broke" usually means "one broke and I can't see past it". Fix the first failure and re-run before judging scope; a suite reporting fewer cases than it has `func test_` definitions *is* the signal.
- **Orphan-node hygiene = the exit code.** gdUnit4 counts "orphan nodes" (`root.get_orphan_node_ids()` — any `Node` not in the SceneTree) sampled *during* each test, and returns `101` if any remain. So a fixture that `Node.new()`s something must keep it **in the tree** or `auto_free` it. The big trap here: `SquadManager` creates `Squad` nodes as *its own* children, so if the manager itself is orphaned (not in the tree) every squad it makes is an orphan too. `make_manager` therefore stands the manager up **inside the tree** (see fixtures below). Counterpart: `queue_free()` only works for in-tree nodes, which is a second reason to keep the graph in-tree.
- **RefCounted reference cycles leak** (no GC). A volley's `AttackAction.volley` array references every sibling including itself, so a volley is a self-referential cycle that never frees — the volley suite breaks it in `after_test` (`attack.volley = empty`). See findings; this is a real (small) gameplay leak too.
- **The engine can segfault on SHUTDOWN, after a clean pass** (exit `-1073741819` = `0xC0000005`). Root-caused 2026-07-29 ([#93](https://github.com/Phaazoid/Godoiosis/issues/93)) — **it is a gdUnit4 teardown bug, and it has nothing to do with the code under test.** Findings, each measured:
  - It is **not Godot and not Iosis**: the identical work driven by a plain `--script` SceneTree probe exits 0. It happens only inside the gdUnit4 runner.
  - It is **not fixed upstream**: reproduces unchanged on gdUnit4 **v6.2.0 stable** (the repo vendors `6.2.0-rc1`; the upgrade was tried and reverted — it changed 21 files and fixed nothing).
  - It reproduces from a **four-line suite that loads nothing and touches no game state**. The scenario-loading in `test_scenario_load_integrity.gd` was a red herring:
    ```gdscript
    func test_x() -> void:
        var item: EquippableData = null
        assert_bool(item is WeaponInstance).is_false()
    ```
    The check does not even have to *execute* — with the loop guarded so it never runs, it still crashes. So this is compile/parse-time, not runtime.
  - The trigger is a **(declared type, checked type) pair**, not a class: `EquippableData is WeaponInstance` and `Item is ChainswordWeaponInstance` crash, while `EquippableData is ChainswordWeaponInstance`, `EquippableData is RuneData` and `Resource is WeaponInstance` are clean. A `Variant` operand never crashes — one suite naming **all 115 Iosis classes** against a `Variant` is clean.
  - The signature at exit is always identical: ~141 leaked objects and **102 leaked scripts, every one of them gdUnit4's own**. Zero Iosis scripts leak; clean runs leak nothing at all.
  - It is **masked by running more suites**, which is why it only ever appeared in narrow runs. `run_tests.ps1 flow` was the original symptom and now exits 0 on its own, because #96 added a third suite to that folder.

  **No test result is ever affected** — gdUnit4 finishes counting and prints its verdict before the process dies. `run_tests.ps1` now reports that verdict (see the exit-code table above), so this no longer lies in either direction. Left as a known upstream quirk rather than chased further into gdUnit4's internal refcounting.
- **The FIRST failure ends that suite file — every later test in it is silently skipped.** First seen 2026-07-15 (#56); measured exactly 2026-07-29 (#103) with a three-case throwaway suite: make case 1 fail and the run reports `1 test cases | 1 failures` and `Executed test cases : (1/1)`; make case 1 pass and all three run. It is the runner, not your file — `GdUnitTestDiscoverer.discover_tests_from_gd_script()` finds all of them (worth checking with a `--script` probe if you suspect a discovery problem instead). Consequences:
  - A suite's printed test count is **not** proof the whole file ran, and "only 1 failure reported" does not mean only one test is affected.
  - After fixing a failure, **always re-run** rather than trusting the fix from reasoning.
  - **While falsifying a new suite, verify each case's red state one at a time** — rename the others to a non-`test_` prefix, or the first failure hides the rest and you learn nothing about whether they have teeth.
- **A case that relies on a precondition another case established can be defeated by shared state — and a shared-state bug is exactly what will defeat it.** Measured 2026-08-01 while falsifying `tests/weapons/test_weapon_family_seam.gd`: making `SpringspearWeaponInstance.ready` **static** reintroduces the #73 bug that whole seam exists to prevent, and the first draft of the suite **passed it**. A static survives between test cases, so the first case to spend it left every later `_fresh()` handing back an already-spent spear; those cases then took their baseline from the poisoned instance, "disturbed" something already disturbed, saw no change, and went green. Two rules fall out: **(1) assert your own precondition in the same case that depends on it** (the suite now calls `_assert_disturbed()` right after every mutation instead of trusting an earlier case), and **(2) never derive an expected value by re-constructing the object under test after mutating it** — snapshot the baseline first, because a freshly-made instance is only pristine if the bug you are hunting doesn't exist.
- **Per-family properties that are really BASE-class properties belong in one table-driven suite.** `tests/weapons/test_weapon_family_seam.gd` owns the three that are true of every `WeaponInstance` family — battle state never survives `copy_equippable()`, two instances track independently, and a family's verbs are inert on the others — plus the capture/apply round trip and the status-text scope rule. These used to be re-written inside each family's suite, which covered only the four families someone remembered and grew with every new one. **Adding family #8: add its row to `FAMILIES` and nothing else** — `test_every_weapon_type_declares_a_family_row` fails until you do, so the coverage cannot be silently skipped (same partition-law shape as `law/test_action_registry.gd`).
- **Content-scan catalogs can key off a name that changes.** `WeaponAttackCatalog` (and similar folder-scan catalogs) use `display_name` as the registry key, falling back to the resource's filename when `display_name` is unset. Authoring a real `display_name` for a previously-unnamed attack changes its catalog key — a test asserting the old filename-derived key breaks (happened 2026-07-22: Springspear's main attack, "Springspear" → "Stab"). Expect this to recur as the remaining weapon families get real content.

## Testing the game scene (game.gd / HoverPresenter / MainActionMenu)

**The game scene does NOT segfault in the runner.** That belief blocked [#114](https://github.com/Phaazoid/Godoiosis/issues/114) and is wrong: measured 2026-07-29, `Main.tscn` instantiates under gdUnit4, spawns a board, and dispatches clicks, with `0 orphans` and exit `0`. `tests/ui/test_game_scene_smoke.gd` is the working suite — copy its fixture.

Two things make it work, and both are easy to get wrong:

1. **Name the instanced root `Main` and add it to `/root`, not to the suite.** `game.gd` resolves the dev overlay by an *absolute* path (`get_node("/root/Main/DevOverlay")`), so under any other parent `dev_overlay` is null and `ScenarioManager.clear_board()` dies on `game.dev_overlay.unit_editor`. That error — not a segfault — is what made the scene look untestable.
   ```gdscript
   _main = (load("res://Scenes/Main.tscn") as PackedScene).instantiate()
   _main.name = "Main"
   get_tree().root.add_child(_main)
   await await_idle_frame()
   game = _main.get_node("GameContainer/GameView/Game")
   ```
   Free it in `after_test` with `remove_child` + `free` (not `auto_free`, which frees too late to keep `/root` clean between tests).

2. **Drive `_on_left_click` / `_on_right_click` directly — never real `InputEvent`s.** Godot does not deliver input in headless mode. Those two functions *are* the dispatchers; `_unhandled_input` only picks a cell and calls them, so nothing meaningful is skipped.

**A menu pick is not the same as setting `game_state` yourself.** `ActionMenuController` emits `cancelled` **before** `action_selected`, so `MainActionMenu._on_menu_cancelled` runs `game.clear_selection()` on the way *into* the mode you just chose. That ordering is precisely what caused #105 and #107 — and a test that jumps straight to `game.game_state = CHOOSING_MOVE` **cannot see either bug**. The first draft of this suite did exactly that and stayed green with #107 deliberately reintroduced. Go through the real sequence:

```gdscript
func _pick_menu_action(action_id: int, unit: Unit) -> void:
	var controller: ActionMenuController = null
	for child in game.get_children():
		if child is ActionMenuController:
			controller = child
	controller.cancelled.emit(controller)          # clear_selection() fires HERE
	controller.action_selected.emit(action_id, unit)
```

Falsified against the real regression: with #107 put back (`selected_unit = null` inside `clear_selection()`), `test_selection_survives_a_menu_pick` fails, `test_move_mode_queues_a_move_order` fails with 4 errors, and `test_attack_targeting_queues_an_attack_order` reports 0 attacks queued. All three pass once it is reverted.

> **A suite's printed test count is not proof the whole file ran** — a failure truncates the rest of that file (see the gotcha below). While falsifying, disable the earlier failing test to confirm the later ones have teeth too.

`tests/flow/test_mission_controller.gd` (31 cases) is the second suite on this fixture and the model for driving a *system* rather than the input layer: it clears the board with `scenario_manager.clear_board()`, then builds each situation cell by cell with `game.spawn_unit` and `zone_manager.paint_cell` so no test depends on the sandbox's contents.

`tests/ai/test_ai_turn_terminates.gd` (5 cases, [#103](https://github.com/Phaazoid/Godoiosis/issues/103)) is the third, and it is here for a reason worth knowing: **the hold-position filler that decides a group move's validity is queued by a game.gd signal handler** (`_on_squad_became_active` → `SquadManager.setup_hold_move_actions`), so a board built by `play/board_builder.gd` never grows the orders the bug lives in. That is why the Play API could not reproduce #103 — the same board and the same orders give a different validity answer headless. Reach for the real scene whenever plan *validity* is under test, not just input.

`tests/ui/test_tooltip_rendering.gd` (6 cases, 2026-08-01) is the fourth, and it is the one that shows what the fixture is *for*. It replaced `tests/law/test_tooltip_wrapping.gd`, a **source-scanning** law that read `Classes/ui/*.gd` as text and grepped each function for the token `UiText` — written because "Classes/ui/ has ZERO runtime coverage because the game scene segfaults inside the runner (#114)". That premise was false while `test_game_scene_smoke.gd` sat two folders away saying so; the suite contradicted itself in-tree for months. **When a suite's header explains why it had to do something unusual, check whether that reason is still true.**

Two things it teaches about writing a UI-layer suite here:

- **Populate before you assert.** A freshly spawned sandbox unit wears no armor and holds no abilities, so its longest tooltip is ~20 characters. A tree-walk over the default board finds only short text and passes no matter what the wrapper does. The suite dresses a unit in the *authored* content that caused the original regression (the Insulated Weave and its long granted-ability description), and `test_the_fixture_reaches_content_that_needs_wrapping` fails loudly if that stops being true — measured floors, not vibes.
- **Assert the outcome, not the mechanism.** It checks `UiText.wrap(t) == t` on every rendered tooltip (valid because `wrap` is idempotent, pinned by `tests/ui/test_ui_text.gd`), which means "already display-safe". Falsified two ways: a site with the wrap removed, and a site wrapping at the **wrong width** — the second is invisible to a source scan, since `UiText` still appears in the function.

`tests/flow/test_capture_action.gd` (15 cases, 2026-08-01) is the fifth, and it is on the fixture for a narrower reason: `CaptureAction.init()` reads `game.zone_manager` through the `MissionController`, and its re-validation clause only runs inside a real squad plan. Note what building it revealed about the order of operations — **a capture is a MAIN action, so queueing one locks the move option**, and you therefore cannot strand a capture by re-planning a move underneath it. Cancelling the move is the only way, which is why that is the case with teeth. Getting that backwards is what the first draft did, and the refusal it hit was the code being right.

One case in `test_ai_turn_terminates.gd`, `test_ai_turn_from_a_jam_terminates_every_turn`, costs **~12s** — by far the most expensive in the tree (~0.26s is typical). It runs three full `AIController.take_faction_turn` passes because #103's signature was *stability*, and `pan_to` is 2 real seconds per squad planned plus a 1s `BETWEEN_TURNS` timer per hand-off. Every other squad on that board is marked `has_acted` each turn precisely so it is skipped and not panned to; don't remove that or the case triples.

**Falsify with mutations, and take the baseline from git.** That suite was checked by breaking `MissionController` seven ways — one per piece of doctrine — and confirming each was caught by the test that claims to own it. Two traps, both hit on the first attempt:

- **A crashed mutation run leaves the source mutated.** The next run then read *that* as its "original" baseline and silently restored a broken file, making every later result meaningless — and it wrote the mutation into the repo. Always `git checkout -- <file>` to get the baseline *and* to restore, never a string captured from the working file.
- **`$ErrorActionPreference = 'Stop'` plus `2>&1` on `godot.exe` aborts the run** on Godot's harmless `ObjectDB instances leaked at exit` warning, because PowerShell 5.1 wraps native stderr in ErrorRecords. Don't redirect a native exe's stderr here.

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
