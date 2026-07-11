# 5 — Drift sweep (SPD ghosts, WIND/AIR, stale doc text)

**✅ EXECUTED 2026-07-07 by Fable 5, same session it was written — kept for the record.** Outcomes: **AIR** ruled canonical by the dev (primaries Earth/Air/Fire/Water + Aether/Alkahest; "wind" reserved for attack names — the Wind Blast reaction demonstrates); SPD ghost swept from `tests/util/test_devwidgets.gd` and scenario `.tres` verified already clean (the audit's `.tres` claim was stale); stale claims fixed across the design + top-level + story docs. Ledger: [grill-queue.md](../design/grill-queue.md) → Drift fixes.

**Size S · mostly Claude-direct (tests/docs/`.tres` data) · no gameplay-code typing expected · safe to run before anything else.** Source: [grill-queue.md](../design/grill-queue.md) → "Drift fixes — no decisions needed".

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first (especially the sharp-edges section on .tres serialization), then docs/design/grill-queue.md ("Drift fixes" section). This is a cleanup session: NO design decisions, NO new features. Docs in docs/design/ are canon.

Goal: retire three pieces of drift the 2026-07-05/06 grills left behind.

1. GHOST SPD RETIREMENT. There is no SPD stat and never will be (DEX owns the role — docs/design/stats.md "Open forks"). Grep the whole repo (scenario .tres files, tests/, fixtures, comments) for SPD / "Speed" used as a stat. For each hit, judge: if it's a stale stat KEY in saved data or fixtures, remove or re-key it; if it's a comment, fix the wording. SHARP EDGE: .tres stat dictionaries serialize enum keys as ints — a "SPD" ghost is likely an old string key or a stale int from a pre-migration enum. Show the user every .tres diff before saving (data migrations get sign-off; remember the #7 fallout story in CLAUDE.md). Tests you may edit directly; run the suite after.

2. WIND vs AIR. One word must win before content authoring multiplies it. Check Classes/elemental/Elemental.gd — whatever the Element enum actually says is the incumbent. Propose the code's word as the winner (renaming an enum member is safe — only its int serializes — but sweep display strings and docs). Ask the user for a one-line confirmation, then sweep docs/design/ (elemental-system.md, elemental-interactions.md, terrain.md, etc.) and any UI strings to the winning word.

3. STALE DOC TEXT. docs/design/squad-system.md "Known gaps" still claims death handling is undesigned — the #33 lifecycle build superseded it. Rewrite that line to point at the built lifecycle (Unit.LifecycleState, docs/design/will-and-death.md "Implementation status"). While in there, scan the same doc for other claims the lifecycle build outdated.

Do NOT: create a temperament owner doc (parked — it rides the recovery grill), sweep the scratchpad Inbox (separate /scratchpad-sweep skill), or touch gameplay code beyond what the SPD/element sweep strictly requires (if a Classes/ file needs an edit, deliver it as a typed code block for the user).

Done when: repo-wide grep for the dead SPD stat comes back clean, one element word survives everywhere, squad-system.md tells the truth, tests green, changes committed.
```
