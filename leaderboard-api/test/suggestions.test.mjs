import { test } from "node:test";
import assert from "node:assert/strict";
import { handleSuggestionPost, suggestionStatus, validateSuggestion } from "../src/suggestions.mjs";

const payload = {
  category: "tower",
  title: "Please add a new summon",
  description: "A lightning summon with a storm-themed area attack could be exciting.",
  website: "",
};
function env() {
  const data = new Map();
  return {
    GITHUB_TOKEN: "test-token",
    GITHUB_OWNER: "Zephino",
    GITHUB_REPO: "WaveDefence",
    LEADERBOARD_KV: {
      async get(key) { return data.get(key) ?? null; },
      async put(key, value) { data.set(key, value); },
    },
    _data: data,
  };
}
function request(p = payload) {
  return new Request("https://example.workers.dev/suggestions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(p),
  });
}
test("validates category, title, description, honeypot and link limits", () => {
  assert.equal(validateSuggestion(payload).error, undefined);
  assert.equal(validateSuggestion({ ...payload, category: "admin" }).error, "invalid category");
  assert.ok(validateSuggestion({ ...payload, title: "hi" }).error);
  assert.ok(validateSuggestion({ ...payload, description: "short" }).error);
  assert.ok(validateSuggestion({ ...payload, website: "spam.example" }).error);
  assert.ok(validateSuggestion({ ...payload, description: "a".repeat(30) + " http://a http://b http://c" }).error);
});
test("doesn't accept submissions before server setup", async () => {
  assert.equal((await suggestionStatus({}).json()).accepting, false);
  assert.equal((await handleSuggestionPost(request(), {}, "127.0.0.1")).status, 503);
});
test("creates exactly one GitHub issue and returns confirmation", async () => {
  let posted;
  const githubFetch = async (_url, options) => {
    posted = options;
    return new Response(JSON.stringify({ number: 42 }), { status: 201 });
  };
  const e = env();
  const result = await handleSuggestionPost(request(), e, "1.2.3.4", githubFetch);
  assert.equal(result.status, 201);
  assert.equal((await result.json()).issue_number, 42);
  const body = JSON.parse(posted.body);
  assert.match(body.title, /Player suggestion/);
  assert.match(body.body, /lightning summon/);
  assert.equal(body.body.includes("1.2.3.4"), false);
  assert.equal(e._data.size, 2);
});
test("rejects GitHub failure without claiming success", async () => {
  const e = env();
  const response = await handleSuggestionPost(request(), e, "1.2.3.4",
    async () => new Response("forbidden", { status: 403 }));
  assert.equal(response.status, 502);
  assert.equal(e._data.size, 0);
});
test("explains common GitHub permission and access failures without leaking secrets", async () => {
  const cases = [
    [401, /token is invalid or expired/],
    [403, /Issues: Read and write/],
    [404, /repository access failed/],
    [422, /rejected the issue submission/],
    [503, /status 503/],
  ];
  for (const [status, diagnostic] of cases) {
    const e = env();
    const res = await handleSuggestionPost(request(), e, "1.2.3.4",
      async () => new Response(JSON.stringify({ secret: "do-not-repeat" }), { status }));
    assert.equal(res.status, 502);
    const body = await res.json();
    assert.match(body.error, diagnostic);
    assert.doesNotMatch(JSON.stringify(body), /test-token|do-not-repeat/);
    assert.equal(body.error.includes("1.2.3.4"), false);
    assert.equal(e._data.size, 0);
  }
});

test("limits one IP to three successful suggestions per day", async () => {
  const e = env();
  const fetcher = async () => new Response(JSON.stringify({ number: 1 }), { status: 201 });
  const codes = [];
  for (let i = 0; i < 4; i++) {
    codes.push((await handleSuggestionPost(request(), e, "1.2.3.4", fetcher)).status);
  }
  assert.deepEqual(codes, [201, 201, 201, 429]);
});
test("returns validation errors before using the GitHub API", async () => {
  const e = env();
  let called = false;
  const fetcher = async () => { called = true; return new Response("", { status: 201 }); };
  const response = await handleSuggestionPost(request({ ...payload, title: "x" }), e, "1.2.3.4", fetcher);
  assert.equal(response.status, 400);
  assert.equal(called, false);
});

