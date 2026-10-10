/**
 * Wave Defence shared leaderboard Worker.
 * GET/POST /leaderboard — stores in KV and commits leaderboard.json to GitHub.
 *
 * Secrets: GITHUB_TOKEN (contents:write on Zephino/WaveDefence)
 * Bindings: LEADERBOARD_KV
 * Vars: GITHUB_OWNER, GITHUB_REPO, GITHUB_PATH, GITHUB_BRANCH
 */

const MAX_ENTRIES = 10;
const MAX_NAME_LENGTH = 12;
const MAX_WAVE = 100000;
const BOARD_KEYS = ["easy", "medium", "hard"];
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 30;

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Accept",
    "Content-Type": "application/json; charset=utf-8",
  };
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders() });
}

function emptyBoards() {
  return { easy: [], medium: [], hard: [] };
}

function sanitizeName(raw) {
  let cleaned = "";
  const s = String(raw ?? "");
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    const code = ch.charCodeAt(0);
    const ok =
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      (code >= 48 && code <= 57) ||
      ch === " " ||
      ch === "_" ||
      ch === "-";
    if (ok) cleaned += ch;
  }
  cleaned = cleaned.trim();
  if (cleaned.length > MAX_NAME_LENGTH) cleaned = cleaned.slice(0, MAX_NAME_LENGTH);
  return cleaned;
}

const MAX_SEEDS = 40;

function normalizeSeeds(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const item of raw) {
    const n = parseInt(item, 10);
    if (!Number.isFinite(n) || n < 0) continue;
    out.push(n);
    if (out.length >= MAX_SEEDS) break;
  }
  return out;
}

function normalizeEntry(item) {
  if (!item || typeof item !== "object") return null;
  const name = sanitizeName(item.name);
  const wave = Math.max(0, parseInt(item.wave, 10) || 0);
  if (!name || wave <= 0) return null;
  const seeds = normalizeSeeds(item.seeds);
  const entry = { name, wave };
  if (seeds.length) entry.seeds = seeds;
  return entry;
}

function sortAndTrim(entries) {
  const cleaned = [];
  for (const item of entries || []) {
    const e = normalizeEntry(item);
    if (e) cleaned.push(e);
  }
  cleaned.sort((a, b) => b.wave - a.wave);
  return cleaned.slice(0, MAX_ENTRIES);
}

function normalizeBoards(raw) {
  const boards = emptyBoards();
  if (!raw || typeof raw !== "object") return boards;
  for (const key of BOARD_KEYS) {
    boards[key] = sortAndTrim(raw[key]);
  }
  return boards;
}

function difficultyKey(value) {
  const s = String(value ?? "medium").toLowerCase();
  if (s === "easy" || s === "0") return "easy";
  if (s === "hard" || s === "2") return "hard";
  return "medium";
}

async function rateLimit(env, ip) {
  if (!env.LEADERBOARD_KV) return true;
  const key = `rl:${ip}`;
  const now = Date.now();
  let data = { t: now, n: 0 };
  try {
    const existing = await env.LEADERBOARD_KV.get(key, { type: "json" });
    if (existing && typeof existing === "object") data = existing;
  } catch (_) {}
  if (now - (data.t || 0) > RATE_LIMIT_WINDOW_MS) {
    data = { t: now, n: 0 };
  }
  data.n = (data.n || 0) + 1;
  await env.LEADERBOARD_KV.put(key, JSON.stringify(data), { expirationTtl: 120 });
  return data.n <= RATE_LIMIT_MAX;
}

async function loadBoards(env) {
  if (env.LEADERBOARD_KV) {
    const cached = await env.LEADERBOARD_KV.get("boards", { type: "json" });
    if (cached) return normalizeBoards(cached);
  }
  const owner = env.GITHUB_OWNER || "Zephino";
  const repo = env.GITHUB_REPO || "WaveDefence";
  const path = env.GITHUB_PATH || "leaderboard.json";
  const branch = env.GITHUB_BRANCH || "data";
  const url = `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${path}`;
  const res = await fetch(url, { headers: { Accept: "application/json" } });
  if (!res.ok) return emptyBoards();
  try {
    const data = await res.json();
    return normalizeBoards(data);
  } catch (err) {
    console.log("loadBoards JSON parse failed:", String(err));
    return emptyBoards();
  }
}

