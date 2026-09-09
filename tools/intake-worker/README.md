# Iosis intake Worker (#131, #53 slice 5)

One Cloudflare Worker with two tenants, routed on path:

| Path | What it does | Where it lands |
| --- | --- | --- |
| `` (the root) | relays a bug report, untouched | a Discord webhook |
| `/telemetry` | writes one recorded playtest run | the `iosis-telemetry` D1 database |

An unmatched path is a **404**, never a fall-through — Cloudflare normalizes doubled slashes and
nothing else, so `/telemetry/` is a string a client can really send, and under a default-to-report
branch it would have been posted to Discord as a bug report with no row written.

The game never learns the Discord webhook URL or a database credential. It knows only this Worker's
address, which is not a secret — it is just where things go. That is the whole point: either can be
rotated, and abuse can be filtered, without re-exporting the game.

`tools/` is in `export_presets.cfg`'s `exclude_filter`, so nothing here ships in a build.

---

## Already done — do not redo these

The relay half has been live since **2026-08-05** (#131). Listed so it is obvious what is *not*
being asked of you:

- The Discord webhook exists, and `DISCORD_WEBHOOK` is set as a Worker secret.
- `wrangler` is installed and logged in.
- The Worker is deployed at **`https://iosis-reports.phlogiston-games.workers.dev`**.
- `ENDPOINT` in `Classes/net/Uploader.gd` already points at it.

**`ENDPOINT` does not change in slice 5, and that is deliberate.** The folder was renamed
`report-worker` → `intake-worker`, but `name = "iosis-reports"` in `wrangler.toml` was **not** —
that name is what the URL is built from, so renaming it would move the endpoint out from under
every build already in someone's hands.

> **If wrangler has forgotten you**, `wrangler login` again. That is the only step from the original
> setup you might have to repeat.

---

## What slice 5 asks of you: four commands and one paste

All from **`tools/intake-worker/`** — the folder is new, so a shell history that says
`cd tools/report-worker` will not find it.

**1 · Create the database.** D1 is free and needs **no payment method** — that is the whole reason
the run intake is D1 and not R2.

```bash
wrangler d1 create iosis-telemetry
```

**2 · Paste the id it prints** into `wrangler.toml`, replacing `REPLACE_ME` in the
`[[d1_databases]]` block. The id is an identifier, not a credential — reaching the database still
needs an account — which is why it is safe to commit.

**3 · Create the table, then apply every migration beside it, in name order.**

```bash
wrangler d1 execute iosis-telemetry --remote --file=schema.sql
wrangler d1 execute iosis-telemetry --remote --file=alter-2026-09-09-trivial.sql
```

**`--file` DOES NOT WORK UNDER AN OAUTH LOGIN — measured 2026-09-09, and the error does not say so.**
It fails with `Authentication error [code: 10000]` naming `/d1/database/<id>/import`, on an account
whose token carries `d1 (write)` and whose owner is Super Administrator. `--file` and `--command` are
different API endpoints: `--file` stages the file through D1's **import** endpoint, `--command` goes
to the plain **query** endpoint, and only the second one works with the token `wrangler login`
mints. So the real instruction is *paste the statements*, not *pipe the file* — see
*Running SQL when `--file` is refused* below. The `--file` form is kept here because it is the right
command the day a scoped API token is in `CLOUDFLARE_API_TOKEN`.

**Two files rather than one, deliberately.** `schema.sql` is the table as it was first created;
every column added since is spelled once in an `alter-*.sql` beside it, and never repeated into
`schema.sql` — a column with two spellings has two live callers (the database that does not exist
yet, and the one that does) and nothing would notice them drifting apart. See *Adding a column*
below.

**`--remote` is the one trap in this whole page.** Without it wrangler writes to a **local** SQLite
file that the deployed Worker never sees, everything looks fine, and your first real upload comes
back `no such table: runs`.

**4 · Deploy.**

```bash
wrangler deploy
```

Note this replaces the **whole** running Worker, so it redeploys the bug-report relay too. That
shared blast radius is the cost of one Worker rather than two, chosen deliberately on 2026-09-08.

---

## Adding a column

**A new column goes in a NEW `alter-*.sql` and is never back-written into `schema.sql`.** That file
is `CREATE TABLE IF NOT EXISTS`, so once the table exists it is a no-op and a column added there
would never reach the live database — while still *looking* like the table's definition. Spelling
one column in two files is a second answer to what that column is, with two live callers and no way
to notice them drifting; so `schema.sql` is frozen as the table as first created, and the migrations
beside it are the rest. What the table actually holds is a question for the table: the D1 console's
**Tables** tab, or `select * from runs limit 0`.

There is one migration so far — `alter-2026-09-09-trivial.sql`, which adds `passes`,
`orders_queued` and `trivial` ([#851](https://github.com/Phaazoid/Godoiosis/issues/851)). Under an
OAuth login it is applied by pasting its statements (see the section below); with a scoped API
token it is one command:

```bash
wrangler d1 execute iosis-telemetry --remote --file=alter-2026-09-09-trivial.sql
```

**Three things about it that are true of every migration here, because every column in this schema
is `GENERATED ... VIRTUAL`:**

- **It is instant and it rewrites nothing.** A virtual column stores no data; it is an expression
  evaluated when you read it.
- **It is retroactive.** Rows already in the table are classified the moment the statement returns —
  which is the whole reason `trivial` is computed here rather than stamped by the game. A value the
  client wrote would freeze each row's answer at whatever build sent it, and could never reach a
  run that has already been uploaded.
- **No `wrangler deploy`.** The Worker stores `summary` whole and never reads a promoted column, so
  its code is unchanged. Skipping the deploy also means not redeploying the bug-report relay.

Running a migration twice fails with `duplicate column name`, which is the honest answer to *did I
already apply this?* — nothing is damaged either way.

**Re-cutting the `trivial` threshold** is the same door, in two statements, and needs no build:

```bash
wrangler d1 execute iosis-telemetry --remote --command "alter table runs drop column trivial"
```

…then re-add it with new numbers by editing the `ADD COLUMN trivial` statement in the migration file
and running just that. This works only because `trivial` is deliberately **not indexed** — SQLite
refuses `DROP COLUMN` on a column an index names.

---

## Running SQL when `--file` is refused

Under the token `wrangler login` mints, `--file` fails and `--command` works. Measured on this
account 2026-09-09; the failure names the endpoint rather than the cause:

```
✘ [ERROR] A request to the Cloudflare API (/accounts/<id>/d1/database/<id>/import) failed.
  Authentication error [code: 10000]
```

**It is not a missing D1 permission** — the token carried `d1 (write)` and the account owner is
Super Administrator. `--file` stages the file through D1's **import** endpoint, `--command` goes to
the plain **query** endpoint, and the OAuth token reaches only the second.

**So paste the statements.** They are independent — `trivial` reads `summary` directly rather than
the two columns above it — so order does not matter and any one can be rerun on its own.

```bash
wrangler d1 execute iosis-telemetry --remote --command "alter table runs add column passes integer generated always as (json_extract(summary, '$.passes')) virtual"
```

```bash
wrangler d1 execute iosis-telemetry --remote --command "alter table runs add column orders_queued integer generated always as (json_extract(summary, '$.orders_queued')) virtual"
```

```bash
wrangler d1 execute iosis-telemetry --remote --command "alter table runs add column trivial integer generated always as (coalesce(json_extract(summary, '$.rounds'), 0) < 2 or coalesce(json_extract(summary, '$.orders_queued'), 0) < 2) virtual"
```

Windows PowerShell needs no escaping here: `$` followed by `.` is not a variable, so `'$.rounds'`
survives a double-quoted string intact (checked, rather than assumed).

**The migration FILE is still the one home for those statements** even though it is not what gets
executed — it is where they are authored, reviewed and re-cut. The cost of pasting rather than
piping is that nothing enforces that what ran matches what the file says, so **ask the table what
it holds after a migration** rather than trusting the file: `select * from runs limit 0`, or the D1
console's **Tables** tab.

**The other way out**, if piping files is worth having: put a scoped API token in
`CLOUDFLARE_API_TOKEN` instead of logging in interactively. That is a Cloudflare dashboard job
(My Profile → API Tokens) and it needs **Account · D1 · Edit**; `--file` then works as written
everywhere on this page. Nothing here requires it.

---

## Proving it before the game is involved

Each of these proves one route on its own, so a later failure in-game is unambiguously the game's
side. Substitute your own subdomain.

**The report relay** — expect `ok`, and a message with an attachment in the channel:

```bash
curl -X POST -F "payload_json={\"content\":\"worker smoke test\"}" -F "files[0]=@wrangler.toml" https://iosis-reports.<your-subdomain>.workers.dev
```

**The telemetry route** — needs no Discord at all. Expect `ok`, then the first query below should
show a row for `smoke-1`:

```bash
curl -X POST -F 'summary={"event":"summary","summary":{"run_id":"smoke-1","scenario":"x","outcome":"VICTORY","rounds":3,"passes":9,"orders_queued":9,"sandbox":false,"dev_mode":false,"swept":false}}' -F "events.jsonl=@schema.sql" https://iosis-reports.<your-subdomain>.workers.dev/telemetry
```

**That summary carries the flag fields on purpose, and it did not always.** Every recipe below
filters on `sandbox` / `dev_mode` / `trivial`, and those are `json_extract` over this blob — a field
that is *absent* extracts as SQL `NULL`, and `NULL = 0` is NULL rather than true, so a row is
dropped by a filter that looks like it should keep it. The older, shorter smoke summary posted
fine, wrote its row, and was invisible to the very query this step tells you to check it with.

Clean it up afterwards with
`wrangler d1 execute iosis-telemetry --remote --command "delete from runs where run_id = 'smoke-1'"`.

| Response | Cause |
| --- | --- |
| `DISCORD_WEBHOOK secret is not set` | The secret was never set, or was set outside `tools/intake-worker/` |
| `discord 401` / `discord 404` | The webhook was deleted, or the URL was pasted truncated |
| `expected multipart/form-data` | `curl -d` was used instead of `-F` |
| `no such route: /report` | Only `` and `/telemetry` exist; anything else is a 404 by design |
| `DB (D1) binding is not set` | Step 2 was skipped — `database_id` is still `REPLACE_ME` |
| `no such table: runs` | Step 3 was run **without `--remote`** |
| `summary carries no run_id` | A run recorded before slice 5. Refused on purpose — see `schema.sql` |
| `no such column: trivial` | The migration was never applied -- see *Adding a column* above |
| `Authentication error [code: 10000]` on `/d1/.../import` | `--file` under an OAuth login -- see *Running SQL when `--file` is refused* |

**Then the real check:** play a mission to the end. The run should appear in the first query below,
`user://telemetry/sent/` should hold its folder, and `pending/` should be empty. Alt-F4 mid-mission
and relaunch to see slice 4b and slice 5 together — the swept `CRASHED` run uploads on launch.

---

## Reading the data

Slice 5 ships no dashboard (dev ruling, 2026-09-08: query recipes, not a build). There are two ways
in, and the first is better for looking around.

### The Cloudflare dashboard

**D1 SQL database → `iosis-telemetry` → Console** — paste SQL, press **Execute**, get a table.
There is a **Tables** tab beside it for browsing rows without writing anything at all. This is the
one to reach for when you do not yet know what you are asking.

### wrangler, for questions worth repeating

From `tools/intake-worker/`. `--remote` on every one of these, or you are querying an empty local
copy.

**The exclusion is baked into every recipe below**, because remembering it every time is what
[#851](https://github.com/Phaazoid/Godoiosis/issues/851) exists to stop. It is always the same
clause — `sandbox = 0 and dev_mode = 0 and trivial = 0` — and it is a `WHERE`, so dropping it is
how you see everything again. The last recipe on this page shows you exactly what it removed.

```bash
# the last twenty runs, real play only
wrangler d1 execute iosis-telemetry --remote --command "select run_id, scenario, outcome, rounds, round(seconds) as secs, swept from runs where sandbox = 0 and dev_mode = 0 and trivial = 0 order by received_at desc limit 20"
```

```bash
# how each mission is going: win rate and typical length
wrangler d1 execute iosis-telemetry --remote --command "select scenario, count(*) n, sum(outcome = 'VICTORY') wins, round(avg(rounds), 1) avg_rounds from runs where sandbox = 0 and dev_mode = 0 and trivial = 0 group by scenario order by n desc"
```

```bash
# where people STOP -- QUIT or CRASHED mid-mission is the ragequit signal (#53 slice 4b)
wrangler d1 execute iosis-telemetry --remote --command "select outcome, count(*) n, sum(trivial = 0) played, sum(trivial = 1) barely, round(avg(rounds), 1) avg_rounds from runs where sandbox = 0 and dev_mode = 0 group by outcome order by n desc"
```

**That third one takes `trivial` as a COLUMN rather than a filter, deliberately.** *Someone opened
this mission and left inside one turn* is a finding here, not noise — it is the one question where
the thin runs are the answer — so it splits them out instead of dropping them.

```bash
# what players actually reach for -- straight out of the summary blob, no schema change needed
wrangler d1 execute iosis-telemetry --remote --command "select key as attack, sum(value) uses from runs, json_each(runs.summary, '$.attacks_used') where sandbox = 0 and dev_mode = 0 and trivial = 0 group by key order by uses desc"
```

```bash
# pull one run's raw log back out
wrangler d1 execute iosis-telemetry --remote --command "select events from runs where run_id = 'PASTE_ID'" --json
```

```bash
# WHAT THE EXCLUSION IS DROPPING -- run this before trusting any number above
wrangler d1 execute iosis-telemetry --remote --command "select sandbox, dev_mode, trivial, count(*) n from runs group by sandbox, dev_mode, trivial order by n desc"
```

**Run that last one first, and periodically.** A flag is only better than a deletion while somebody
can still see what it caught: if the excluded pile is most of the table, or is growing faster than
the kept pile, the threshold is wrong and that is a thing you can only learn because nothing was
thrown away. Re-cutting it is one command — see *Adding a column* above.

The attacks-used recipe is the point of storing the summary whole (named rather than numbered, since
that count went stale the moment a recipe was added above it): **a new question is a query, not a build
and a new cohort of players.** Anything `MissionSummary` computes is reachable through
`json_extract(summary, '$.field')` or `json_each` with no schema change — and where the summary
cannot answer, `events` is still there and is the authority.

**Four flags every real query wants.** `sandbox = 1` is a dev sandbox board, `dev_mode = 1` is a
run played with dev mode on, `swept = 1` means the ending was *inferred* at a later launch rather
than watched, and `trivial = 1` means the run was over inside one round or carried fewer than two
player orders. They are flags rather than exclusions on purpose (your ruling, 2026-09-08): an
exclusion destroys the evidence the exclusion was right, and a `WHERE` clause can always be dropped.

**`trivial` is a projection, not a stamp**, and the difference is why the two rows already in this
table from before it existed are classified correctly: it is a `GENERATED ... VIRTUAL` expression
over `rounds` and `orders_queued`, evaluated when you read it. So the threshold can be re-cut over
every run ever collected without a new build, and the raw `rounds` / `passes` / `orders_queued`
columns are all there beside it if you would rather draw the line somewhere else in the query.

**The client refuses one narrow case outright** ([#851](https://github.com/Phaazoid/Godoiosis/issues/851)),
and it is the exception that keeps FLAG-NEVER-EXCLUDE honest rather than a hole in it: a run with
**no** resolved pass and **no** queued order, ended by something somebody chose (`ABANDONED`,
`RESTARTED`, `QUIT`, `INTERRUPTED`), is never uploaded. There is nothing in such a run to lose, so
there is no judgement call to get wrong. A `CRASHED` run is never refused however empty it is —
*the game died before I could do anything* is the most valuable thing this intake can receive.

---

## Limits and what to do when they bite

- **Requests:** 100,000/day free. A demo will not approach this.
- **Body caps:** `MAX_REPORT_BYTES` (8 MB) and `MAX_TELEMETRY_BYTES` (1.8 MB) in `src/index.js`. A
  report is a few hundred KB, almost all of it the PNG; raise it only if Discord's own attachment
  limit for the server allows it. The telemetry number is **not** a guess — D1 caps a *row* at 2 MB,
  and summary + events + board share one row. Measured runs are 30–70 KB, so there is headroom.
- **CPU:** the free plan allows **10 ms per request**, and it is a plan gate, not a config knob.
  Waiting on D1 does not count against it (that is I/O); parsing the multipart body does. If uploads
  start failing with a **1102**, `wrangler tail` reports `CPUTimeMs` per invocation — measure before
  reaching for a fix. In order of cost: stop sending `board.tres`, gzip the events client-side, or
  the $5/month paid plan. **Nothing is lost while you decide** — a refused upload leaves the run in
  `pending/` and it retries at the next launch.
- **D1 storage:** 500 MB per database, 5 GB per account, free. At 70 KB a run that is thousands.
- **Rate limiting** is deliberately not implemented. If the endpoint is ever abused, in order of
  cost: a Cloudflare dashboard rate-limit rule (no code change, no game redeploy), a shared header
  token (redeploy both, and old builds stop reporting), or take the Worker down.
- **Rotating the Discord webhook** is `wrangler secret put DISCORD_WEBHOOK` again. The game is
  unaffected and distributed builds keep working — the capability a plain webhook does not have.

## If this ever needs to scale

- **Bigger runs:** R2 for the `events` blob, keeping the summary in D1. Enabling R2 requires a
  payment method on file even at its free tier, which is why slice 5 is D1-only.
- **A dashboard:** nobody's ticket yet. The schema is shaped for one — every queryable field is a
  generated column over `summary`, so a reader needs no migration to ask something new.
- **Structured report intake:** have the Worker also open an issue in a private intake repo via the
  GitHub API, so reports land in the `/agent-queue` triage workflow instead of in chat. Considered
  and deferred 2026-08-05 — worth revisiting when reading the channel by hand stops being practical.
