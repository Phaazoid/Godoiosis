# Iosis intake Worker (#131, #53 slice 5)

One Cloudflare Worker with two tenants, routed on path: `` (the root) relays a bug report to a
Discord webhook, and `/telemetry` writes a recorded playtest run into D1.

The game never learns the Discord webhook URL. It knows only this Worker's address, which is not a
secret — it is just where reports go. That is the whole point: the Discord token can be rotated,
and abuse can be filtered, without re-exporting the game.

`tools/` is in `export_presets.cfg`'s `exclude_filter`, so nothing here ships in a build.

## One-time setup

**1 · Make the Discord webhook.**
In the Discord server you want reports in: Server Settings → Integrations → Webhooks → New Webhook.
Point it at a channel you own (a dedicated `#playtest-reports` is worth it — this channel will get
screenshots). Copy the URL; it looks like `https://discord.com/api/webhooks/<id>/<token>`.

**2 · Install wrangler and log in.**

```bash
npm install -g wrangler
```

```bash
wrangler login
```

`wrangler login` opens a browser to authorize; a free Cloudflare account is enough and no payment
method is needed for a Worker with no storage bindings.

**3 · Store the webhook as a secret.**
Run this from `tools/intake-worker/`. It prompts for the value — paste the webhook URL.

```bash
wrangler secret put DISCORD_WEBHOOK
```

**4 · Create the telemetry database and its schema.**
D1 is free and needs **no payment method** — that is why the run intake is D1 and not R2.

```bash
wrangler d1 create iosis-telemetry
```

Paste the `database_id` it prints into `wrangler.toml`'s `[[d1_databases]]` block, replacing
`REPLACE_ME`. Then create the table:

```bash
wrangler d1 execute iosis-telemetry --remote --file=schema.sql
```

`--remote` is not optional — without it wrangler writes to a **local** SQLite file that the
deployed Worker never sees, and the first real upload fails with `no such table: runs`.

**5 · Deploy.**

```bash
wrangler deploy
```

It prints the live URL, of the form `https://iosis-reports.<your-subdomain>.workers.dev`.

**6 · Point the game at it.**
Paste that URL into `ENDPOINT` in `Classes/net/Uploader.gd` — **the Worker's URL, not the
Discord webhook**, and note the Worker sits one level below your account subdomain
(`<worker-name>.<account-subdomain>.workers.dev`). Deployed as of 2026-08-05:
`https://iosis-reports.phlogiston-games.workers.dev`.

An empty `ENDPOINT` disables upload and leaves reports local-only. It is **not** how the test suite
is kept quiet, though — `is_configured()` refuses any headless run, because the endpoint in the
committed source is live and an unguarded suite would post into the channel on every green run.

## Verifying it before touching the game

This proves the Worker independently, so a later failure in-game is unambiguously the game's side.

```bash
curl -X POST -F "payload_json={\"content\":\"worker smoke test\"}" -F "files[0]=@wrangler.toml" https://iosis-reports.<your-subdomain>.workers.dev
```

Expect `ok` on stdout and a message with an attachment in the channel. Common failures:

| Response | Cause |
| --- | --- |
| `DISCORD_WEBHOOK secret is not set` | Step 3 was skipped, or was run outside `tools/intake-worker/` |
| `discord 401` | The webhook was deleted or the URL was pasted with a truncation |
| `discord 404` | Same — Discord returns 404 for a webhook id that no longer exists |
| `expected multipart/form-data` | `curl -d` was used instead of `-F` |
| `no such route: /report` | Only `` and `/telemetry` exist; an unmatched path is a 404 rather than a fall-through |

And the telemetry route, which needs no Discord at all:

```bash
curl -X POST -F 'summary={"event":"summary","summary":{"run_id":"smoke-1","scenario":"x","outcome":"VICTORY","rounds":3}}' -F "events.jsonl=@schema.sql" https://iosis-reports.<your-subdomain>.workers.dev/telemetry
```

Expect `ok`, then `select run_id, scenario, outcome, rounds from runs` (below) should show it.
Delete the smoke row with `delete from runs where run_id = 'smoke-1'`.

