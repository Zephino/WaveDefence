/**
 * Online Clash lobbies (6-digit codes). Same relay as Mythriven co-op.
 *
 *   GET /lobby?host=1        (WebSocket) host a match; the reply says its 6-digit code
 *   GET /lobby?code=123456   (WebSocket) join that match
 *
 * Each match is one LobbyRoom Durable Object named by its code. It only passes
 * messages between the players (up to 4); the host's game simulates every
 * lane (host-authoritative), so the Worker never needs to understand the game. Nothing is stored after everyone leaves.
 *
 * Messages:
 *   text (JSON) from the room:  {t:"welcome", id, code, peers:[ids]}, {t:"join", id},
 *                               {t:"leave", id}, {t:"error", reason}
 *   text from the host:         {t:"start"} (no more joining), {t:"kick", id}
 *   binary from a player:       [to][data...]   to = 0 for everyone else, or a player id
 *   binary to a player:         [from][data...]
 * Player ids: the host is 1, others 2–4.
 *
 * Binding: LOBBY (Durable Object class LobbyRoom, see wrangler.toml)
 */

export const MAX_PLAYERS = 4;
export const HOST_ID = 1;
/** Messages a player may send per second; more are dropped (a game sends ~20). */
export const MAX_MESSAGES_PER_S = 80;
export const MAX_MESSAGE_BYTES = 256_000;
const CODE_TRIES = 8;

function plain(text, status) {
  return new Response(text, { status, headers: { "Access-Control-Allow-Origin": "*" } });
}

export function randomCode() {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return String(n).padStart(6, "0");
}

export function isCode(text) {
  return typeof text === "string" && /^[0-9]{6}$/.test(text);
}

/** Routes /lobby to a room: a new one with a free code for a host, or the code's room. */
export async function handleLobby(request, env) {
  if (!env.LOBBY) return plain("online play is not set up", 503);
  if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") return plain("expected a WebSocket", 426);
  const url = new URL(request.url);
  if (url.searchParams.get("host") === "1") {
    for (let i = 0; i < CODE_TRIES; i++) {
      const code = randomCode();
      const res = await roomFor(env, code).fetch(withRole(request, code, "host"));
      if (res.status !== 409) return res;
    }
    return plain("no free code, try again", 503);
  }
  const code = url.searchParams.get("code") || "";
  if (!isCode(code)) return plain("invalid code", 400);
  return roomFor(env, code).fetch(withRole(request, code, "join"));
}

function roomFor(env, code) {
  return env.LOBBY.get(env.LOBBY.idFromName("lobby:" + code));
}

function withRole(request, code, role) {
  const headers = new Headers(request.headers);
  headers.set("X-Lobby-Code", code);
  headers.set("X-Lobby-Role", role);
  return new Request("https://lobby/connect", { method: "GET", headers });
}

/** One online Clash match's lobby: relays messages between its players. */
export class LobbyRoom {
  constructor(state, env, makePair = () => new WebSocketPair()) {
    this.state = state;
    this.makePair = makePair;
    /** Per-socket message counts for the rate limit: id -> {second, count}. */
    this.rate = new Map();
  }

  sockets() {
    return this.state.getWebSockets();
  }

  info(ws) {
    return ws.deserializeAttachment() || {};
  }

  socketOf(id) {
    return this.sockets().find((ws) => this.info(ws).id === id);
  }

  async fetch(request) {
    const code = request.headers.get("X-Lobby-Code") || "";
    const role = request.headers.get("X-Lobby-Role") || "";
    const open = this.sockets();
    let id;
    if (role === "host") {
      if (open.length > 0) return plain("code in use", 409);
      await this.state.storage.put({ code, started: false });
      id = HOST_ID;
    } else {
      if (!open.some((ws) => this.info(ws).id === HOST_ID)) return plain("no game with that code", 404);
      if (await this.state.storage.get("started")) return plain("that game has already started", 409);
      if (open.length >= MAX_PLAYERS) return plain("that game is full", 409);
      const taken = new Set(open.map((ws) => this.info(ws).id));
      id = 2;
      while (taken.has(id)) id++;
    }
    const pair = this.makePair();
    const client = pair[0];
    const server = pair[1];
    this.state.acceptWebSocket(server);
    server.serializeAttachment({ id });
    const peers = open.map((ws) => this.info(ws).id);
    server.send(JSON.stringify({ t: "welcome", id, code, peers }));
    for (const ws of open) ws.send(JSON.stringify({ t: "join", id }));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    const from = this.info(ws).id;
    if (!from || !this.allowed(from)) return;
    if (typeof message === "string") {
      if (from !== HOST_ID || message.length > 1000) return;
      let msg;
      try {
        msg = JSON.parse(message);
      } catch {
        return;
      }
      if (msg.t === "start") await this.state.storage.put("started", true);
      if (msg.t === "kick" && Number.isInteger(msg.id) && msg.id !== HOST_ID) {
        const target = this.socketOf(msg.id);
        if (target) target.close(4001, "removed by the host");
      }
      return;
    }
    const bytes = new Uint8Array(message);
    if (bytes.length < 2 || bytes.length > MAX_MESSAGE_BYTES) return;
    const to = bytes[0];
    bytes[0] = from;
    for (const other of this.sockets()) {
      const id = this.info(other).id;
      if (id === from || (to !== 0 && id !== to)) continue;
      try {
        other.send(bytes);
      } catch (_) {}
    }
  }

  allowed(id) {
    const second = Math.floor(Date.now() / 1000);
    const entry = this.rate.get(id) || { second, count: 0 };
    if (entry.second !== second) {
      entry.second = second;
      entry.count = 0;
    }
    entry.count++;
    this.rate.set(id, entry);
    return entry.count <= MAX_MESSAGES_PER_S;
  }

  async webSocketClose(ws) {
    await this.leave(ws);
  }

  async webSocketError(ws) {
    await this.leave(ws);
  }

  async leave(ws) {
    const id = this.info(ws).id;
    const others = this.sockets().filter((o) => o !== ws);
    if (id === HOST_ID) {
      // No host migration at launch: the game ends for everyone.
      for (const other of others) other.close(4000, "the host left");
      await this.state.storage.deleteAll();
      return;
    }
    for (const other of others) {
      try {
        other.send(JSON.stringify({ t: "leave", id }));
      } catch (_) {}
    }
    if (others.length === 0) await this.state.storage.deleteAll();
  }
}
