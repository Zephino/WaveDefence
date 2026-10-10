class_name OnlineConfig
extends RefCounted

## Public worldwide boards (read) from the dedicated `data` branch.
## Updated by the Cloudflare Worker via GitHub API (does not touch main).
const LEADERBOARD_READ_URL := "https://raw.githubusercontent.com/Zephino/WaveDefence/data/leaderboard.json"

## Cloudflare Worker origin only (no path, no trailing slash).
## Set this after deploying leaderboard-api/ (see that folder's README).
## Example: "https://wave-defence-leaderboard.your-account.workers.dev"
const API_BASE_URL := "https://wave-defence-leaderboard.thebotcoder.workers.dev"

## Reject absurd client-reported waves (server enforces the same).
const MAX_WAVE_SANITY := 100000


static func post_url() -> String:
	var base := API_BASE_URL.strip_edges().trim_suffix("/")
	if base.is_empty():
		return ""
	return base + "/leaderboard"


## Prefer the Worker (KV source of truth) when deployed; fall back to GitHub raw.
static func read_url() -> String:
	var worker := post_url()
	if not worker.is_empty():
		return worker
	return LEADERBOARD_READ_URL.strip_edges()


static func can_read() -> bool:
	return not read_url().is_empty()


static func can_post() -> bool:
	return not post_url().is_empty()
