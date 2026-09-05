# Running playtest experiments

**Canon checked through #765 (2026-09-05).**

How to have an AI agent play Iosis through the headless bridge, unattended, and get a measurement
you can believe. Written after seven runs across three arms, and it is mostly a list of ways the
obvious approach quietly produces a wrong answer.

The API itself is [`play-api.md`](play-api.md). This is about *operating* it.

The harness is [`tools/playtest/`](../tools/playtest/): `run.sh` (one run, isolated and archived),
`analyze.sh` (the metrics), `extract-transcript.sh` (the agent's own account), `prompt.md` (the
shared prompt).

---

## The shape of a run

```bash
export IOSIS_PLAYTEST_WT=~/iosis-worktrees/playtest      # a THROWAWAY worktree
export IOSIS_PLAYTEST_PROJECT=<agy project id>           # pins the session to it
export IOSIS_PLAYTEST_ARM=C                              # names the arm in the archive
tools/playtest/run.sh 1
tools/playtest/analyze.sh
```

Each run archives frames, the agent transcript, its conversation db, and a manifest naming the
commit. A run takes 3–7 minutes and ~3% of a five-hour Gemini budget.

---

## Isolation: the agent binds to a PROJECT, not to cwd

**This cost a run.** `agy -p` launched from the worktree played in the *main checkout* instead,
and the harness archived zero frames while reporting success. `--project` with a JSON in
`~/.gemini/config/projects/<id>.json` binding `folderUri` to the worktree is what pins it:

```json
{ "id": "<uuid>", "name": "/path/to/worktree",
  "projectResources": { "resources": [ { "gitFolder": {
     "folderUri": "file:///path/to/worktree", "allowWrite": true } } ] } }
```

`allowWrite` must be true — the bridge protocol writes `playrun/command.json` inside the repo.
So the isolation is *the worktree is disposable*, not *the agent cannot write*. Verify a new pin
with a one-line `pwd` prompt before spending a real run on it; `run.sh` also fails loudly when it
finds no frames, because silently archiving nothing is how this hid the first time.

**`/playrun/` is gitignored**, so switching branches does NOT clear it. Frames from the previous
run survive into the next and mix into the analysis. `run.sh` clears it; skipping that step
invalidates the arm.

---

## The prompt is a variable, and a bigger one than the code

The first five (observational) runs were prompted *"…has a headless mode that AI agents like you
can play. Would you like to give it a spin?"* — no goal, no stopping rule. They rejected **30–54%**
of their own commands.

A controlled prompt — *play as well as you can, read the docs first, stop after 8 player turns* —
produced **4%** on the same build.

So: **arms must share a prompt, and a prompt without a stopping rule produces runs of
incomparable length** (those five ranged 84–477 frames). Never treat exploratory sessions as a
baseline for a measured one. And do not name new commands in the prompt: if a fresh session cannot
find an affordance from `play-api.md` alone, the affordance shipped inert, and prompting around
that measures your prompt instead.

---

## Pre-register the metrics, then distrust your own collector

Fix the metrics before either arm runs. Then assume the collector is wrong, because mine was,
twice, and both times in the direction that flattered the change:

- **It counted my own archived transcripts as game output.** `find -name '*.txt'` swept up the
  `transcript.txt` that the archiver had just written beside the frames. Bytes read 4x high.
- **The guard went blind when the interface changed.** `overview`-per-`execute` was counted from
  filenames; batching then named a frame for its LAST command, so an `overview` *inside* a batch
  stopped being visible and the pre-registered falsifier silently read zero. Count from frame
  CONTENT, not names.

A guard that cannot fail is worse than no guard, and neither of these announced itself.

### What the columns mean

| | |
|---|---|
| `REJECT` | refused commands. **Rises when the opponent is real** — plans go stale between turns. |
| `B/TURN` | bytes per player turn. Normalised; raw totals are not comparable across run lengths. |
| `OV/EXEC` | explicit `overview` per `execute`. The guard on any change that removes a redraw: if it climbs, the redraw **moved** rather than went away. |
| `AFFORD` | `legal_moves`/`legal_targets` calls. Zero means an affordance shipped inert. |
| `PY` | `python3` invocations — see below. |

---

## `python3` usage is an interface metric, not a hygiene one

| arm | shell calls | of which `python3` |
|---|---|---|
| pre-#613 | 72, 61 | 69, 54 |
| #613 | 3, 43 | 0, 32 |
| #665 (`send.sh` shipped) | — | **0, 0, 0** |

The bridge is write-then-poll. That is fine a dozen times and unbearable seventy, so an agent
writes a poller and loops it — **the scripting tracks round-trip count and nothing else.** It
matters because an agent that must run arbitrary code cannot be given a narrow permission
allowlist, so an unattended run needs blanket approval, which removes the guard that stops a
session meant to be *playing* the game from editing it. Batching and `play/send.sh` took it to
zero; the allowlist is now *launch the bridge* and *run send.sh*.

**Treat a rise in `PY` as an interface regression.**

---

## What you may and may not compare

Only compare arms that differ in **interface**. Three arms exist and only two are comparable:

| arm | what it is |
|---|---|
| A | pre-#613 |
| B | #613 — affordances, batching, no automatic redraw |
| C | #665 — same interface, **plus an opponent that actually acts** |

A↔B is an interface comparison. **B↔C is not**: the enemy was a no-op before #665, so an agent has
a strictly harder game in C, and any difference confounds "interface changed" with "game got
harder". C is a *new baseline* for future interface work, not the other side of an A/B.

Reference values, three C runs: `REJECT` 12–20%, `B/TURN` 6.4–9.9k, `OV/EXEC` 0.62–1.42,
`AFFORD` 17–24, `PY` 0.

---

## Two runs per arm is directional, not significant

Between-run variance on a single build ran **2% to 54%** rejection in the observational set. Two
runs cannot resolve a difference smaller than that. Say "directional" in the writeup and mean it.
The one metric that separated cleanly at n=2 was bytes/turn, where the two baseline runs landed
within 1.5% of each other — variance is per-metric, so check it per-metric.

---

## Watching a run, and reading it afterwards

Live, read-only:

```bash
cat $IOSIS_PLAYTEST_WT/playrun/state.txt          # the board, as the agent last saw it
```

**Never write `playrun/command.json` while a session is live** — that injects a command into its
conversation and corrupts the run.

Afterwards, the frames are *what it did* and the transcript is *what it was trying to do*. Both
are needed and they answer different questions. Transcripts are protobuf blobs in SQLite;
`extract-transcript.sh` pulls the readable half — the prompt, every tool call with its JSON
arguments, the model's running status summaries, and its final written report.

**Read the report.** Agents diagnose interface faults precisely and unprompted. Across these runs
they found: the six session verbs the bridge never dispatched, a refusal message that reports a
guessed reason (#662), weapon readiness missing from the legend (#663), and a bash expansion bug
in `send.sh` that they root-caused from the source (#765).

---

## Assorted, each learned the hard way

- **macOS has no `timeout`.** `agy --print-timeout` is the bound.
- **A run that ends on the enemy's turn is not stuck** — `end_turn` refuses to hand off a finished
  mission, so a won or lost board legitimately stops there.
- **Do not assert on content.** A fixture of one unit against a rushdown loses on turn 3; "the
  board ends on PLAYER" is false for a good reason. The invariant is *it ends somewhere the driver
  can act from unless the mission is over*. `tests/README.md` #9's razor applies to run analysis as
  much as to tests.
- **Check the tree after every run**, even with the prompt forbidding edits. `run.sh` records
  `worktree_dirty` and reverts.
