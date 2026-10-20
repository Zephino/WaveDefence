# Wave Defence leaderboard API

Cloudflare Worker that:

- Serves `GET /leaderboard` (mode×difficulty top 10s: `classic_medium`, `siege_hard`, `clash_easy`, …)
- Accepts `POST /leaderboard` with `{ "name", "wave", "difficulty", "mode", "board", "seeds?", "board_png?" }`
- Saves to Workers KV (fast) and commits `leaderboard.json` on the **`data`** branch of [Zephino/WaveDefence](https://github.com/Zephino/WaveDefence) (not `main`)

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

## Local test

```bash
npm run dev
```
