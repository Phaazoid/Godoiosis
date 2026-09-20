// Iosis intake (#131, widened by #53 slice 5).
//
// One Worker, two tenants, routed on PATH:
//
//   ""           the bug-report relay -- takes the multipart POST the game sends and forwards it to
//                a Discord webhook unchanged. The point is WHERE THE TOKEN LIVES: a Worker secret
//                here rather than inside the exported pack, so it rotates without re-exporting the
//                game, and abuse can be filtered here instead of forcing you to delete the only
//                credential.
//   "/telemetry" the playtest run intake -- one row per run in D1. It parses ONLY the small summary
//                field and stores events and board verbatim, which is what keeps a free-plan Worker
//                inside its 10 ms CPU budget. Never relayed to Discord: a message per finished
//                mission would drown the channel the reports live in.
//
// THE ROUTE IS DECIDED BEFORE ANYTHING ELSE, and that ordering is the one that matters -- each
// handler owns its own content-type check and its own size cap, so a future route shaped
// differently is not unreachable behind somebody else's 415.
//
// AN UNMATCHED PATH IS A 404, NEVER A FALL-THROUGH to the report relay. Cloudflare normalizes
// doubled slashes and nothing else, so "/telemetry/" is a real string a client can send -- and
// under a default-to-report branch that would have been posted to Discord as a bug report,
// silently, with no row written.
//
// Deploy: see ../README.md. Requires the DISCORD_WEBHOOK secret and the DB (D1) binding.

const MAX_REPORT_BYTES = 8 * 1024 * 1024;

// D1 caps a ROW at 2,000,000 bytes, and summary + events + board share one row -- so the budget is
// the whole payload's, not each part's. The client checks the same number before sending; this is
// the half that does not depend on the client being honest.
const MAX_TELEMETRY_BYTES = 1_800_000;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    // THE METHOD CHECK BELONGS TO THE ROUTE, not to the door (#1060). A blanket "POST only" sat
    // here above the dispatch, which was right while every route was a POST -- /version is a GET,
    // and it would have been refused before routing ever ran.
    const path = new URL(request.url).pathname.replace(/\/+$/, "");
    if (path === "/telemetry") return only("POST", request, handleTelemetry, env);
    if (path === "/version") return only("GET", request, handleVersion, env);
    if (path === "") return only("POST", request, handleReport, env);
    return text(`no such route: ${path}`, 404);
  },
};

function only(method, request, handler, env) {
  if (request.method !== method) return text(`${method} only`, 405);
  return handler(request, env);
}

// --- the report relay (#131), unchanged in behaviour ---

async function handleReport(request, env) {
  if (!env.DISCORD_WEBHOOK) {
    // Loud rather than silent: a missing secret otherwise looks exactly like a network failure
    // from the game's side, and you would go hunting in the wrong place.
    return text("DISCORD_WEBHOOK secret is not set on this Worker", 500);
  }

  const contentType = request.headers.get("content-type") || "";
  if (!contentType.startsWith("multipart/form-data")) {
    return text("expected multipart/form-data", 415);
  }

  // Buffer rather than stream: Discord wants a content-length, and reading it here is what makes
  // the cap real -- a declared content-length header is not something a caller has to be honest about.
  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_REPORT_BYTES) {
    return text(`body ${body.byteLength} exceeds ${MAX_REPORT_BYTES}`, 413);
  }

  // The boundary lives inside contentType, so passing it through untouched is what keeps the
  // relay a relay -- nothing here parses or rewrites the parts.
  const upstream = await fetch(env.DISCORD_WEBHOOK, {
    method: "POST",
    headers: { "content-type": contentType },
    body,
  });

  if (!upstream.ok) {
    const detail = await upstream.text().catch(() => "");
    return text(`discord ${upstream.status} ${detail}`.trim(), 502);
  }

  return text("ok", 200);
}

// --- the run intake (#53 slice 5) ---

