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

`run_tests.ps1` runs Godot headless against gdUnit4 and returns the suite's exit code. It defaults to `C:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe`; override with `$env:GODOT_BIN`. The raw command it runs:

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

**Exit codes (from gdUnit4's `report_exit_code`):** `0` = clean pass · `100` = test failures **or** caught engine errors (e.g. a `push_error`/runtime error during a test) · `101` = passed but **orphan nodes** were detected. Treat anything non-zero as "fix it" — see orphan-node hygiene below. **And note `0` can lie too**: gdUnit4 reports it when zero tests ran, which is why the runner has a separate zero-cases guard (next block).

> **The runner reports gdUnit4's verdict, not the process exit code** (changed 2026-07-29, [#93](https://github.com/Phaazoid/Godoiosis/issues/93)). Godot can die with an access violation *while tearing the engine down* — after every test has run and been counted — which made a clean pass report failure. `run_tests.ps1` now parses gdUnit4's own `Exit code: N` line and exits with that, printing a loud yellow NOTE when the process disagreed. This is strictly **more** truthful than trusting the process, in both directions:
>
> | situation | process | runner exits | how you see it |
> |---|---|---|---|
> | clean pass | 0 | **0** | normal |
> | clean pass + teardown crash | `-1073741819` | **0** | yellow NOTE naming #93 |
> | real test failure | 100 | **100** | the failures themselves |
> | real failure + teardown crash | `-1073741819` | **100** | the failures themselves |
> | crash *before* gdUnit4 reports | non-zero | **non-zero** | red "never reported a verdict" |
> | **suite fails to LOAD** (parse error in a class it uses) | 105 | **non-zero** | red "ZERO test cases executed" |
>
> The last two rows are the safety properties, and they are two different doors into the same room. A run that dies mid-flight produces no verdict line, and **no verdict is treated as failure**. A run whose suites never loaded produces a verdict of `0` that is *honest but meaningless* — nothing failed because nothing ran — so **zero executed cases is also treated as failure** ([#146](https://github.com/Phaazoid/Godoiosis/issues/146), fixed 2026-08-09). Together they mean the #93 override can only ever apply when its own premise holds: that every test really did run and get counted.
>
> **Why cases-executed and not the segfault exit code:** a #93 teardown crash happens *after* reporting, so it always prints `Executed test cases : (N/N)` with N > 0; a load failure never gets there. That discriminator is platform-independent, which matters because CI has to make the same call in bash.
>
> **Falsifying these guards** — do this rather than trusting the table, it is how #146 was found in the first place:
>
> ```
> # 1. break a production class some suite depends on
> #    append this line to Classes/ui/ModalCard.gd:   func _x( -> void:
> powershell -File tests\run_tests.ps1 res://tests/ui/test_modal_card_scaffold.gd
> #    -> MUST exit non-zero. Before #146 it exited 0 with "No test cases found" + "Exit code: 0".
> # 2. put it back
> git checkout -- Classes/ui/ModalCard.gd
> ```
>
> Note a parse error in a **test** file behaves differently and was always caught: the run dies before any verdict is printed, so the no-verdict guard fires. The hole was specifically *test file fine, production dependency broken*.
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

8. **The tuning razor (dev rule, 2026-08-10 — #118 and the sweep that followed): a test may not break when a NAMED tunable constant moves; it may break when a function body changes.** *"I don't want any tests that test what these values are, only that they work."* In practice:
   - **Never hard-code a knob's current value** into an expectation, an input whose *meaning* is its position relative to a threshold, or a tick/loop count. Read the constant (`Squad.MEMBER_LDR_COST`, `Stats.DEX_MOV_MID_MAX + 1`, `TerrainStateManager.STATE_DURATIONS[state]`), derive the expectation from it, or assert a relationship (`is_greater`, before-vs-after) instead of a number. `contains(str(CONST))` is the pattern for status strings.
   - **A fixture that inherits a tunable default is a trap** — author the knob-dependent input explicitly (the cohesion suite's `FIXTURE_COH`), or derive it (`2 * Squad.MEMBER_LDR_COST`). Where a case's premise depends on a knob relationship, **assert the premise** so a retune fails loudly as a fixture problem, not silently as a phantom mechanism bug.
   - **What stays literal:** values in function *bodies* (band rung heights, the MOV floor of 1) — retuning those means editing the mechanism, where a red test is ordinary regression semantics — and authored fixture content a test constructs itself.
   - Verified by **retune matrix** (2026-08-10): `CON_DEF_FACTOR`, `STATE_DURATIONS`, `MEMBER_LDR_COST`, and the band thresholds were each moved and the full suite stayed green. `JOBLESS_MOV_BASE` is the known exception: the AI/cohesion **board-geometry fixtures** are authored relative to global mobility (what's "out of reach" at MOV 4 isn't at MOV 6), so a mobility retune legitimately demands a fixture pass — the same pass the game's real scenario boards would need.

9. **The content razor (dev rule, 2026-08-15) — rule 8's sibling, for the other thing the dev edits without touching code. A test may LOAD authored content to exercise a real path; it may not ASSERT anything about what that content contains.** *"Authored content shouldn't be pinned, and level geometry, not to mention contents, units, objectives, all of it is authored."* Rule 4 says build content ad hoc and never load a `.tres` — that is the rules layer, where the content IS the subject. `tests/presentation/` is the **declared exception**: those suites load a real mission on purpose, because the bug class they hunt (a wire that never fires — #103, #222) only appears on the real load path. Loading it is the point; asserting on its contents is the error.
   - **What went wrong (#273 + `b057f6e`, 2026-08-15).** `#273` gave elevation the ability to render; a *level edit* then painted eight tiles onto `Level_1` and reddened a case about the board-swap funnel. Measured on the way in: adding three raised tiles to Prolog took the presentation area from **165 executed / 1 failure to 116 executed / 7 failures** — four suites reddened at their first content-dependent case, and because a failure aborts the rest of its own suite, three painted tiles cost **49 test cases**.
   - **Never pin** a cell coordinate, an elevation, a cell *count*, a footprint size, or a roster size. `used_cells.size() == used_cells.size()` across the 2D/3D boards was an equality that held only while every board was flat — one raised cell writes a whole column.
   - **Derive from the seam the code under test uses**, so a repaint moves the expectation and the assertion together: `BoardPicker.column_tops_from(board)` (keyed by column — its keys are the footprint), `BoardSpace.surface_point(cell, heights)` (where `UnitMirror` seats a sprite), `board_heights.elevation_at(cell)` (the level `OverlayMirror` marks at), `game.get_move_range(...)` (where a unit may actually be ordered).
   - **A precondition on content is a non-vacuity message, never a magic threshold.** `live.size() >= 8  # Prolog fields 10` breaks on a re-cast; `> 0` with *"the board spawned nobody; parity over an empty roster proves nothing"* says the same thing and survives.
   - **On a board with hills, "can I click this cell" stops being a UI-overlap question.** A taller column shadows the cell behind it from a pitched camera and the click lands on the blocker, so clickability is asked of the real picker (`_click_lands_on` in `test_input_bridge.gd`). Likewise a unit on a terrace with no ramp off it genuinely cannot move — a case needing a mover must *find* one rather than assume the first one qualifies.
   - Verified by **content matrix** (2026-08-15): three raised cells plus a ramp were painted into `Prolog.tres` and `tests/presentation` ran **179/179 green, identical to the flat board**. The same edit against the pre-sweep suite is the 116/7 measurement above.
   - **A PLAYER SETTING IS AUTHORED CONTENT TOO (dev, 2026-08-21, [#449](https://github.com/Phaazoid/Godoiosis/issues/449)).** `user://settings.cfg` is authored by whoever is playing — the dev included — so a case that reads a setting-driven surface without saying which state it is in is pinning content exactly as much as one asserting a cell coordinate. It cost the same way, too: `test_overlay_mirror` asserted *"the hover-raised crown clears"* as unconditional, `ALWAYS_SHOW_SQUAD_RINGS` had made it conditional, and the case redded **only on the machine that had switched the setting on** — taking the nine cases after it out of the run. Two halves, and neither alone is enough. **The store is hermetic by construction**: a headless process honours nobody's preferences (`PlayerSettings`/`Experiments` `_static_init`), so the suite reads DEFAULTS and *cannot* inherit a cfg — the per-suite discipline this replaced was unenforceable, and 22 scene suites had never followed it. **And a suite still DECLARES its branch**, because a setting that forks a marker's lifecycle forks the cases that pin it: the OFF branch is pinned in `test_overlay_mirror`, the ON branch next door in `test_standing_squad_rings`, each saying so. Pin the *fork*, never one side of it by accident.

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
- **A test that ends in the same frame it queued a free reports FALSE orphans** (measured 2026-08-09, [#162](https://github.com/Phaazoid/Godoiosis/issues/162)). `ScenarioManager.clear_board()` does `remove_child` *then* `queue_free` — deliberately, so same-frame respawns don't see dying units in occupancy checks — and `game.spawn_unit`'s refusal paths do the same. Between those two calls and the next frame, the node is **parentless and pending**, which is exactly what the orphan monitor counts. gdUnit4 6.2.0 samples orphans right after `after_test()` with no frame boundary in between, so any suite whose test bodies clear the board reported dozens of "leaks" that were nothing of the kind — 400 of them across three suites, all of which vanish after a single idle frame (`Node.print_orphan_nodes()` printed nothing). **The fix is one `await await_idle_frame()` at the top of `after_test()`**, which the three real-game-scene suites now carry. It does not blind the check: a genuine leak survives any number of frames and still reports — falsified by planting an unparented `Node.new()` and confirming it was still caught. If you write a suite that clears or reloads the board, copy that teardown.
- **RefCounted reference cycles leak** (no GC). A volley's `AttackAction.volley` array references every sibling including itself, so a volley is a self-referential cycle that never frees — the volley suite breaks it in `after_test` (`attack.volley = empty`). See findings; this is a real (small) gameplay leak too.
- **The engine can segfault on SHUTDOWN, after a clean pass** (exit `-1073741819` = `0xC0000005`). Root-caused 2026-07-29 ([#93](https://github.com/Phaazoid/Godoiosis/issues/93)) — **it is a gdUnit4 teardown bug, and it has nothing to do with the code under test.** Findings, each measured:
  - It is **not Godot and not Iosis**: the identical work driven by a plain `--script` SceneTree probe exits 0. It happens only inside the gdUnit4 runner.
  - It is **not fixed upstream**: reproduces unchanged on gdUnit4 **v6.2.0 stable**, which the repo now vendors (bumped from `6.2.0-rc1` on 2026-08-09 alongside [#162](https://github.com/Phaazoid/Godoiosis/issues/162) — the bump fixes nothing here and was never expected to; the verdict-parsing below is still what makes the exit code truthful).
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

1. **Instantiate the whole of `Main.tscn`, don't hand-build a partial tree.** `game.gd` resolves the dev overlay *relative* to Game (`../../../DevOverlay` — up through `GameView` and `GameContainer` to `Main`), so the sibling structure is what matters; a fixture that reparents `Game` alone gets a null `dev_overlay`, and `ScenarioManager.clear_board()` then dies on `game.dev_overlay.unit_editor`. That error — not a segfault — is what made the scene look untestable. **The path was absolute (`/root/Main/DevOverlay`) until 2026-08-14**, which is why the older fixtures also name the root `Main` and add it to `/root`; that ritual is now harmless rather than required. To test the *absent* overlay deliberately, `free()` the `DevOverlay` node before entering the tree — mis-naming the root no longer produces a null (see `test_game_scene_without_dev_overlay.gd`).
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

One case in `test_ai_turn_terminates.gd`, `test_ai_turn_from_a_jam_terminates_every_turn`, used to cost **~12s** — by far the most expensive in the tree — because it runs three full `AIController.take_faction_turn` passes (#103's signature was *stability*) and every real-time pause on that path was paid in full: `pan_to` at 2 real seconds per squad planned, plus a 1s `BETWEEN_TURNS` timer per hand-off. **Fixed 2026-08-10 by #118**: playback pauses now route through `Pacing.beat`, which returns immediately in a headless run, and `pan_to` snaps instead of tweening — the whole `ai` area went **19.0s → 7.5s**. Every other squad on that board is still marked `has_acted` each turn, but that is now fidelity to the reported scenario rather than a runtime dodge.

**Falsify with mutations, and take the baseline from git.** That suite was checked by breaking `MissionController` seven ways — one per piece of doctrine — and confirming each was caught by the test that claims to own it. Two traps, both hit on the first attempt:

- **A crashed mutation run leaves the source mutated.** The next run then read *that* as its "original" baseline and silently restored a broken file, making every later result meaningless — and it wrote the mutation into the repo. Always `git checkout -- <file>` to get the baseline *and* to restore, never a string captured from the working file.
- **`$ErrorActionPreference = 'Stop'` plus `2>&1` on `godot.exe` aborts the run** on Godot's harmless `ObjectDB instances leaked at exit` warning, because PowerShell 5.1 wraps native stderr in ErrorRecords. Don't redirect a native exe's stderr here.

## Testing the presentation stack (`LookDev.tscn` is a FIXTURE, not a scratch scene)

`res://Scenes/LookDev/LookDev.tscn` is the fixture five suites stand on — `test_board_overlays`,
`test_board_picker`, `test_camera_rig`, `test_look_dev`, `test_walk_demo`. Its folder name says
scratch and its header used to agree; both were wrong, and [#393](https://github.com/Phaazoid/Godoiosis/issues/393)
(2026-08-19) said so in canon rather than moving the scene. **Renaming a node in it, deleting a prop,
or re-parenting the camera rig reds those five suites**, and the game as well: `Battle3D.tscn` loads
its `lookdev_meshlib.tres`, `BoardMirror`/`BoardOverlays` read textures out of `Art/LookDev/`, and
the rig itself is now `Classes/presentation/CameraRig3D.gd` — shipping code that merely used to live
in that folder.

Two consequences for writing cases against it. Its **moods** are `LookPreset` files resolved by name
through `LookKnobs`, not a table in `look_dev.gd`, so a case about them must not assume a local
constant — and `_ready` applies `Day`, so the scene's live post-stack values come from
`Resources/LookPresets/Day.tres` rather than from what `LookDev.tscn` authors. Its **help label** is a
full-rect `CanvasLayer` over the viewport, which is why `test_camera_rig` drives the rig's own
`_unhandled_input` rather than parsing events into the tree.

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
| `squad/test_counters.gd` | C1–C7 via `can_counter` / `choose_counter_target` / `calculate_reactions_for_squad` | Reaction rules |
| `squad/test_reaction_heal.gd` | C8–C10 (#148) — a healer's reaction heals its own side, never the attacker; below-max is a filter and lowest-HP the sort; downed allies skipped; every HP read off the threaded hypo; heals ordered after strikes | Reaction rules |
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
