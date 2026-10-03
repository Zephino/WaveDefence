# Wave Defence leaderboard API

Cloudflare Worker that:

- Serves `GET /leaderboard` (Easy / Medium / Hard top 10)
- Accepts `POST /leaderboard` with `{ "name", "wave", "difficulty" }`
- Saves to Workers KV (fast) and commits `leaderboard.json` on [Zephino/WaveDefence](https://github.com/Zephino/WaveDefence)

Apps never hold a GitHub token. Only this Worker does.

## One-time setup

1. Create a free [Cloudflare](https://dash.cloudflare.com/) account.
2. Create a fine-grained GitHub PAT (or classic) with **Contents: Read and write** on `Zephino/WaveDefence` only.
3. From this folder:

```bash
npm install
npx wrangler login
npx wrangler kv namespace create LEADERBOARD_KV
```

4. Copy the KV id into `wrangler.toml` (`[[kv_namespaces]]` binding `LEADERBOARD_KV`).
5. Store the GitHub token:

```bash
npx wrangler secret put GITHUB_TOKEN
```

6. Deploy:

```bash
npm run deploy
```

7. Copy the Worker URL (e.g. `https://wave-defence-leaderboard.<account>.workers.dev`) into  
   `scripts/online_config.gd` → `API_BASE_URL` (no trailing slash).
8. Rebuild / re-export the game so clients can POST scores.

Until `API_BASE_URL` is set, clients still **read** worldwide boards from  
`https://raw.githubusercontent.com/Zephino/WaveDefence/main/leaderboard.json`.

## Local test

```bash
npm run dev
```