test("auto-attached game version, runtime, device and browser appear in the Issue", async () => {
  const client = {
    game_version: "00.01.21", runtime: "Web", device_type: "Phone",
    platform: "Android", browser: "Chrome",
  };
  let issue;
  const response = await handleSuggestionPost(request({ ...payload, client }), env(), "1.2.3.4",
    async (_url, opts) => {
      issue = JSON.parse(opts.body);
      return new Response(JSON.stringify({ number: 23 }), { status: 201 });
    });
  assert.equal(response.status, 201);
  assert.match(issue.body, /Game version: 00\.01\.21/);
  assert.match(issue.body, /Run target: Web/);
  assert.match(issue.body, /Device type: Phone/);
  assert.match(issue.body, /Operating system: Android/);
  assert.match(issue.body, /Browser: Chrome/);
  assert.doesNotMatch(issue.body, /1\.2\.3\.4/);
});

test("only fixed non-identifying device categories are accepted", () => {
  const malicious = {
    game_version: "0.1\n@someone", runtime: "untrusted raw UA",
    device_type: "My secret phone ID", platform: "**bad**",
    browser: "Chrome\\nSensitive info", user_agent: "full UA must not be stored",
    ip: "192.168.0.1", model: "private model",
  };
  const checked = validateSuggestion({ ...payload, client: malicious });
  assert.equal(checked.error, undefined);
  assert.deepEqual(checked.client, {
    game_version: "Unknown", runtime: "Unknown", device_type: "Unknown",
    platform: "Unknown", browser: "Unknown",
  });
  assert.ok(!JSON.stringify(checked).includes("192.168.0.1"));
  assert.ok(!JSON.stringify(checked).includes("private model"));
});

test("old game versions still submit suggestions without device metadata", async () => {
  let issue;
  const response = await handleSuggestionPost(request(payload), env(), "1.2.3.4",
    async (_url, options) => {
      issue = JSON.parse(options.body);
      return new Response(JSON.stringify({ number: 24 }), { status: 201 });
    });
  assert.equal(response.status, 201);
  assert.match(issue.body, /Not provided \(older game build\)/);
});

test("normalizes control characters and refuses multiline issue titles", () => {
  const checked = validateSuggestion({
    ...payload,
    title: "  A\r\nbad\u202e title\x00 ",
    description: "Enough regular text here\r\n## Injected heading\u2028@everyone",
  });
  assert.equal(checked.error, undefined);
  assert.equal(checked.title, "A bad title");
  assert.equal(checked.description, "Enough regular text here\n## Injected heading\n＠everyone");
});

test("SQL-looking content stays inert text and Markdown/HTML are escaped in GitHub Issues", async () => {
  const description = [
    "Please improve the life bar size.",
    "<script>alert('xss')</script>",
    "## Spoofed developer announcement",
    "[click here](javascript:alert(1))",
    "@everyone",
    "SQL example: '; DROP TABLE suggestions; --",
  ].join("\n");
  let issue;
  const response = await handleSuggestionPost(request({
    ...payload,
    title: "Suggest '\r\nbetter health bars",
    description,
  }), env(), "1.2.3.4", async (_url, options) => {
    issue = JSON.parse(options.body);
    return new Response(JSON.stringify({ number: 31 }), { status: 201 });
  });
  assert.equal(response.status, 201);
  assert.equal(issue.title, "[Player suggestion] Suggest ' better health bars");
  assert.ok(issue.body.includes("&lt;script&gt;"));
  assert.ok(issue.body.includes("&lt;/script&gt;"));
  assert.ok(issue.body.includes("> \\#\\# Spoofed developer announcement"));
  assert.ok(issue.body.includes("> \\[click here\\]\\(javascript:alert\\(1\\)\\)"));
  assert.ok(issue.body.includes("＠everyone"));
  assert.ok(issue.body.includes("DROP TABLE suggestions;"));
  assert.ok(!issue.body.includes("<script>"));
  assert.ok(!issue.body.includes("@everyone"));
  assert.equal(issue.body.includes("1.2.3.4"), false);
});

test("Worker routes in-game feedback without changing the leaderboard", async () => {
  const { default: worker } = await import("../src/index.js");
  const e = env();
  const response = await worker.fetch(
    new Request("https://example.workers.dev/suggestions"), e);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).accepting, true);

  const noSecret = { ...e, GITHUB_TOKEN: undefined };
  const missing = await worker.fetch(
    new Request("https://example.workers.dev/suggestions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }), noSecret);
  assert.equal(missing.status, 503);

  const other = await worker.fetch(
    new Request("https://example.workers.dev/not-found"), e);
  assert.equal(other.status, 404);
});
