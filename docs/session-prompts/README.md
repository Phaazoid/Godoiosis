# Session prompts — parallel roadmap work

Copy-paste prompts for spinning up fresh Claude sessions against the roadmap's highest-priority items. Each is written to be **actionable cold** (same bar as `docs/BACKLOG.md`): a new session has only `CLAUDE.md` + memory auto-loaded, so each prompt names what to read first.

## How these parallelize

You hand-type all gameplay code, so "4 simultaneous sessions" isn't the real shape. Two lanes:

- **Lane A — Claude-owned, truly parallel, hands-off:** [1 — test harness](1-test-harness.md) and [4 — GitHub migration](4-github-migration.md). Different file regions (`tests/`+`addons/` vs GitHub), no gameplay code. Safe to run in the background. Only overlap is `BACKLOG.md` edits at the very end.
- **Lane B — you type, serial with each other:** [2 — elemental v1](2-elemental-v1.md) then [3 — Will/downed lifecycle](3-will-downed-lifecycle.md). **Both heavily touch `unit.gd` and `SquadManager.gd`, and you're the single typist** — don't run them at once. Do elemental first (it's unblocked, and it builds the resolver/preview pattern Will reuses); Will waits behind the co-dev fork chat anyway.

Recommended: run 1 + 4 hands-off now; drive 2 as your main session; hold 3.

## Shared foundation (read before 2 and 3)

[`docs/design/resolution-pipeline.md`](../design/resolution-pipeline.md) is the keystone contract (R1–R8) that elemental and Will **both** plug into. Build them as stages of one pipeline, not two private systems. Prompts 2 and 3 reference it.

## Environment note

In at least one of the dev's environments, **Godot is not on PATH** (only git is). A session that needs to run the engine (the harness's first green run) must be launched where Godot is available, or hand that step back to the dev.
