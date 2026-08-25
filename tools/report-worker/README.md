# Iosis report intake Worker (#131)

A ~50-line Cloudflare Worker that relays the game's report POST to a Discord webhook.

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
Run this from `tools/report-worker/`. It prompts for the value — paste the webhook URL.

```bash
wrangler secret put DISCORD_WEBHOOK
```

**4 · Deploy.**

```bash
wrangler deploy
```

It prints the live URL, of the form `https://iosis-reports.<your-subdomain>.workers.dev`.

**5 · Point the game at it.**
Paste that URL into `ENDPOINT` in `Classes/net/ReportUploader.gd` — **the Worker's URL, not the
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
| `DISCORD_WEBHOOK secret is not set` | Step 3 was skipped, or was run outside `tools/report-worker/` |
| `discord 401` | The webhook was deleted or the URL was pasted with a truncation |
| `discord 404` | Same — Discord returns 404 for a webhook id that no longer exists |
| `expected multipart/form-data` | `curl -d` was used instead of `-F` |

## Limits and what to do when they bite

- **Free tier:** 100,000 requests/day. A demo will not approach this.
- **Body cap:** `MAX_BYTES` in `src/index.js`, currently 8 MB. A report is a few hundred KB — almost
  all of it the PNG. Raise it only if Discord's own attachment limit for the server allows it.
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