| Response | Cause |
| --- | --- |
| `DB (D1) binding is not set` | Step 4 was skipped, or `database_id` is still `REPLACE_ME` |
| `no such table: runs` | `wrangler d1 execute` was run without `--remote` |
| `summary carries no run_id` | A run recorded before #53 slice 5; it is refused on purpose |

## Reading the data

Slice 5 ships no dashboard — the CLI is the read path (dev ruling, 2026-09-08). Every one of these
runs against the deployed database with `--remote`; drop it to query a local copy.

```bash
# the last twenty runs, real play only
wrangler d1 execute iosis-telemetry --remote --command "select run_id, scenario, outcome, rounds, round(seconds) as secs, swept from runs where sandbox = 0 and dev_mode = 0 order by received_at desc limit 20"
```

```bash
# how each mission is going: win rate and typical length
wrangler d1 execute iosis-telemetry --remote --command "select scenario, count(*) n, sum(outcome = 'VICTORY') wins, round(avg(rounds), 1) avg_rounds from runs where sandbox = 0 group by scenario order by n desc"
```

```bash
# where people STOP -- a quit or a crash mid-mission is the ragequit signal (#53 slice 4b)
wrangler d1 execute iosis-telemetry --remote --command "select outcome, count(*) n, round(avg(rounds), 1) avg_rounds from runs where sandbox = 0 group by outcome order by n desc"
```

```bash
# what players actually reach for -- straight out of the summary blob, no schema change needed
wrangler d1 execute iosis-telemetry --remote --command "select key as attack, sum(value) uses from runs, json_each(runs.summary, '$.attacks_used') where sandbox = 0 group by key order by uses desc"
```

That last one is the point of storing the summary whole: **a new question is a query, not a build
and a new cohort of players.** Anything `MissionSummary` computes is reachable through
`json_extract(summary, '$.field')` or `json_each` without touching this schema — and if the summary
itself cannot answer it, `events` is still there and is the authority.

```bash
# pull one run's raw log back out
wrangler d1 execute iosis-telemetry --remote --command "select events from runs where run_id = 'PASTE_ID'" --json
```

## Limits and what to do when they bite

- **Free tier:** 100,000 requests/day. A demo will not approach this.
- **Body caps:** `MAX_REPORT_BYTES` (8 MB) and `MAX_TELEMETRY_BYTES` (1.8 MB) in `src/index.js`. A
  report is a few hundred KB, almost all of it the PNG; raise it only if Discord's own attachment
  limit for the server allows it. The telemetry number is **not** a guess — D1 caps a *row* at 2 MB
  and summary + events + board share one row, so that is the real ceiling. Measured runs are 30–70 KB.
- **CPU:** the free plan allows **10 ms per request**, and it is a plan gate, not a config knob.
  Waiting on D1 does not count (it is I/O); parsing the multipart body does. If uploads start
  failing with a 1102, `wrangler tail` reports `CPUTimeMs` per invocation — check it before
  reaching for a fix. In order of cost: stop sending `board.tres`, gzip the events client-side, or
  the $5/month paid plan.
- **D1 free tier:** 500 MB per database, 5 GB per account. At 70 KB a run that is thousands of runs.
- **Rate limiting** is deliberately not implemented. If the endpoint is ever abused, the options in
  order of cost are: add a Cloudflare dashboard rate-limit rule (no code change, no redeploy of the
  game), require a shared header token (a redeploy of both, and old builds stop reporting), or take
  the Worker down (reports stop, Discord is untouched).
- **Rotating the Discord webhook** is `wrangler secret put DISCORD_WEBHOOK` again. The game is
  unaffected and already-distributed builds keep working. This is the capability the plain-webhook
  approach does not have.

## If this ever needs to scale

The relay is the smallest useful version. The two upgrades it was shaped to accept:

- **Archive:** add an R2 binding and write each request body to a bucket before forwarding, giving a
  queryable history. Enabling R2 requires a payment method on file even at the free tier.
- **Structured intake:** have the Worker also open an issue in a private intake repo via the GitHub
  API, so reports land in the `/agent-queue` triage workflow instead of in chat. This was considered
  and deferred on 2026-08-05 — worth revisiting at the point where reading the channel by hand stops
  being practical. *(Reworded 2026-08-25: this used to name the `agent/claude` label, retired that
  day — an auto-filed report would be picked up because nobody has replied to it yet, which the queue
  now derives from the thread rather than from a label.)*
