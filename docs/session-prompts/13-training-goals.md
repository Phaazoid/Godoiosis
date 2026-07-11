# 13 — Training goals: the anti-grind learning machinery

**Size M · gameplay code (user types) · AFTER 9 + 10 (its consumers: job abilities + weapon proficiency) · LAST in the series.** Source: [progression.md](../design/progression.md) (the capped anti-grind machinery) + [jobs.md](../design/jobs.md) → "The linked trio" (training goal = the verb). One learning system for jobs, weapon proficiency, and aura.

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first (collaboration contract: user hand-types ALL gameplay code — complete typed code blocks + anchors + why; anti-grind is a design LAW here, not a vibe). Then read IN FULL as canon: docs/design/progression.md (the training-goal / momentum / caps machinery — this is the spec; if the mechanism you need is NOT specified there or in jobs.md, STOP and ask the user rather than inventing — parts of this layer may still be direction-not-spec) and docs/design/jobs.md ("The linked trio": a job's ability pool is a MENU of training goals; each ability defines its own reps; momentum, bench trickle, per-mission caps all inherited; pause-never-reset — accrued progress persists across job swaps, only the momentum RATE changes; temperament biases rate never access, and temperament itself is PARKED — leave a seam, build nothing). Code to read: Classes/units/UnitInstance.gd (per-ability progress scaffold from prompt 9, proficiency stub from prompt 10), the jobs code, game.gd + Classes/flow/TurnManager.gd (where a mission ENDS — see the dependency note below).

DEPENDENCY NOTE: training awards settle at mission end, and win/loss detection is a known #29 leftover that may not exist yet. If there is no mission-end seam, build the MINIMAL one (a dev-triggered "end mission" that runs settlement) and file the win/loss issue separately — do not build victory conditions inside this session.

Goal: the learning loop — deterministic reps in, capped progress out — growing BOTH job-ability progress and weapon-family proficiency. Numbers are placeholders -> named constants, "# playtest-tunable". Terse comments.

1. TRAINING GOAL state: the per-ability progress dict from prompt 9 becomes live — each AbilityData defines its own rep requirement + what counts as a rep (deterministic, observable in-battle events ONLY: hits landed with the family, rescues performed, cells moved... start with 2-3 rep KINDS as an enum, append-only). Weapon proficiency: same machinery, reps grow the per-family int from prompt 10.

2. THE ANTI-GRIND CAPS (all from progression.md — verify exact shapes there): per-mission progress caps (a mission contributes at most N reps toward any goal — repetition past the cap earns nothing, killing the grind incentive); MOMENTUM (progress rate is higher for the MAIN job's goals than subs'); BENCH TRICKLE (benched units accrue a small trickle — the between-battle task-assignment layer is PARKED, so trickle is a flat constant for now with a seam comment).

3. PAUSE-NEVER-RESET: swapping jobs freezes un-slotted goals' progress exactly where it stands; re-slotting resumes. Test this explicitly — it is the momentum doctrine's core promise.

4. SETTLEMENT: reps tally during battle (transient side), settle into UnitInstance progress at mission end (persistent side — the #8 seam). Crossing a goal's threshold UNLOCKS the ability into the known set (live kit picks it up per prompt 12's rules). Surface progress in the inspect panel + dev editor (read-only bars are fine).

5. LAW #1: no random rep gains, no random thresholds. Everything counts deterministically from observable events.

Do NOT touch: temperament (parked), the between-battle task metagame (parked recovery grill), aura GROWTH via training (aura grows by authored/event beats per alchemy-kit.md — it shares the philosophy, not this rep loop; confirm in the doc before wiring anything), economy costs, feat-trigger designs (deferred content). Doc silent -> STOP and ask.

Done when: a unit demonstrably learns an ability by doing its reps across two missions with the cap provably limiting single-mission progress; main-job goals outpace sub goals; a mid-training job swap pauses and resumes without loss; weapon proficiency rises through the same loop and activates a previously-inactive mod space (prompt 10 integration); suite green; CLAUDE.md updated; committed.
```
