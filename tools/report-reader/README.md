# Bug report reader (#131 follow-up)

A read-only companion to `tools/report-worker/`: pulls the reports that worker relays into Discord
back out again, so reading the channel by hand isn't the only way to see what testers filed. Built
at the point the #131 README flagged — "revisit when reading the channel by hand stops being
practical."

Talks to Discord directly via a bot's REST API (`GET /channels/{id}/messages`). No gateway
connection, no new server, nothing added to the game or the Worker.

## One-time setup

**1 · Create a Discord bot application.**
[discord.com/developers/applications](https://discord.com/developers/applications) → **New
Application**. Open its **Bot** tab, reset/copy the token.

**2 · Enable Message Content Intent.**
Same **Bot** tab → **Privileged Gateway Intents** → turn on **Message Content Intent** → Save.
Without this, Discord silently returns every message with empty `content`/`attachments` — no error,
just nothing to read. No app review needed for a bot in one server.

**3 · Invite it to the reports channel, read-only.**
**OAuth2** tab → URL Generator → scope `bot` → permissions `View Channels` + `Read Message History`
only (no send, no manage). Open the generated URL, pick the server, authorize.

**4 · Get the channel ID.**
Discord → User Settings → Advanced → **Developer Mode** on. Right-click the reports channel →
**Copy Channel ID**.

**5 · Store credentials OUTSIDE the repo.** Godoiosis is public — same reasoning as the webhook URL
in #131. Create `%USERPROFILE%\.iosis-secrets\discord-bot.env`:

```
DISCORD_BOT_TOKEN=<bot token from step 1>
DISCORD_CHANNEL_ID=<channel id from step 4>
```

This path is never created or read by anything else in this repo, and `.iosis-secrets` is outside
`Godoiosis/` entirely, so there is no `.gitignore` to maintain for it.

## Usage

```powershell
tools/report-reader/read-bug-reports.ps1
```

Prints every report posted since the last run (note text, full `report.md` body, and links to
`report.md`/`board.tres`/`board.png`), then remembers the newest message ID it showed.

- `-All` — show the most recent reports regardless of what's already been seen. Does not update the
  saved position, so a later plain run still picks up where it left off.
- `-Limit N` — how many recent Discord messages to consider (default 25, Discord's cap is 100).
- `-NoFetch` — skip downloading each `report.md` body; just print the note and attachment links.

State (the last-seen message ID) lives beside the credentials, in
`%USERPROFILE%\.iosis-secrets\discord-bot-state.json`.

## If this ever needs to scale

Same note as the Worker's README: the next step up is the Worker also opening an issue in a private
intake repo via the GitHub API, landing reports in the `/agent-queue` triage workflow instead of in
chat. Still not needed at current tester volume. *(Reworded 2026-08-25: this used to name the
`agent/claude` label, retired that day — a filed report is picked up because nobody has replied to it
yet, which the queue derives from the thread.)*