async function saveBoards(env, boards) {
  const normalized = normalizeBoards(boards);
  if (env.LEADERBOARD_KV) {
    await env.LEADERBOARD_KV.put("boards", JSON.stringify(normalized));
  }
  await commitToGitHub(env, normalized);
  return normalized;
}

async function commitToGitHub(env, boards) {
  const token = env.GITHUB_TOKEN;
  if (!token) {
    console.log("GITHUB_TOKEN missing — skipped GitHub commit");
    return;
  }
  const owner = env.GITHUB_OWNER || "Zephino";
  const repo = env.GITHUB_REPO || "WaveDefence";
  const path = env.GITHUB_PATH || "leaderboard.json";
  const branch = env.GITHUB_BRANCH || "data";
  const api = `https://api.github.com/repos/${owner}/${repo}/contents/${path}`;
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "User-Agent": "wave-defence-leaderboard-worker",
    "Content-Type": "application/json",
  };
  let sha = undefined;
  const getRes = await fetch(`${api}?ref=${branch}`, { headers });
  if (getRes.ok) {
    const meta = await getRes.json();
    sha = meta.sha;
  }
  const content = btoa(unescape(encodeURIComponent(JSON.stringify(boards, null, "\t") + "\n")));
  const putRes = await fetch(api, {
    method: "PUT",
    headers,
    body: JSON.stringify({
      message: "Update shared leaderboard",
      content,
      branch,
      sha,
    }),
  });
  if (!putRes.ok) {
    const text = await putRes.text();
    console.log("GitHub commit failed:", putRes.status, text);
  }
}

export default {
  async fetch(request, env) {
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: corsHeaders() });
      }

      const url = new URL(request.url);
      if (url.pathname !== "/leaderboard" && url.pathname !== "/") {
        return jsonResponse({ error: "not found" }, 404);
      }

      const ip = request.headers.get("CF-Connecting-IP") || "unknown";
      try {
        if (!(await rateLimit(env, ip))) {
          return jsonResponse({ error: "rate limited" }, 429);
        }
      } catch (err) {
        console.log("rateLimit failed:", String(err));
      }

      if (request.method === "GET") {
        const boards = await loadBoards(env);
        return jsonResponse(boards);
      }

      if (request.method === "POST") {
        let body;
        try {
          body = await request.json();
        } catch {
          return jsonResponse({ error: "invalid json" }, 400);
        }
        const name = sanitizeName(body.name);
        const wave = parseInt(body.wave, 10) || 0;
        const key = difficultyKey(body.difficulty);
        const seeds = normalizeSeeds(body.seeds);
        if (!name) return jsonResponse({ error: "invalid name" }, 400);
        if (wave <= 0 || wave > MAX_WAVE) return jsonResponse({ error: "invalid wave" }, 400);

        const boards = await loadBoards(env);
        const entries = boards[key] || [];
        const qualifies =
          entries.length < MAX_ENTRIES || wave >= (entries[MAX_ENTRIES - 1]?.wave ?? 0);
        if (!qualifies) {
          return jsonResponse(boards);
        }
        const row = { name, wave };
        if (seeds.length) row.seeds = seeds;
        entries.push(row);
        boards[key] = sortAndTrim(entries);
        const saved = await saveBoards(env, boards);
        return jsonResponse(saved);
      }

      return jsonResponse({ error: "method not allowed" }, 405);
    } catch (err) {
      console.log("worker error:", String(err && err.stack ? err.stack : err));
      return jsonResponse({ error: "server error", detail: String(err && err.message ? err.message : err) }, 500);
    }
  },
};
