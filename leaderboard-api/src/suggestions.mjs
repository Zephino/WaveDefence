/**
 * Anonymous Wave Defence player feedback. Submissions become GitHub Issues using
 * a server-side token; no player account, email, or token is required.
 *
 * Defense in depth: strict field limits, optional honey-pot, per-IP and global
 * daily caps. Cloudflare KV limits are best-effort, not atomic bot protection.
 */
export const SUGGESTION_CATEGORIES = Object.freeze([
  "tower", "enemy", "map", "clash", "balance", "gameplay", "ui", "other",
]);

const MAX_BODY_BYTES = 6000;
const MAX_TITLE = 100;
const MAX_DESCRIPTION = 2000;
const DAILY_IP_LIMIT = 3;
const DAILY_GLOBAL_LIMIT = 40;

const jsonHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Accept",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

function reply(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: jsonHeaders });
}

/**
 * Treat all player text as untrusted. Keep useful natural language (including
 * quotes and semicolons) while removing non-printing/spoofing controls.
 * The Worker uses KV + GitHub Issues, not SQL queries. If a SQL store is ever
 * introduced, use bound parameters; string filtering is NOT SQLi prevention.
 */
function clean(value) {
  if (typeof value !== "string") return "";
  return value.normalize("NFC")
    .replace(/\r\n?|\u2028|\u2029/g, "\n")
    .replace(/\t/g, " ")
    .replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g, "")
    .replace(/@/g, "＠")
    .trim();
}

/**
 * Only accept broad, known device categories. Never accept or store a raw
 * user-agent, device identifier, IP address, or arbitrary client metadata.
 * Client-provided values are diagnostic hints, not trusted facts.
 */
function normalizeClientInfo(client) {
  if (!client || typeof client !== "object" || Array.isArray(client)) return null;
  const category = (value, permitted) => permitted.includes(clean(value)) ? clean(value) : "Unknown";
  const version = clean(client.game_version);
  return {
    game_version: /^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$/.test(version) ? version : "Unknown",
    runtime: category(client.runtime, ["Web", "Native"]),
    device_type: category(client.device_type, ["Desktop", "Phone", "Tablet"]),
    platform: category(client.platform, ["Windows", "macOS", "Linux", "ChromeOS", "Android", "iOS", "FreeBSD", "Unknown"]),
    browser: category(client.browser, ["Chrome", "Edge", "Firefox", "Safari", "Opera", "Samsung Internet", "Other", "N/A", "Unknown"]),
  };
}

