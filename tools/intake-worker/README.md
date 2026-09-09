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

**3 · Create the table.**

```bash
wrangler d1 execute iosis-telemetry --remote --file=schema.sql
```

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
curl -X POST -F 'summary={"event":"summary","summary":{"run_id":"smoke-1","scenario":"x","outcome":"VICTORY","rounds":3}}' -F "events.jsonl=@schema.sql" https://iosis-reports.<your-subdomain>.workers.dev/telemetry
```

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

```bash
# the last twenty runs, real play only
wrangler d1 execute iosis-telemetry --remote --command "select run_id, scenario, outcome, rounds, round(seconds) as secs, swept from runs where sandbox = 0 and dev_mode = 0 order by received_at desc limit 20"
```

```bash
# how each mission is going: win rate and typical length
wrangler d1 execute iosis-telemetry --remote --command "select scenario, count(*) n, sum(outcome = 'VICTORY') wins, round(avg(rounds), 1) avg_rounds from runs where sandbox = 0 group by scenario order by n desc"
```

```bash
# where people STOP -- QUIT or CRASHED mid-mission is the ragequit signal (#53 slice 4b)
wrangler d1 execute iosis-telemetry --remote --command "select outcome, count(*) n, round(avg(rounds), 1) avg_rounds from runs where sandbox = 0 group by outcome order by n desc"
```

```bash
# what players actually reach for -- straight out of the summary blob, no schema change needed
wrangler d1 execute iosis-telemetry --remote --command "select key as attack, sum(value) uses from runs, json_each(runs.summary, '$.attacks_used') where sandbox = 0 group by key order by uses desc"
```

```bash
# pull one run's raw log back out
wrangler d1 execute iosis-telemetry --remote --command "select events from runs where run_id = 'PASTE_ID'" --json
```

That fourth one is the point of storing the summary whole: **a new question is a query, not a build
and a new cohort of players.** Anything `MissionSummary` computes is reachable through
`json_extract(summary, '$.field')` or `json_each` with no schema change — and where the summary
cannot answer, `events` is still there and is the authority.

**Three flags every real query wants.** `sandbox = 1` is a dev sandbox board, `dev_mode = 1` is a
run played with dev mode on, and `swept = 1` means the ending was *inferred* at a later launch
rather than watched. They are flags rather than exclusions on purpose (your ruling, 2026-09-08): an
exclusion destroys the evidence the exclusion was right, and a `WHERE` clause can always be dropped.

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
