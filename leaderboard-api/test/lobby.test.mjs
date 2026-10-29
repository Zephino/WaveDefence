import { test } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { LobbyRoom, HOST_ID, MAX_PLAYERS, MAX_MESSAGES_PER_S, isCode, randomCode } from "../src/lobby.mjs";

/** Stand-ins for Cloudflare's WebSockets and Durable Object state. */
class FakeSocket {
  constructor() {
    this.sent = [];
    this.closed = null;
    this.attachment = null;
  }
  send(data) {
    this.sent.push(typeof data === "string" ? JSON.parse(data) : [...data]);
  }
  close(code, reason) {
    this.closed = { code, reason };
  }
  serializeAttachment(v) {
    this.attachment = v;
  }
  deserializeAttachment() {
    return this.attachment;
  }
}

function fakeRoom() {
  const sockets = [];
  const data = new Map();
  const state = {
    acceptWebSocket(ws) {
      sockets.push(ws);
    },
    getWebSockets() {
      return sockets.filter((ws) => !ws.closed);
    },
    storage: {
      async get(k) {
        return data.get(k);
      },
      async put(k, v) {
        if (typeof k === "object") for (const [a, b] of Object.entries(k)) data.set(a, b);
        else data.set(k, v);
      },
      async deleteAll() {
        data.clear();
      },
    },
  };
  // Responses with status 101 aren't allowed in Node, so the room's reply is faked too.
  const room = new LobbyRoom(state, {}, () => [new FakeSocket(), new FakeSocket()]);
  const original = room.fetch.bind(room);
  room.connect = async (role, code = "123456") => {
    const headers = new Headers({ "X-Lobby-Code": code, "X-Lobby-Role": role });
    const before = sockets.length;
    let res;
    try {
      res = await original(new Request("https://lobby/connect", { headers }));
    } catch (err) {
      // new Response(null, {status: 101}) throws in Node: the socket was still accepted.
      if (sockets.length > before) return { status: 101, socket: sockets[sockets.length - 1] };
      throw err;
    }
    return { status: res.status, text: await res.text() };
  };
  return { room, sockets };
}

test("codes are 6 digits", () => {
  for (let i = 0; i < 50; i++) assert.ok(isCode(randomCode()));
  assert.equal(isCode("12345"), false);
  assert.equal(isCode("12a456"), false);
});

test("the host gets id 1 and players join with 2, 3, 4", async () => {
  const { room } = fakeRoom();
  const host = await room.connect("host");
  assert.equal(host.status, 101);
  assert.equal(host.socket.sent[0].t, "welcome");
  assert.equal(host.socket.sent[0].id, HOST_ID);
  const ids = [];
  for (let i = 0; i < MAX_PLAYERS - 1; i++) ids.push((await room.connect("join")).socket.sent[0].id);
  assert.deepEqual(ids, [2, 3, 4]);
  assert.deepEqual(host.socket.sent.slice(1).map((m) => m.id), [2, 3, 4], "the host hears each join");
  const fifth = await room.connect("join");
  assert.equal(fifth.status, 409, "4 players at most");
});

test("joining needs a host, and a code in use can't be hosted again", async () => {
  const { room } = fakeRoom();
  assert.equal((await room.connect("join")).status, 404);
  await room.connect("host");
  assert.equal((await room.connect("host")).status, 409);
});

test("no one can join after the host starts the match", async () => {
  const { room } = fakeRoom();
  const host = await room.connect("host");
  await room.webSocketMessage(host.socket, JSON.stringify({ t: "start" }));
  assert.equal((await room.connect("join")).status, 409);
});

test("binary messages are relayed with the sender's id, to everyone or one player", async () => {
  const { room } = fakeRoom();
  const host = (await room.connect("host")).socket;
  const a = (await room.connect("join")).socket;
  const b = (await room.connect("join")).socket;
  host.sent = [];
  a.sent = [];
  b.sent = [];
  await room.webSocketMessage(host, new Uint8Array([0, 7, 8]).buffer);
  assert.deepEqual(a.sent, [[1, 7, 8]]);
  assert.deepEqual(b.sent, [[1, 7, 8]]);
  assert.deepEqual(host.sent, [], "not echoed back");
  await room.webSocketMessage(a, new Uint8Array([1, 9]).buffer);
  assert.deepEqual(host.sent, [[2, 9]]);
  assert.equal(b.sent.length, 1, "only to the host");
});

test("only the host can send room commands, and too many messages are dropped", async () => {
  const { room } = fakeRoom();
  const host = (await room.connect("host")).socket;
  const a = (await room.connect("join")).socket;
  await room.webSocketMessage(a, JSON.stringify({ t: "start" }));
  assert.equal((await room.connect("join")).status, 101, "a player can't start the game");
  host.sent = [];
  for (let i = 0; i < MAX_MESSAGES_PER_S + 20; i++) await room.webSocketMessage(a, new Uint8Array([1, 1]).buffer);
  assert.ok(host.sent.length <= MAX_MESSAGES_PER_S);
});

test("when the host leaves the game ends for everyone; a player leaving is announced", async () => {
  const { room } = fakeRoom();
  const host = (await room.connect("host")).socket;
  const a = (await room.connect("join")).socket;
  const b = (await room.connect("join")).socket;
  a.closed = { code: 1000 };
  await room.webSocketClose(a);
  assert.deepEqual(b.sent.at(-1), { t: "leave", id: 2 });
  host.closed = { code: 1000 };
  await room.webSocketClose(host);
  assert.equal(b.closed.code, 4000);
});

test("the lobby route needs a WebSocket and a valid code", async () => {
  const env = { LOBBY: { idFromName: (n) => n, get: () => ({ fetch: async () => new Response("ok") }) } };
  assert.equal((await worker.fetch(new Request("https://w.example/lobby?code=123456"), env)).status, 426);
  const ws = { headers: { Upgrade: "websocket" } };
  assert.equal((await worker.fetch(new Request("https://w.example/lobby?code=12", ws), env)).status, 400);
  assert.equal((await worker.fetch(new Request("https://w.example/lobby?code=123456", ws), {})).status, 503);
});
