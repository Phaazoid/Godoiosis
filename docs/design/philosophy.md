# Design Philosophy — Gameplay Axioms

**Status: NORTH STAR (short, stable).** Distilled 2026-06-17 (issue #32) from `Game Mechanics/Gameplay Philosophies`, `Intended Player Behavior/*`, and `Home`. These are the *why* behind the non-negotiable **Laws** in `../../CLAUDE.md`; when a design choice is unclear, it should serve these.

## The pitch (one line)

A turn-based tactical RPG of **steampunk mechanisms and alchemic runes** — in the Fire Emblem / FFT / XCOM / Advance Wars lineage, set apart by **squad combat** and a deterministic **elemental combinatrix**.

## Axioms

1. **Combat is worth watching.** Battles should be interesting to *watch* resolve — the player sets a plan and enjoys its execution; they shouldn't have to micromanage every beat.
2. **Influence, then watch.** The player shapes the outcome *before* execution (the plan) and, in places, *during* it (mid-battle decisions / charges) — but is comfortable letting a planned turn play out.
3. **Emergent, within predictable bounds.** Outcomes emerge from interacting systems (squads × elements × terrain) yet stay **inside bounds the player can foresee** — *"it won't be a surprise if someone dies."* This is the design reason behind **Law #1 (no randomness).**
4. **The preview never lies.** Whatever the game shows about how a turn will unfold must match what happens (**Law #2**). Hidden information is allowed only through *explainable* means — e.g. a **perception stat** that reveals enemy detail, or a telegraphed-but-undirected overwatch — never by the preview asserting something false. (See the deferred battle-preview thread in [wiki-triage.md](wiki-triage.md).)
5. **Go wide, not tall.** No basic leveling. Units grow by **specializing across systems** — squads, Will, weapon proficiency, aura, jobs — rarely by raw stat inflation; most effective stats stay small. (See [progression.md](progression.md); the anti-grind rubric G1–G4 that operationalizes this lives in [stats.md](stats.md).)
6. **Respect the player's time.** A standing genre problem (FE) is late-game levels ballooning in length. Iosis wants **bounded, resumable sessions** — design encounters and the **Bounty Board** (mission contracts; renamed 2026-07-06 from the wiki's "job board" to avoid colliding with the unit *jobs* layer) so play fits a sitting.

## What these rule out

Crits, hit/miss, dodge %, and "surprise" deaths (Axiom 3 + Law #1). Mandatory grinding (Axiom 5). Previews that mislead (Axiom 4 + Law #2).

> **Scope note:** Law #1 governs the **battlefield.** Meta-progression *outside* combat may use randomness — e.g. a random menu of upgrade choices when a proficiency levels (see [progression.md](progression.md)). The turn never rolls dice; the campaign layer may.

## Sources & cross-refs

Wiki: `Gameplay Philosophies`, `Intended Player Behavior/{Tactics, Session Length}`, `Home`. See `../../CLAUDE.md` (the three Laws), [progression.md](progression.md), [squad-system.md](squad-system.md).
