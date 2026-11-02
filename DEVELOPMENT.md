# Wave Defence — development notes

Technical notes for working on the game: running from source, exporting builds,
tests, debug tools, and how the online pieces fit together. For how to **play**,
see [`README.md`](README.md).

## Run from source

### Quick start (Windows)

Double-click **`play.bat`** (or run the scripts below). This will:

1. Install **Godot 4** with winget if it is missing
2. Launch the game

If launch fails, the window stays open and writes `godot_launch.log` in this folder.

```bat
play.bat
```

PowerShell:

```powershell
.\play.ps1
```

Open the Godot editor instead of playing:

```powershell
.\play.ps1 -Editor
```

Git Bash:

```bash
./play.sh
```

### Manual setup

1. Install [Godot 4](https://godotengine.org/) (standard build, 4.3+ recommended; CI uses 4.7).
2. In Godot: **Import** → open this folder → select `project.godot`.
3. Press **F5** (or Play) to run.

No addons or extra packages required.

## Web version (GitHub Pages)

The website (**https://zephino.github.io/WaveDefence/**) is generated from the
files in `docs/`, not directly from the Godot source. A GitHub Actions workflow
(`.github/workflows/web-export.yml`) exports the web game whenever game files
change on `main` and commits the refreshed `docs/` files back to `main`; GitHub
Pages then publishes them. Don't edit `docs/index.*` by hand.

To rebuild the web files locally instead:

```powershell
.\export_builds.ps1 -WebOnly
```

## Builds and packages

There is **one** game codebase. Playable builds live in:

| Folder | File | Use |
|--------|------|-----|
| `docs/` | `index.html` (+ wasm/pck) | Web — GitHub Pages |
| `pc/` | `WaveDefence.exe` | Windows — double-click to play |
| `phone/android/` | `WaveDefence.apk` | Android — install on the phone |
| `phone/ios/` | `WaveDefence.ipa` | iPhone/iPad — export on a Mac with Xcode |

After you change game code, rebuild from the project root:

```powershell
.\export_builds.ps1
```

Options: `-PcOnly`, `-PhoneOnly`, `-AndroidOnly`, `-IosOnly`, `-WebOnly`.

### Export (Windows) → `pc/`

1. Install Godot export templates (Editor → Manage Export Templates).
2. Project → Export → **Windows Desktop**, or run `.\export_builds.ps1`.
3. Send `pc/WaveDefence.exe` (or the whole `pc/` folder).

### Export (Android) → `phone/android/`

1. Install Godot **Android** export templates and configure the Android SDK + Java 17 (Editor → Editor Settings → Export → Android).
2. Project → Export → **Android**, or run `.\export_builds.ps1 -AndroidOnly`.
3. Package id: `com.wavedefence.game`.
4. Send `phone/android/WaveDefence.apk`.

### Export (iOS) → `phone/ios/`

1. Requires **macOS + Xcode** (cannot finish an IPA on Windows).
2. Install Godot **iOS** export templates and set Apple team / signing (Editor Settings → Export → iOS).
3. Project → Export → **iOS** (preset writes `phone/ios/WaveDefence.ipa`), or run `.\export_builds.ps1 -IosOnly` on a Mac.
4. Bundle id: `com.wavedefence.game`. Install via Xcode / TestFlight / your usual signing flow.

### Export (Web) → `docs/`

1. Install Godot **Web** export templates.
2. Project → Export → **Web**, or `.\export_builds.ps1 -WebOnly`.
3. Enable GitHub Pages: branch `main`, folder `/docs`.
4. Share `https://zephino.github.io/WaveDefence/`.

Optional custom domain (not free): point your domain at GitHub Pages so the link does not show `github.io`.

## Tests

Headless smoke test:

```text
godot --headless --path . -s res://scripts/smoke_test.gd
```

Expect `SMOKE_TEST_OK`.

Online Clash (lobby seats, a friend's actions on the host, the friend's view of host snapshots; no internet needed):

```text
godot --headless --path . -s res://scripts/online_clash_test.gd
```

Expect `ONLINE_CLASH_TEST_OK`. Other test scripts: `scripts/leaderboard_test.gd`, `scripts/clash_bot_seal_test.gd`.

Worker tests (leaderboard, suggestions, lobbies): `npm test` in `leaderboard-api/`.

## Debug / playtest

Toggle the debug panel with **F1** or **~**. Opening it or using debug hotkeys makes that run **ineligible** for the leaderboard. Debug is off in online Clash.

| Hotkey | Action |
|--------|--------|
| G | +1000 gold |
| L | +5 lives |
| N | Force next wave (ignores timer / skip unlock; keeps enemies on the map) |
| U | Upgrade selected towers |
| K | Clear enemies |
| R | Restart run |

Panel also: **Force Next Wave**, **Spawn 5 / Flyer / Boss on Self** (your path or Clash human lane), jump to wave 10/15/50, god mode, restart. It floats over the board (does not cover the sidebars).

## Balance

- `data/towers.gd` — tower costs, combat stats, air/ground multipliers, `target_filter` (`any` / `ground` / `air`), `unlock_wave`
- `data/command_abilities.gd` — Command ability costs, cooldowns, trap modes
- `data/wave_scaler.gd` — wave scaling, starting gold, Clash numbers, and `DIFFICULTY_TUNING` (Classic / Random / Siege difficulty: monster health, speed, count, gold, lives, how early bosses / fliers arrive)
- `data/monster_types.gd` — Randomize monster roster and resist growth

## Art and audio

- **Monsters** — ground / flier / boss sheets from the **mobs_all** pack under `assets/sprites/` (base + `_plus` variants; late waves prefer plus). Wreckers use armadillo / armadillo_plus; snakes use crawler / crawler_plus. Older ground art is kept in `archive/mobs_ground_legacy/`; pre-update sheets sit under `archive/mobs_all_pre_*`. Regenerate with `tools/monster_art/`.
- **Towers** — animated sheets under `assets/sprites/towers/` (data-driven via `TowerSprites` + `*_frames.json`). Walls use a **16-tile fortress autotile**; Vortex uses a **120×120** sheet. Replace PNGs with the same names/layout without code changes — see [`docs/TOWER_SPRITES.md`](docs/TOWER_SPRITES.md).
- **Attack effects** — projectile / muzzle / impact sheets under `assets/sprites/effects/` (`EffectSprites` + `effects_manifest.json`). See [`docs/EFFECT_SPRITES.md`](docs/EFFECT_SPRITES.md).
- **Music** — original retro console-style loops in `audio/music/` (32 bars, seamless WAV; `MIX_CONSOLES` blends NES, Game Boy, GBA, SNES, Master System, Game Gear, and Genesis timbres). Desktop uses full stereo beds; the web build uses lighter mono `web_loop_*.wav` copies played through the browser Web Audio API. Menu, Standard, and Siege each have a bed; the intense layer is the same tempo with a busier mix so it blends when enemies near the exit. Regenerate with `python audio/music/generate_loops.py`. Older beds are in `audio/music/old_audio/`. Settings persist in `user://settings.cfg`.

## Leaderboard, suggestions, and online Clash

- **Shared scores** live on the **`data`** branch as [`leaderboard.json`](https://github.com/Zephino/WaveDefence/blob/data/leaderboard.json) (kept off `main` so score updates don't clutter game history). Don't delete the `data` branch. Clients read that file; **submitting** goes through the Cloudflare Worker in [`leaderboard-api/`](leaderboard-api/), which writes the same path on `data` (apps never hold a GitHub token). `API_BASE_URL` is in [`scripts/online_config.gd`](scripts/online_config.gd). Without it, scores save on this device only.
- Text boxes are **allowlist-sanitized**; there is **no SQL database** (local JSON + Cloudflare KV).
- **Suggest a Feature** posts to the same Worker (`/suggestions`), which opens a GitHub issue.
- **Online Clash** uses the Worker's `/lobby` route: a Durable Object per match relays messages between up to 4 players; the host's game simulates every lane. See [`leaderboard-api/README.md`](leaderboard-api/README.md) for deploying it.

## Project layout

- `scenes/main.tscn` — game scene; `scenes/menu.tscn` — main menu (entry scene)
- `scripts/` — game systems
- `scripts/net/` — online Clash: lobby connection (`Net` autoload), host / joined-player sync
- `data/` — tunable numbers
- `docs/` — web / GitHub Pages build (generated)
- `data` branch / `leaderboard.json` — shared worldwide top-10 boards (Worker writes here)
- `leaderboard-api/` — Cloudflare Worker (leaderboard, suggestions, online Clash lobbies)
- `leaderboard.json` on `main` — empty stub / local reference only
- `pc/`, `phone/android/`, `phone/ios/` — play packages
- `export_builds.ps1` — rebuild packages from this source
- `CHANGELOG.md` — version history; `VERSION` — current version
- `CLAUDE.md`, `.cursor/rules/` — rules for AI assistants working on the project
- `docs/archive/` — original tower/effect ZIP backups
- `LICENSE` — All Rights Reserved
