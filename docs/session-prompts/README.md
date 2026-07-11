# Session prompts — the post-grill build-out (v2, 2026-07-07)

Copy-paste prompts for fresh Claude sessions, each **actionable cold**: a new session auto-loads only `CLAUDE.md` + memory, so every prompt names what to read first. Launch sessions from `C:\Iosis` (the junction — relaunching from the repo root orphans memory).

**v1 (prompts 1–4) is DONE** — test harness, elemental v1, Will/downed lifecycle, GitHub migration all landed. The files stay as history.

**v2 is the coding build-out of the 2026-07-04→06 grill decisions** (jobs · CON+bands · weapon parts · limb-slot maims · AI Crisis stances · transmutation doctrine · audit A1–A8). All design is **canon in `docs/design/`** — these sessions *implement*, they do not redesign. Tracked context: [grill-queue.md](../design/grill-queue.md) → Done.

## Ground rules for the driving model (Sonnet-ready)

Every prompt embeds these, but they bear stating once:

1. **Docs are canon.** If code and a design doc disagree, the doc wins. If the doc is *silent*, STOP and ask the user — never invent design. Parked topics (between-battle recovery, materia, temperament, LDR budget numbers, content/naming passes) are **off-limits**: leave a `TODO` pointing at [grill-queue.md](../design/grill-queue.md) and move on.
2. **The collaboration contract (CLAUDE.md) is absolute.** The user hand-types all gameplay code (`Classes/`, `Scenes/`, `game.gd`) — deliver complete typed code blocks with file/line anchors and the *why*; verify by reading the real file after each step. Claude edits `tests/`, `docs/`, and issue text directly.
3. **All doc numbers are placeholders.** Implement each as a named constant with a terse `# playtest-tunable` comment. Terse comments generally — no walkthrough prose in source.
4. **Laws:** #1 no randomness · #2 the queue never lies (every new outcome must be previewed) · #3 AI uses the player's API. Read the sharp-edges section of CLAUDE.md before touching enums or `.tres` (append-only, data-migration trap).
5. **Tests:** every session adds gdUnit4 coverage under `tests/`. Read `tests/README.md` first — explicit types (no `:=` on `auto_free`/spawn helpers), never instantiate full UI scenes headless. If Godot isn't on PATH in the session's environment, hand the run back to the user.
6. **Wrap-up:** update the CLAUDE.md architecture map if the session added a subsystem, note follow-ups as GitHub issues (existing label scheme), commit.

## The dependency spine

```
5 drift sweep ──────────────┐ (independent, mostly Claude-direct)
6 CON + bands + min-1 chip ─┴─→ 7 limb slots + effective-stat spine + MOV
                                   │
        ┌──────────────────────────┼───────────────────────┐
        8 AI Crisis stances        9 jobs data model        11 transmutation doctrine (#30)
        (anytime after 6)          │                        (needs 7's aura-tax hook only)
                                   ├─→ 10 weapon parts
                                   └─→ 12 ability chassis ─→ 13 training goals
```

**Default serial order (single typist): ~~5~~ (done) → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13.**
Legal swap: 11 may jump ahead of 9 any time after 7 — it advances [#30](https://github.com/Phaazoid/Godoiosis/issues/30), the open P1 issue. 8 is a small palate-cleanser; slot it wherever a short session fits.

| # | Prompt | Size | Builds |
|---|--------|------|--------|
| 5 | ~~[drift sweep](5-drift-sweep.md)~~ | ✅ DONE 2026-07-07 | Executed by Fable 5 in-session: AIR ruled canonical (wind = attack names only), SPD ghost swept (fixture; `.tres` were already clean), stale claims fixed across 12 docs — see [grill-queue.md](../design/grill-queue.md) Drift fixes |
| 6 | [CON + stat bands](6-con-and-stat-bands.md) | M | CON stat, min-1 chip, CON→MHP & PER→LDR bands, Weight readout, DEF×CON seam |
| 7 | [limb slots + effective stats](7-limb-slots-and-effective-stats.md) | L | the effective-stat pipeline, 4-slot limb model, maim rotation, verb locks, MOV derivation, aura limb tax |
| 8 | [AI Crisis stances + preview](8-ai-crisis-and-preview.md) | S | per-archetype Crisis stances, CRISIS lethality preview, AI deprioritizes downed |
| 9 | [jobs data model](9-jobs-data-model.md) | L | JobData/JobCatalog, certification + slots, ceilings, job MOV base, dev-editor + enemy jobs |
| 10 | [weapon parts](10-weapon-parts.md) | L | WeaponModData, 3-space fitting, proficiency stub, prototypes, module Weight |
| 11 | [transmutation doctrine catch-up](11-transmutation-doctrine.md) | L | affinity set, two-knob rune sizes, temper/leeway/strain, fizzle preview (A7) — the #30 lane |
| 12 | [ability chassis](12-ability-chassis.md) | L | taxonomy, live-kit computation, seed abilities, reactions-as-policies |
| 13 | [training goals](13-training-goals.md) | M | the anti-grind learning machinery growing proficiency + job abilities |

## What is deliberately NOT here

- **Between-battle recovery, materia pass, temperament, affinity expansion, LDR budget, story canon conflicts** — parked grills ([grill-queue.md](../design/grill-queue.md)); no code until grilled.
- **Campaign store (A8)** — a named persistence seam, not a build item; it lands with campaign save/load.
- **BREAK banner / visual-clarity work** — rides umbrella [#44](https://github.com/Phaazoid/Godoiosis/issues/44); prompts only build the *previewed-fizzle* substrate the doctrine needs.
- **Milestone-A demo blockers that predate the grills** — win/loss detection, Balanced archetype, Play-API AI integration (#29 leftovers). Interleave these by taste; 8 covers the AI-ignores-downed piece. *(The #50 fire/ice feel-test passed 2026-07-08 — cleared.)*
- **Play-API parity catch-up (#46)** — deliberately AFTER the spine: one "prompt 14" pass (terrain states, Will/Rally/Crisis, carving commands, frame persistence, inspect parity + whatever 6–13 added), then the Play API becomes the verification lane for the new systems. Status + gap list: the 2026-07-08 comment on [#46](https://github.com/Phaazoid/Godoiosis/issues/46).

## Environment note (unchanged from v1)

In at least one dev environment **Godot is not on PATH** (only git). A session needing an engine run (tests, import) must be launched where Godot is available, or hand that step to the dev.
