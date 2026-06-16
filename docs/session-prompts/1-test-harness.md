# 1 — Test harness + invariant battery

> **✅ STATUS: COMPLETE (2026-06-16).** gdUnit4 installed and green; Tier-1 + Tier-2 + Law guards all pass (33 cases, 0 orphans, exit 0). Canonical docs: `tests/README.md` (run + fixtures + findings) and the BACKLOG "Recently completed" entry. The prompt below is kept as the historical brief / for anyone extending the suite (e.g. attack-pattern geometry tests, more Law guards, or Phase-2 elemental coverage).

**Lane A (Claude-owned) · run now, hands-off · no dependency** — but the first green run needs a Godot-available environment (see env note). Pairs with: protects the seams Prompt 2 refactors.

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. CLAUDE.md and the project memory auto-load — read CLAUDE.md first, then docs/design/squad-system.md and the "Test harness + invariant tests" item in docs/BACKLOG.md.

Goal: Stand up the test framework and pin the SETTLED squad spec as executable invariant tests, so nothing regresses while elemental/Will work churns the same files (SquadManager, AttackAction, unit.gd).

This is Claude-owned scaffolding — tests/ and addons/ are in your standing edit exception (CLAUDE.md collaboration contract). You may install the addon, enable the plugin in project.godot, and write tests directly. Do NOT edit gameplay code (Classes/, Scenes/, game.gd); if something is hard to test, record it as a finding rather than refactoring it.

Context already known (verify, don't re-derive):
- **gdUnit4 is ALREADY installed and green** (vendored to addons/gdUnit4, plugin enabled, Tier-1 verified 7/7 on Godot 4.6). This prompt now covers the REMAINING work: Tier-2 node-fixture suites (I1-I7, C1-C7, volley) + the two Law guards. Read tests/README.md for the verified workflow + gotchas first.
- Run tests headless via `tests/run_tests.ps1` (or the raw command in tests/README.md). Godot 4.6 console exe: C:\Godot\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe. After adding any new gameplay class_name, run a one-time `<exe> --headless --path . --import` so global classes register.
- The hard part is fixtures: Unit instances come from Scenes/unit.tscn (needs a UnitData); SquadManager has manager deps (overlay_manager, grid) so isolating it needs care. Build a tests/support/ helper (make_unit() + minimal board) FIRST, then write the suites.

Steps:
1. Pick a runner. Default to gdUnit4 (Godot-4-native; parameterized tests fit the numbered batteries) unless the user prefers GUT — confirm before installing.
2. READ the actual classes before asserting anything: Squad.gd, Managers/SquadManager.gd, unit.gd, UnitInstance.gd, Actions/AttackAction.gd, CounterAttackAction.gd. Find the REAL way units/squads get instantiated — a Unit is a Node2D with @onready components and a scene; figure out how to stand one up in a test (gdUnit4 scene runner) before writing node-dependent tests.
3. Tier the work so you validate the harness before fighting node setup:
   - TIER 1 (pure logic, no scene): GridUtils, AttackPattern geometry, ManhattanRangePattern. Prove the runner works here first.
   - TIER 2 (needs Unit nodes): squad invariants I1-I7, counter rules C1-C7, volley semantics. Each test tagged to its spec ID.
4. Add two LAW-level guards that protect every future feature:
   - Determinism (Law #1): run the same plan twice -> identical result.
   - Preview==execution (Law #2): a reusable helper that snapshots a plan's previewed outcome, executes, asserts execution matched. A thin version now pays off the moment elemental/Will plug in (see docs/design/resolution-pipeline.md R3).
5. Green suite. Add tests/README.md (how to run: editor + headless CLI). Update the BACKLOG item to DONE with a pointer.

Done when: the suite runs green (observed, not assumed) and I1-I7 / C1-C7 / volley are each pinned. Flag any invariant the current code violates as a finding for the user (e.g., the known I2 disband_squad wording drift already in BACKLOG) — don't change gameplay code to satisfy a test without the user.
```
