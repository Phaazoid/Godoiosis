// Iosis report intake (#131).
//
// A pure relay: it takes the multipart/form-data POST the game sends and forwards it to a Discord
// webhook unchanged. The point is WHERE THE TOKEN LIVES -- as a Worker secret here rather than
// inside the exported pack, so it can be rotated without re-exporting the game, and so abuse can
// be filtered here instead of forcing you to delete the only credential.
//
// Deploy: see ../README.md. Requires one secret, DISCORD_WEBHOOK.

const MAX_BYTES = 8 * 1024 * 1024;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (request.method !== "POST") {
      return text("POST only", 405);
    }

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
    if (body.byteLength > MAX_BYTES) {
      return text(`body ${body.byteLength} exceeds ${MAX_BYTES}`, 413);
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
  },
};

function text(message, status) {
  return new Response(message, { status, headers: corsHeaders() });
}

// Not needed by a desktop build, but a Godot web export would be blocked without it.
function corsHeaders() {
  return {
    "content-type": "text/plain; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}