async function handleTelemetry(request, env) {
  if (!env.DB) {
    // DISCORD_WEBHOOK's rule, for the same reason: a missing binding must not read as a network
    // fault at the far end.
    return text("DB (D1) binding is not set on this Worker", 500);
  }

  const contentType = request.headers.get("content-type") || "";
  if (!contentType.startsWith("multipart/form-data")) {
    return text("expected multipart/form-data", 415);
  }

  const form = await request.formData();

  // The one thing parsed here. The game sends the run's `summary` LINE verbatim -- envelope and
  // all -- so what the row wants is one level in.
  const line = form.get("summary");
  if (typeof line !== "string") return text("no summary field", 400);
  let summary;
  try {
    summary = JSON.parse(line).summary;
  } catch (e) {
    return text(`summary is not JSON: ${e.message}`, 400);
  }
  // The PRIMARY KEY, and the schema declares it NOT NULL: SQLite would otherwise accept NULL in a
  // TEXT PRIMARY KEY and treat every NULL as distinct, so runs recorded before the id existed
  // would each land as their own garbage row instead of being refused here.
  if (!summary || typeof summary.run_id !== "string" || summary.run_id === "") {
    return text("summary carries no run_id", 400);
  }

  // .text() decodes as UTF-8 whatever the part declares, substituting U+FFFD silently on anything
  // else. Both files are UTF-8 by construction -- a text .tres out of ResourceSaver, and
  // JSON.stringify through store_line -- and TEXT is what makes `wrangler d1 execute` readable,
  // which is the read path this slice ships. The day either stops being text, they become
  // arrayBuffer() into BLOB columns.
  const events = await partText(form, "events.jsonl");
  if (events === null) return text("no events.jsonl part", 400);
  const board = await partText(form, "board.tres");

  const total = line.length + events.length + (board ? board.length : 0);
  if (total > MAX_TELEMETRY_BYTES) {
    return text(`payload ${total} exceeds ${MAX_TELEMETRY_BYTES}`, 413);
  }

  // BOUND PARAMETERS, never an inlined value: D1 caps a STATEMENT at 100,000 bytes while a bound
  // value is governed by the 2 MB row limit instead. An upsert rather than INSERT OR REPLACE,
  // which SQLite runs as delete-then-insert -- nothing here would notice today, and this is the
  // one that stays right if the table ever grows a trigger. Either way a retry after a lost
  // response is idempotent, which is what lets the client retry blindly at every launch.
  await env.DB.prepare(
    `INSERT INTO runs (run_id, received_at, summary, events, board)
     VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT(run_id) DO UPDATE SET
       received_at = excluded.received_at,
       summary     = excluded.summary,
       events      = excluded.events,
       board       = excluded.board`
  ).bind(summary.run_id, new Date().toISOString(), JSON.stringify(summary), events, board).run();

  return text("ok", 200);
}

// --- the latest build (#1060) ---

// WHAT THE GAME ASKS ON EVERY LAUNCH. One row, written at release time by tools/archive-build.ps1
// with wrangler as the account owner -- so there is no write route here, no token, and no secret
// compiled into anything (pull-runs.ps1's ruling, applied to a write instead of a read).
//
// THE URL IS IN THE PAYLOAD DELIBERATELY. A const in the game would be frozen into every build
// already in someone's hands, so moving off itch is an UPDATE here rather than a re-export.
async function handleVersion(request, env) {
  if (!env.DB) {
    return text("DB (D1) binding is not set on this Worker", 500);
  }
  const row = await env.DB.prepare(
    "SELECT version, url FROM release WHERE id = 1"
  ).first();
  if (!row) {
    // No release announced yet. Not an error -- the game reads anything but 200 as "stay quiet",
    // which is the right answer before the first butler push has ever run.
    return text("no release recorded", 404);
  }
  return new Response(JSON.stringify({ version: row.version, url: row.url }), {
    status: 200,
    headers: { ...corsHeaders(), "content-type": "application/json; charset=utf-8" },
  });
}

async function partText(form, name) {
  const part = form.get(name);
  if (part === null) return null;
  return typeof part === "string" ? part : await part.text();
}

// --- shared ---

function text(message, status) {
  return new Response(message, { status, headers: corsHeaders() });
}

// Not needed by a desktop build, but a Godot web export would be blocked without it.
function corsHeaders() {
  return {
    "content-type": "text/plain; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}
