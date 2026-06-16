# 3 — Will / downed lifecycle

**Lane B (you type the gameplay code) · AFTER the co-dev fork chat · don't run concurrently with Prompt 2** (both touch unit.gd + SquadManager.gd). Build the unblocked half; gate the rest.

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first, then docs/design/will-and-death.md IN FULL (the deterministic stakes ladder, downed state, rescue sub-game, the Law #2 requirement, and the OPEN FORKS), and docs/design/resolution-pipeline.md IN FULL (Will/death is the "Will stage" of that pipeline — R7: it reads the elementally-resolved damage). Read the real seams: unit.gd (die() emits unit_died then queue_free — the mechanical floor; unit_instance holds HP), UnitInstance.gd (the persistent store; already advertises "limb loss" storage — the natural home for Will IF it persists), Managers/SquadManager.gd (handle_unit_death), Managers/TurnManager.gd (phase signals, for the rescue countdown).

Goal: Build the UNBLOCKED part of the Will/death design — the unit lifecycle state machine and the rescue sub-game — and prepare the blocked part for a decision.

Collaboration: GAMEPLAY code — user hand-types. Complete typed code blocks + file anchors + the why; read the real file after each step.

CRITICAL law note: #1 — the stakes ladder is DETERMINISTIC by design. The user once floated a random "going-down" roll and was deliberately talked out of it (finite Will is the deterministic punishment instead). Do NOT reintroduce randomness; if it resurfaces, point back to Law #1 and will-and-death.md. (Aside: UnitInstance.level_up() currently uses randi_range for leveling — that path is benched by the no-leveling decision; don't build on it, and see the backlog item to reconcile it.)

Two halves — build the first, gate the second:

UNBLOCKED (build now):
- Unit lifecycle state machine: active -> downed -> dead, layered on the existing unit_died floor (today die() goes straight to queue_free; insert a DOWNED state before death). A downed unit can't move or attack and renders as downed.
- Enemies DEPRIORITIZE downed units — leave a clean hook (full AI is a separate session).
- Rescue sub-game: a downed unit must be reached by a squadmate within X turns or it's lost/captured. Build the countdown as a GENERIC "turn-scoped timed state" that ticks on turn-phase change (use TurnManager's phase signals) — the deferred elemental over-time (EoT) layer will reuse the exact same mechanism, so don't make it rescue-specific.
- STUB the rung selector: "would-be-fatal hit -> downed (unless overkill -> dead)". This builds the STATES and TRANSITIONS without the Will math, and gives the resolution pipeline its Will-stage seam.

BLOCKED on a dev/co-dev decision — do NOT build past this; instead help the user write a one-page decision brief:
- The Will resource (bar, build/spend) and full rung selection (down vs maim vs overkill vs Crisis) depend on Fork 1 (persist-vs-reset) and Fork 2 (individual-vs-squad), which set the DATA MODEL (resolution-pipeline.md: persist -> UnitInstance, reset -> transient Unit), plus Fork 3 (downed-attack kill-vs-maim).
- Flag the cross-system constraint (resolution-pipeline.md R7): the number the ladder judges "fatal?" against is the ELEMENTALLY-RESOLVED damage, so the Will stage runs AFTER the elemental stage in the same plan-time pass. The Will outcome is the same derive-from-plan / surface-in-preview (Law #2) / replay family as counters and elemental — it plugs into the SAME pipeline, not a parallel one.

Done when: a unit taking a lethal hit enters DOWNED (not freed) via the floor; downed can't act; a rescue countdown ticks and resolves (rescued vs lost); and the user has a one-page brief on Forks 1-3 for the co-dev. No Will bar yet.

OUT of scope: limb-loss/maiming, Crisis Mode, Will abilities (Iron Will, Intimidation...), and the Law #2 down/maim/lethal preview number (that's the blocked half).
```
