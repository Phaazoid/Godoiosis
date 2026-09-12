# Playtest telemetry — the record a played mission leaves

**Status: THE ARC IS COMPLETE ([#53](https://github.com/Phaazoid/Godoiosis/issues/53), closed 2026-09-09).** Five slices, all merged: the recorder + replay-grade capture (#831), the notice (#840), the replay viewer (#843), the quit record (#845), and transport + storage (#848, with #849 and #850 behind it). Filed 2026-07-14, parked, and unparked by the dev 2026-09-07 with *"now that we've started to close the loop of a player playing a mission, we can start on it."* The polish it deliberately left is [#856](https://github.com/Phaazoid/Godoiosis/issues/856).

**Canon checked through #925 (2026-09-12).**

**Not to be confused with [`playtest-experiments.md`](../playtest-experiments.md)**, whose name is one word away and whose subject is different: that one is how to drive an AI agent through the headless bridge and get a measurement you can believe. This one is the record a HUMAN's played mission leaves behind. Neither reads the other's data.

**The ask, verbatim in shape (dev, 2026-09-07):** collect the data while a mission is played, send it on finish, and put it somewhere dashboards can eventually read.

## The one property everything here protects

**A new question must be a query, not a new build and a new cohort of players.**

That single sentence decides nearly every argument below. It is why the client computes no counters, why the raw event log is stored verbatim next to the summary derived from it, why an indexed column is `GENERATED` from the blob rather than written beside it, and why a run the dev would rather not look at is *flagged* instead of dropped. Every one of those is the same trade: pay a little storage now so that a question nobody has thought of yet is still answerable from runs already collected.

The counter-design — per-metric counters in the client — fails that test completely. Asking a new question means shipping a build and waiting for new players to play it.

### The departure from #53's own comments, and why an issue's stated architecture is stale-able

The ticket's 2026-08-10 comment specified **tier 1 = a replay log**: record the command stream, replay it offline through the Play API, *"no per-metric counters in the client, ever."* That is not what was built. A replay harness is its own build, and replaying an old log through newer rules drifts silently — the log ages into a lie without anything announcing it.

An **event log** keeps the property that actually matters (every metric derived offline) without version-pinned replay, and the client still computes nothing: `MissionSummary.of(events)` is one pure function over the record. The dev confirmed the intent survived — *"replay is still a feature I want... we're just expanding on that, right?"* — and replay-**sufficiency** then became part of the arc's definition of done, ahead of the notice, because **a run recorded badly cannot be re-recorded.**

## What a run IS

A **folder**, `user://telemetry/<state>/<run_id>/`, holding two files — `BugReporter`'s shape one domain over:

| file | what it is |
|---|---|
| `events.jsonl` | the authority. One JSON object per line, flushed per line, sealed at the end. |
| `board.tres` | the starting state, through `ScenarioManager.capture_scenario` |

The summary is **not** a third file: it is the last line of the log, and it is a pure projection of the lines above it. Nothing can be true of the summary that the events do not already say.

**The folder's PARENT is the state.** `pending/` means *still owed to the server*; `sent/` means *delivered, kept on disk so the Replay tab can still open it*. A move, never a marker — so nothing can disagree with where a run is, and `TelemetryStore.run_dir()` resolves between them. A brand-new id is in neither and falls through to `pending/`, which is what let every existing writer stay unchanged when `sent/` was added.

**An unsealed file IS the quit record.** Alt-F4, a crash, F2, a board swap — all of them leave one, and it is finished at the next launch rather than by a hook per door. One rule instead of five.

## The dev's rulings

| when | ruling |
|---|---|
| 2026-09-07 | **Payload = event log + derived summary** — not counters, not a replay harness. |
| 2026-09-07 | **Storage = D1 now, R2 later.** D1 is free with no payment method on file; R2 needs a card even at its free tier. |
| 2026-09-07 | **[#200](https://github.com/Phaazoid/Godoiosis/issues/200) is SUBSUMED**, closed into #53 when slice 1 merged. Its metric table survives as `MissionSummary`'s projection, which is what makes the two structurally unable to disagree. |
| 2026-09-08 | **FLAG, NEVER EXCLUDE.** *"Instead of ignoring dev mode play, I think it should get a special flag, so that we know to separate it in the data."* |
| 2026-09-08 | **No opt-out in early builds**, repealing half his own consent ruling of the day before: *"The entire point of this build is playtest data... If they don't want to give me data, they can't play the early version of my game."* Notice-only, one button, fired on first LAUNCH. |
| 2026-09-08 | **Replay-grade capture is part of the definition of done**, and goes before the notice — it cannot be backfilled. |
| 2026-09-08 | **The replay VIEWER goes before transport** — *"Both to verify the replay capture system works, and to use on the data I'll be getting."* |
| 2026-09-08 | **A replay re-runs recorded orders through the LIVE rules and diffs**, rather than redrawing recorded outcomes. |
| 2026-09-08 | **Ragequits count.** *"If the user Alt F4s, I want that run too."* |
| 2026-09-08 | **One Worker with a `/telemetry` route**, not a second Worker. One URL, one secret store, one place for abuse controls. |
| 2026-09-08 | **A sent run MOVES to `sent/` and stays on disk**, so `pending/` means exactly *still owed*. |
| 2026-09-08 | **Query recipes, not a dashboard** — the arc ends when runs are in D1 and the README carries copy-paste queries. |
| 2026-09-09 | **A run may be refused at the client only when it is structurally EMPTY.** Anything merely thin is sent and stamped. Refines FLAG-NEVER-EXCLUDE rather than repealing it. Settled by [#851](https://github.com/Phaazoid/Godoiosis/issues/851) — see *Where the line between refusing and flagging fell* below. |
| 2026-09-09 | **A run whose board lost a reference is SEEDED and marked untrusted, not refused.** The replay harness is the tool you would reach for to investigate such a run, so refusing removes the only instrument. Settled by [#871](https://github.com/Phaazoid/Godoiosis/issues/871). |

### Why FLAG-NEVER-EXCLUDE is a law and not a preference

**An exclusion destroys the evidence that the exclusion was right; a flag is a `WHERE` clause you can drop later.** A dropped run cannot be counted, audited or reinstated, and the threshold that dropped it has to have been correct the first time — with nothing recording how often it fired. So the dev's own sandbox play is recorded too, stamped `sandbox` (an empty `last_loaded_path`) beside `dev_mode`, and **both ride the SUMMARY as well as the events**: the summary row is what gets indexed, so a separation flag has to exist where the querying happens or it is not a separation at all.

### Where the line between refusing and flagging fell (#851, 2026-09-09)

The law above has exactly one exception and it is drawn where **there is nothing to lose**, so that no judgement call is being made: the client refuses a run in which **no pass ever resolved and no order was ever queued**, and only when the ending was one somebody CHOSE — `ABANDONED`, `RESTARTED`, `QUIT`, `INTERRUPTED`. A `CRASHED` run is never refused however empty it is, because **the only ending whose emptiness might be the story is the one nobody chose**: *the game died before I could do anything* is the most valuable thing the intake can receive, and a refusal keyed on emptiness alone would eat exactly that. `VICTORY`/`DEFEAT` cannot legitimately be empty, so one that is gets through as evidence of a bug.

**`INTERRUPTED` is on that list because it is the main door out, not an edge case** — it is sealed from `MissionController.reset()`, the universal teardown behind F2, a board swap, Load Game and Mission Select. That was measured rather than reasoned: of the six runs recorded on the dev's machine when #851 was built, five were empty, and the two that had already reached D1 were both empty `INTERRUPTED` runs. An earlier draft of the rule listed only the three obviously-deliberate endings and would have refused neither of them.

**Everything merely THIN is sent and flagged `trivial`, and that flag is a SQL projection rather than a stamp the client writes.** It is a `GENERATED ... VIRTUAL` column over `rounds` and `orders_queued`, so it is evaluated when a query reads it — which means the threshold can be re-cut across every run ever collected, by one `ALTER`, with no new build and no re-upload. A value stamped by the game would freeze each row's answer at whatever build sent it, leave a table carrying several thresholds at once, and could never reach a run already uploaded. It is also derived rather than duplicated (Law #4): everything it reads sits in the same `summary` blob beside it.

**The refused run stays in `pending/` and is retried forever**, exactly like a run that predates `run_id`. Giving it a way out is [#852](https://github.com/Phaazoid/Godoiosis/issues/852)'s job, deliberately not this one — #851 is about what reaches the table.

## What is recorded, and what is deliberately not

Recorded: the mission's start (roster, scenario, build, install and session ids), every turn's pre-tick vitals, every resolution pass with its committed queue and its per-hit outcomes, the four decision channels a replay needs (a rescue's chosen `haul_to`, the squad verbs, mid-battle gear changes, a `dev_touched` flag), the lifecycle events, and the ending.

**Not recorded, on purpose:**

- **Per-metric counters.** See the one property, above.
- **A hold-position filler as an order.** `batch_id == 0` is the project's own answer to *"did a person author this"* — stamped only by `queue_action`, the Law #3 chokepoint. Without the filter every churn figure gains a phantom order per squadmate per plan. Nothing is lost: the `pass` record still writes the whole queue with fillers flagged `hold`.
- **A queued attack's target.** `AttackAction.declare()` passes `null`; victims are the resolver's answer at pass time. Recording it would write `id: 0` forever, and **a field that can never be non-null is a field that lies.** An aim's identity is its CELL.
- **An ejection, or any other consequence a replay re-derives.** Only decisions are recorded.
- **A scenario fingerprint.** The board snapshot subsumes it.

## The laws this arc paid for

Each of these cost something to learn, and each travels beyond telemetry.

- **AN ID WRITTEN DOWN FOR A LATER PROCESS TO READ MUST BE A STABLE VALUE; A RUNTIME HANDLE NEVER IS.** `MissionLog._ref` wrote `get_instance_id()`, so every unit reference in every recorded run was unreadable by anything outside the process that wrote it — found by the replay viewer, exactly as slice 2's PR had predicted a harness would find something. Cured with no format change and retroactively: `mission_start.roster` carries each unit's starting CELL, and `spawn_unit` refuses an occupied one, so a seeded board is exactly one unit per cell and the binding is unambiguous. **The fix is usually a fact the record already carries.** The same trap bit again inside `ReplayDriver` (#850) from the other end — see `CLAUDE.md`'s freed-reference edge (#149).
- **A SIGNAL THAT FIRES FROM ONE DOOR CAN MISS THE FIRST MEMBER OF ITS OWN SERIES.** `TurnManager.turn_started` fires only from `end_turn`, never from `start_faction_turn`, so a recorder riding it loses every mission's turn-1 baseline — the snapshot every margin and damage-taken figure subtracts from. When subscribing in order to record a SERIES, ask whether its first occurrence is emitted at all.
- **THE RECORDED `turn_start` VITALS ARE PRE-TICK**, and that is a fact about the codebase rather than about this ticket: `MissionLog` is built in `_build_collaborators`, so its handler connects before `game._on_turn_started` and fires ahead of the downed clocks, `enforce_contact` and the mission check. Anything comparing a recorded row against a live board read *after* a hand-over is comparing pre-tick to post-tick and cries wolf on nearly every run. **The cure is to measure with the SAME recorder at the SAME signal position**, so the two sides are like-for-like by construction.
- **WHEN A PROJECTION IS COMPUTED UPSTREAM OF THE WRITE, NO ASSERTION ON THE PROJECTION CAN SEE THE WRITE.** A mutant that dropped every surviving line from the quit-record rewrite passed nine cases, because the summary is projected from the parsed events before anything is written. Compare the file itself, as a prefix.
- **A RE-ENCODE TURNS EVERY INT IN THE FILE INTO A FLOAT.** JSON has one number type, so a run read back through `JSON.parse_string` is all floats while the live side holds ints — `9` against `9.0` on every field. Keep the raw text beside the parse (`ReplayRun.raw_lines`) and hand back what you read; compare numerically, never as strings.
- **`FileAccess.WRITE` TRUNCATES, AND `load_events` STOPS AT THE FIRST UNPARSABLE LINE.** Either reason alone is fatal to appending an ending onto a partial one: it would be unreachable by the very tool that reads runs. The sweep rewrites.
- **A STATED HOME IN AN APPROVED PLAN IS A DECISION, NOT A MEASUREMENT.** The launch sweep was planned onto `TelemetryStore` and had to move: it needs `ReplayRun` and `MissionSummary`, both of which already depend on the store, so the plan's home was two dependency cycles. Split at the seam that already existed — the store owns the PATH, `MissionLog` owns the CONTENT.
- **REACHING FOR AN EXISTING SIGNAL BECAUSE IT EXISTS IS NOT LAW #4.** `squad_created` has six callers and does not mean *"the player formed a squad"*; riding it would log a leave as a squad-up and a disband as N of them. The signal has to answer the question being asked.
- **AN AUDIT FOR ONE PROPERTY IS A GOOD WAY TO FIND A DIFFERENT BUG.** The slice-2 self-review turned up a live slice-1 defect: `reload_current()` has two callers and only one sealed, so **F2 left the run open and it went on appending events about a board that had been replaced.** Cured at `MissionController.reset()`, the universal teardown, which covers all four doors and composes with the named seals because `seal()` early-returns when closed.

## Transport and storage

The client half is `Classes/net/` and is documented in `CLAUDE.md`; what belongs here is why the shape is what it is.

- **ONE MECHANISM, TWO TRIGGERS:** `send_pending()` runs at launch (after the sweep) and again on `MissionLog.run_sealed`. **The launch call IS the retry**, which is why no retry ledger exists anywhere in the system. Its cost is the declared limit at [#852](https://github.com/Phaazoid/Godoiosis/issues/852): a run the server permanently refuses -- or that the CLIENT refuses, since #851 -- is retried forever.
- **The seal's emit is gated twice**, and both gates are `seal()` callers counted rather than guessed — not while the run has no file (the replay driver re-records in memory, and an ungated emit would make a dev replay session a network trigger), and not on QUIT (`get_tree().quit()` is the next line, so the request is at best wasted and at worst holds shutdown open for its timeout). The next launch's sweep sends that run anyway.
- **The schema is ONE blob with GENERATED VIRTUAL columns over it**, so an index cannot disagree with the record (Law #4). Anything not promoted is still reachable through `json_extract` and needs no migration to ask about; a column added later by `ALTER TABLE` must be VIRTUAL. **A column added after the intake went live is spelled ONCE, in an `alter-*.sql` migration, and is never back-written into `schema.sql`** (#851): that file is `CREATE TABLE IF NOT EXISTS`, so a column added there would never reach the live database while still looking like the table's definition -- two spellings, two live callers, drifting silently. A fresh database runs `schema.sql` and then the migrations in name order; what the table actually holds is a question for the table.
- **MEASURED, NOT ESTIMATED.** A run is 30–70 KB (events 6–10 KB at one round plus ~3 KB per turn; the board 31–60 KB). The binding ceiling is **D1's 2 MB per ROW** — summary, events and board share one — not the Worker's 100 MB body. No compression: ten times the headroom against a limit nothing is near, for a second thing that can be wrong. The free plan's **10 ms CPU is a plan gate, not a config knob**, which is why the Worker parses only the small summary field and stores the rest verbatim.
- **An unmatched path is a 404, never a fall-through.** Cloudflare normalizes doubled slashes and nothing else, so `/telemetry/` is a real string a client can send — under a default-to-report branch it would have been relayed to Discord as a bug report, silently, with no row written.
- **THE PIPE IS ONE-DIRECTIONAL, AND GETTING A RUN BACK IS A QUERY RATHER THAN A ROUTE ([#865](https://github.com/Phaazoid/Godoiosis/issues/865), 2026-09-09).** The Worker has two routes and both are POST; `ReplayRun` reads local disk only. That is what makes the intake safe to leave unauthenticated — `Uploader.ENDPOINT` is a `const` in the shipped game, so the URL is effectively public, which is fine for something that only ACCEPTS uploads and stops being fine the moment it hands runs back. A read route would need auth of its own, and a secret compiled into a dev build is not a secret. So a run comes back down through `tools/intake-worker/pull-runs.ps1`, which asks D1 with the account owner's own `wrangler` credentials and writes `sent/<run_id>/` — no route, no exposure, and the Replay tab needs no change because the run simply appears in its list. **A pulled run lands in `sent/` and never `pending/`**, since `TelemetryUploader` walks `pending_runs()` and would ship it straight back up. Three things that script has to get right, each measured rather than reasoned: **the events blob must be written with NO BOM** (`ReplayRun.load_events` runs `JSON.parse_string` on line 1, and a BOM is not whitespace, so the run reports itself truncated at line 1 and comes back empty); **the console codepage must be UTF-8 before wrangler is called**, because PowerShell decodes a native command's stdout with `[Console]::OutputEncoding` and the default OEM page turns an accented character into box-drawing junk *before* the JSON is parsed; and **a blob whose last line is not the `summary` must be refused rather than written**, because `sweep_unsealed()` walks BOTH folders at every launch and would finish a truncated download as a `CRASHED` run — evidence of a player crash that never happened.

## The replay harness

`Session > Replay` in the dev tools. `ReplayRun` reads a run folder; `ReplayDriver` seeds the recorded board, re-issues every recorded decision **through the real doors**, and diffs the result against what was recorded.

It **owns no rule** — every order goes through `SquadManager.queue_action` or a `game.*` door, so the live rules answer and the driver only asks. That is what makes it a verification tool rather than a second implementation of the game: it can only ever report that today's rules disagree with what was recorded, never quietly reproduce them.

Four properties are load-bearing:

- **The measurement is `MissionLog`'s, not the board's.** The replay re-records in memory through the same recorder at the same signal position, so the two sides are pre-tick against pre-tick by construction, and `pass.hits` gives a per-HIT checksum rather than a per-turn one.
- **The AI stands down AFTER the seed, never before** — `apply_scenario` replaces the AI set from the board it loads (#150), so a stand-down written first is overwritten by the very next line. Every faction's orders are in the log; letting the AI plan fresh ones asks a different question entirely, which is `tools/replay_battle.gd`'s.
- **A BOARD THAT LOST A REFERENCE STILL SEEDS, AND THE REPORT SAYS SO ABOVE THE VERDICT ([#871](https://github.com/Phaazoid/Godoiosis/issues/871), 2026-09-10).** A run's board names authored content by path, and a dangling `ext_resource` is a hard parse error for the whole file — so once [#865](https://github.com/Phaazoid/Godoiosis/issues/865) made runs arrive from other people's builds, a moved `.tres` failed a run completely and said only that `board.tres` was not a `ScenarioData`. It now loads through `ContentRepair`, and **the fix had to carry its own antidote**: `seed()` copied `ReplayRun.problems` into the report *only on the refusal branch*, so merely making the board load would have printed **"Clean — the replay matched the run."** over a board missing a weapon — failing silently traded for succeeding silently. `degraded` is therefore a second list beside `problems` (one says *cannot replay*, the other says *replaying proves less than it looks like*), it is projected into `report()` rather than copied at seed, and the tool prints it **bold, directly under the verdict** — never as a footnote below the divergences the way `notes` are. Two things it is read off matter: **the file's TEXT, never `ContentRepair`'s registry** (a repaired resource takes over its path, so the *second* look at one run is a cache hit that erases the repair record — measured, and the suite's twice-case is the only mutant that catches it), and **`ResourceLoader.exists`, never `FileAccess.file_exists`** (`Classes/dev/` is not in the export exclude list, so the Replay tab ships, and in a pack the `FileAccess` question answers *missing* for every resource — [#867](https://github.com/Phaazoid/Godoiosis/issues/867)'s trap one layer over). A run's board is also **forgotten** after the load: it is a frozen snapshot nobody can fix, and `BoardLint` would otherwise report it forever as authored content to restore.
- **A THREE-VALUED FLAG MUST NOT PASS THROUGH A TWO-VALUED COERCION, AND `bool(null)` IS A HARD SCRIPT ERROR ([#925](https://github.com/Phaazoid/Godoiosis/issues/925), 2026-09-12).** `dev_touched` has three answers, not two: the sweep writes **null** on purpose because the flag lived in memory and died with the process, so *we do not know* is a different answer from *no dev tool was used*. `ReplayRun.headline()` read it as `bool(end.get("dev_touched", false))` — and `Dictionary.get` returns the STORED null when the key exists, so the default never fires. In GDScript that call is not a coercion but an error (*Invalid call. Nonexistent 'bool' constructor*), which aborts `headline()` mid-build and hands the caller null: **clicking any swept run in the Replay tab froze the game**, i.e. every crashed run, which is the one you most want to open. Slice 4 wrote the reader; slice 4b wrote the null 65 minutes later. Nothing caught it because **slice 4b's own case calls `headline()` on the run BEFORE the sweep** — it asserts the null is written and never asks whether anything can read one. The upload side was untouched throughout, `MissionSummary` never having read the field. Two things to carry: a reader of a field whose writer chose three states has to be checked against all three, and **a case pinning such a read needs a `has()` assertion, not a value compare** — the aborted call returns null, so a value compare reads null out of the failure and passes.
- **THE PICKER HIDES ONE-TURN RUNS, AND THAT IS HALF OF D1'S `trivial` CUT ON PURPOSE ([#925](https://github.com/Phaazoid/Godoiosis/issues/925)).** 34 of the 41 runs on the dev's machine never reached round 2 — board swaps, F2s, a mission opened and left — and there is nothing in one to replay. The `trivial` column above is `rounds < 2 OR orders_queued < 2`; the Replay tab takes only the first half, because the dev tools cannot reach D1 and **one turn is what was asked for**: the orders half would hide a three-round run that happened to carry one order, which is a different question. A session-only checkbox rather than a `PlayerSettings` row (a dev-tools list filter is not a preference a player keeps) and it is what gets a hidden run BACK, which matters because a crashed run is usually one turn long itself. The rule is `ReplayRun.is_one_turn()`, the list applies it in `refresh_on_show` because it is a property of the LIST rather than of a run, and the filter reads through `load_events` rather than `load_run` — the board is the expensive half and a filter has no use for it, which is the seam #53 slice 5 split for exactly this.
- **Only OUTCOMES are compared.** `order_queued`, `gear` and `squad_verb` are the driver's own input, so diffing them asks only whether it echoed what it was handed — rows that cannot fail, padding a report until nobody reads it.

**A harness that cannot report a difference is worse than none**, because it would certify anything. The suite therefore corrupts a run on purpose and requires a named divergence back.

## What the record cannot tell you

Stated rather than discovered later:

- **The snapshot has no RESERVE.** `capture_scenario` walks `units_root`, so a run's board carries the deployed force and not the undeployed roster behind it.
- **A swept run's ending was INFERRED at a later launch, not watched** — that is what the `swept` flag is for, and it is why a swept CRASHED run is evidence rather than noise.
- **A pre-#843 run's unit ids are unreadable.** They were instance handles. The roster's starting cells are what make older runs bindable at all.
- **A run recorded before slice 5 has no `run_id`** and the intake will refuse it forever ([#852](https://github.com/Phaazoid/Godoiosis/issues/852)).

## Open gates

- **[#841](https://github.com/Phaazoid/Godoiosis/issues/841) — restore a data-sharing setting before any build goes wider than hand-delivered.** The no-opt-out ruling is scoped to *"the early version of my game"*, handed out in person with the terms said out loud first. It stopped being theoretical the day slice 5 merged: until then the notice described data sitting on the player's own disk, and now it describes data leaving their machine.
- **[#856](https://github.com/Phaazoid/Godoiosis/issues/856)** — the polish umbrella, including the P0 that keeps the dev's own test runs out of the numbers ([#851](https://github.com/Phaazoid/Godoiosis/issues/851)).
- **[#209](https://github.com/Phaazoid/Godoiosis/issues/209)** — Theater mode, the player-facing descendant of the replay viewer. Deliberately separate: this one is a diff tool for a developer, that one is a camera for a player.