export function validateSuggestion(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return { error: "invalid suggestion" };
  }
  // Invisible spam trap; normal in-game form always sends an empty string.
  if (body.website !== undefined && body.website !== "") {
    return { error: "invalid suggestion" };
  }
  const category = clean(body.category);
  const title = clean(body.title).replace(/\s+/g, " ");
  const description = clean(body.description);
  if (!SUGGESTION_CATEGORIES.includes(category)) return { error: "invalid category" };
  if (title.length < 5 || title.length > MAX_TITLE) return { error: "title must be 5–100 characters" };
  if (description.length < 20 || description.length > MAX_DESCRIPTION) {
    return { error: "description must be 20–2000 characters" };
  }
  if ((description.match(/https?:\/\//gi) || []).length > 2) {
    return { error: "too many links" };
  }
  return { category, title, description, client: normalizeClientInfo(body.client) };
}

/** Escape suggestion content before inserting it in a GitHub Markdown issue. */
function escapeIssueText(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/([\\\x60*_{}\[\]()#+.!|~-])/g, "\\$1");
}

function markdownQuote(text) {
  return escapeIssueText(text).split("\n").map((line) => "> " + line).join("\n");
}

async function keyFor(ip, env, day) {
  // Hash identifiers in KV so raw IP addresses aren't stored as keys.
  const input = new TextEncoder().encode(`${day}:${ip}:${env.GITHUB_TOKEN}`);
  const digest = await crypto.subtle.digest("SHA-256", input);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function suggestionStatus(env) {
  return reply({ accepting: Boolean(env.GITHUB_TOKEN && env.LEADERBOARD_KV) });
}

/**
 * Request handler, factored so tests can inject a fake GitHub fetch.
 * A GitHub 201 response is the only success: never claim a suggestion
 * was delivered when GitHub rejected it or the Worker is unconfigured.
 */
export async function handleSuggestionPost(request, env, ip, githubFetch = fetch) {
  if (!env.GITHUB_TOKEN || !env.LEADERBOARD_KV) {
    return reply({ error: "suggestion service not configured" }, 503);
  }
  const declared = Number(request.headers.get("content-length") || 0);
  if (declared > MAX_BODY_BYTES) return reply({ error: "message too large" }, 413);
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
    return reply({ error: "message too large" }, 413);
  }
  let incoming;
  try { incoming = JSON.parse(raw); }
  catch { return reply({ error: "invalid json" }, 400); }

  const checked = validateSuggestion(incoming);
  if (checked.error) return reply({ error: checked.error }, 400);

  const day = new Date().toISOString().slice(0, 10);
  const ipKey = "suggest:ip:" + await keyFor(ip, env, day);
  const globalKey = "suggest:global:" + day;
  const [ipCount, globalCount] = await Promise.all([
    env.LEADERBOARD_KV.get(ipKey),
    env.LEADERBOARD_KV.get(globalKey),
  ]);
  if (Number(ipCount || 0) >= DAILY_IP_LIMIT || Number(globalCount || 0) >= DAILY_GLOBAL_LIMIT) {
    return reply({ error: "daily submission limit reached; try again tomorrow" }, 429);
  }

  const owner = env.GITHUB_OWNER || "Zephino";
  const repo = env.GITHUB_REPO || "WaveDefence";
  const issue = {
    title: `[Player suggestion] ${checked.title}`,
    body: [
      "Anonymous suggestion from the **Wave Defence** main menu.",
      "",
      `**Category:** ${checked.category}`,
      "",
      "**Automatically attached game details:**",
      ...(checked.client ? [
        `- Game version: ${checked.client.game_version}`,
        `- Run target: ${checked.client.runtime}`,
        `- Device type: ${checked.client.device_type}`,
        `- Operating system: ${checked.client.platform}`,
        `- Browser: ${checked.client.browser}`,
      ] : ["- Not provided (older game build)"]),
      "",
      "**Suggestion:**",
      markdownQuote(checked.description),
      "",
      "*Submitted without a player account. Please do not post personal information.*",
    ].join("\n"),
  };
  let response;
  try {
    response = await githubFetch(`https://api.github.com/repos/${owner}/${repo}/issues`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
        "User-Agent": "wave-defence-feedback-worker",
      },
      body: JSON.stringify(issue),
    });
  } catch {
    return reply({ error: "could not reach the suggestion service" }, 502);
  }
  if (response.status !== 201) {
    // Return a safe actionable diagnostic without exposing the token, GitHub
    // response body, user-agent or other request metadata.
    console.log("Create GitHub issue failed:", response.status);
    let error = "GitHub could not save the suggestion (status " + response.status + ").";
    if (response.status === 401) {
      error = "The feedback service's GitHub token is invalid or expired (401). The developer must update the GITHUB_TOKEN secret.";
    } else if (response.status === 403) {
      error = "GitHub denied the feedback service (403). The developer should check that the token has Issues: Read and write permission for Zephino/WaveDefence.";
    } else if (response.status === 404) {
      error = "GitHub repository access failed (404). The developer should check repository access for the token and that Issues are enabled.";
    } else if (response.status === 422) {
      error = "GitHub rejected the issue submission (422). Please notify the developer.";
    }
    return reply({ error }, 502);
  }

  // Caps are intentionally best-effort: KV read-modify-write is not atomic.
  try {
    await Promise.all([
      env.LEADERBOARD_KV.put(ipKey, String(Number(ipCount || 0) + 1), { expirationTtl: 90000 }),
      env.LEADERBOARD_KV.put(globalKey, String(Number(globalCount || 0) + 1), { expirationTtl: 90000 }),
    ]);
  } catch (err) {
    console.log("Suggestion rate counter write failed:", String(err));
  }
  const result = await response.json().catch(() => ({}));
  return reply({ accepted: true, issue_number: Number(result.number || 0) }, 201);
}
