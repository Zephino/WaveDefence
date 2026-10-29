# Wave Defence leaderboard API

Cloudflare Worker that:

- Serves `GET /leaderboard` (mode×difficulty top 10s: `classic_medium`, `siege_hard`, `clash_easy`, …)
- Accepts `POST /leaderboard` with `{ "name", "wave", "difficulty", "mode", "board", "seeds?", "board_png?" }`
- Saves to Workers KV (fast) and commits `leaderboard.json` on the **`data`** branch of [Zephino/WaveDefence](https://github.com/Zephino/WaveDefence) (not `main`)
- Runs **online Clash lobbies** at `GET /lobby` (WebSocket, 6-digit codes; see below)

Apps never hold a GitHub token. Only this Worker does.

**Input safety:** there is no SQL database (JSON + KV only). Names are **allowlist**-sanitized (letters, digits, space, `_`, `-`; max 12). Optional `board_png` is base64 PNG (capped). Quotes/semicolons and other injection metacharacters are rejected. POST bodies over 100 KB are refused. Legacy `easy`/`medium`/`hard` keys migrate into `classic_*`.

## One-time setup

1. Create a free [Cloudflare](https://dash.cloudflare.com/) account.
2. Create a fine-grained GitHub PAT (or classic) with **Contents: Read and write** on `Zephino/WaveDefence` only. Keep the token ready — you will paste it into the terminal (not into chat).
3. **Windows (easiest):** double-click [`Setup-Leaderboard.bat`](Setup-Leaderboard.bat)  
   Or from this folder:

```powershell
.\Setup-Leaderboard.bat
```

The app walks you through Cloudflare signup, the GitHub token page, paste-token, login, KV, secret, and deploy. It writes `API_BASE_URL` into `scripts/online_config.gd`. Your token is sent to Cloudflare only (password field; not saved in the game).

**Git Bash / WSL / macOS / Linux:**

```bash
bash setup-leaderboard.sh
```

**Manual steps (same as the script):**

```bash
npm install
npx wrangler login
npx wrangler kv namespace create LEADERBOARD_KV
# paste id into wrangler.toml [[kv_namespaces]]
npx wrangler secret put GITHUB_TOKEN
npm run deploy
```

4. Confirm `scripts/online_config.gd` → `API_BASE_URL` is the Worker URL (no trailing slash, no `/leaderboard`).
5. Rebuild / re-export the game so clients can POST scores.

Until `API_BASE_URL` is set, clients still **read** worldwide boards from  
`https://raw.githubusercontent.com/Zephino/WaveDefence/data/leaderboard.json`.

## In-game feature suggestions

The main-menu **Suggest a Feature** option opens an in-game form without a
player account or an external browser. It submits to this existing Worker at
`POST /suggestions`, which creates an issue in
[WaveDefence Issues](https://github.com/Zephino/WaveDefence/issues). The game
automatically includes the version, desktop/phone/tablet, OS category and
browser category (when applicable). These diagnostic categories and suggestion
text are public in the GitHub issue; no device IDs or raw browser strings are
attached.

**Cloudflare requirements:** Keep the existing Worker
`wave-defence-leaderboard` and its KV binding `LEADERBOARD_KV`; the new
endpoint does not require a second Worker or a second KV namespace. Its
`GITHUB_TOKEN` secret must have **Issues: Read and write** as well as
**Contents: Read and write**, with repository access to `Zephino/WaveDefence`.
If the token already exists, edit its permissions and save them. No token is
ever committed or sent to players. `GITHUB_BRANCH=data` is **only for
leaderboard data**; Github Issues do not use that branch. Git-linked Cloudflare
deployment should use `main` with root directory `leaderboard-api` and
deploy command `npx wrangler deploy`. If the Worker isn't Git-linked, run
`npm run deploy` from `leaderboard-api` with Cloudflare Wrangler credentials.

**Cloudflare Git build connection:** The production build is linked to
`Zephino/WaveDefence` on `main`. Leave the build command blank, set the root
directory to `leaderboard-api` (not `/`), and deploy with
`npx wrangler deploy`. Saving this connection alone does not publish code;
the next commit to `main` triggers Cloudflare's first Worker build. Check its
actual deployment result in Cloudflare. This does **not** rebuild the Godot
web export in `docs/`; that requires a separate game export and commit.

**Verify after deploying:** Open
`https://wave-defence-leaderboard.thebotcoder.workers.dev/suggestions`. The
response should be `{"accepting":true}` when the KV binding and token are
present. This only checks configuration, not token permissions. To verify
end-to-end, send a sample in-game suggestion and check the newly created
GitHub Issue.

**Input safety:** The Worker validates categories, title/description sizes,
the honeypot and daily rate limits. It normalizes player text and escapes
HTML/Markdown before rendering in issues. It uses JSON, Workers KV, and the
GitHub API—no SQL queries are performed. If a SQL database is added later,
all user-provided values must use parameterized queries. The new route
preserves the existing `/leaderboard` endpoint.

## Online Clash lobbies (6-digit codes)

Same design as Mythriven co-op. `GET /lobby?host=1` (WebSocket) creates a
match and replies with a random 6-digit code; `GET /lobby?code=123456` joins
it. Each match is one **Durable Object** (`LobbyRoom` in `src/lobby.mjs`) that
only **relays messages** between up to 4 players: the host's game simulates
every lane, so the Worker never needs to understand the game. The host is
player 1; nobody can join after the host starts; if the host leaves, everyone
is disconnected. Each player may send 80 messages a second (more are dropped),
up to 256 KB each. Nothing is stored after everyone leaves.

**One-time deploy:** `wrangler.toml` binds `LOBBY` to the `LobbyRoom` class
(SQLite-backed Durable Objects are on the free plan). From this folder:

```bash
npx wrangler login     # if not logged in already
npm run deploy
```

Until this is deployed, **Invite Friends** shows "Couldn't start an online
match". The game connects to `wss://<API_BASE_URL host>/lobby`
(`OnlineConfig.lobby_url()` in `scripts/online_config.gd`).

## Local test

```bash
npm run dev
```
