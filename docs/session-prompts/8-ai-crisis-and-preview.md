# 8 — AI Crisis stances + CRISIS preview + downed deprioritization

**Size S · gameplay code (user types) · anytime after 6 · a good short session between the big ones.** Source: [will-and-death.md](../design/will-and-death.md) → "AI Crisis policy" + [resolution-pipeline.md](../design/resolution-pipeline.md) R9 choice-points. Also closes the #29 leftover "AI ignores downed".

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first (collaboration contract: user hand-types gameplay code — complete typed code blocks + anchors + why; Laws #1/#2/#3). Then read as canon: docs/design/will-and-death.md (Crisis Mode + "AI Crisis policy" — grilled 2026-07-04), docs/design/resolution-pipeline.md (R9: choice-points; ENEMY Crisis never BREAKs because stances are deterministic). Code to read: Classes/ai/ (AIArchetype registry + the three archetypes), game.gd _offer_pending_crisis / _offer_crisis (the AI faction gate), Classes/actions/PlanResolver.gd + ResolvedOutcome.gd (Lethality enum + how MAIMED threads to icons), Classes/ai/AITactics.gd (target selection), tests/ai/.

Goal: replace the shipped auto-accept-for-all stopgap with per-archetype Crisis stances, make the preview Crisis-aware (Law #2 debt), and stop the AI wasting hits on downed units.

1. STANCES. Every archetype declares its Crisis stance at authoring time: RUSHDOWN = always accept; HOLD = never; SENTRY = never. Put the stance on the archetype definition (enum or bool on AIArchetype's registry entry — follow the existing registry pattern), and route the AI-side Crisis decision through it instead of blanket auto-accept. The full-Will eligibility gate is unchanged — stance only decides accept/decline WHEN eligible. The balance lever stays authored enemy WIL (no code).

2. CRISIS-AWARE LETHALITY PREVIEW (Law #2 — the queue icon must not lie). A would-be-down on a Crisis-ELIGIBLE enemy whose stance is ALWAYS must preview as CRISIS (they stand back up surged), not DOWNS. Add Lethality.CRISIS to ResolvedOutcome, predict it in PlanResolver (eligibility = full Will + archetype stance — both deterministic, so the resolver predicts it EXACTLY; R9: enemy Crisis is never a BREAK), and surface a distinct queue icon + hover text. For PLAYER units the accept is a live choice — R9 marks it an assumed branch; the icon may show "down (Crisis possible)" — keep it honest, minimal UI is fine. If no CRISIS icon asset exists, ask the user for one or reuse-with-tint; don't silently ship a lying icon.

3. AI DEPRIORITIZES DOWNED. Downed units rely on the AI deprioritizing them, not on invulnerability (fork 3: attacking a downed unit = kill is LEGAL, just not preferred). In AITactics target selection, prefer ACTIVE targets; fall through to downed only when no active target is reachable. Keep it a preference, not a ban.

Do NOT touch: the BREAK banner (visual-clarity umbrella #44), player-side Crisis flow, Will costs/gates, Balanced archetype (separate #29 leftover — note it, skip it).

Done when: tests/ai/ covers each archetype's stance firing (rushdown surges, hold/sentry take the down), a planned lethal hit on a full-Will RUSHDOWN enemy shows CRISIS in the queue and resolution matches the preview, downed units are only targeted when nothing active is in reach, suite green, CLAUDE.md AI-archetype paragraph updated, committed.
```
