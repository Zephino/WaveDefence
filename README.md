# Wave Defence

Endless maze-builder tower defence (Godot 4). Place towers to shape the enemy path, keep at least one route open, and send waves until you run out of lives.

**Version:** see root [`VERSION`](VERSION) (also shown in-game).

**License:** proprietary — [All Rights Reserved](LICENSE). Play the official builds; contact via the [Zephino/WaveDefence](https://github.com/Zephino/WaveDefence) GitHub profile for commercial licensing. Do not copy or sell this project without permission.

## Play in a browser (share with friends)

After GitHub Pages is enabled on this repo (`Settings → Pages → Deploy from branch → main /docs`):

**https://zephino.github.io/WaveDefence/**

Works on desktop and phone browsers (including iPhone Safari — no Mac/IPA required for web play). Click the game once if controls seem stuck.

On **phones**, the game detects a mobile browser, prefers **landscape**, and enters **fullscreen** after the first tap (browsers block auto-fullscreen). Desktop browsers are left windowed.

Rebuild the site files:

```powershell
.\export_builds.ps1 -WebOnly
```

## Quick start (recommended)

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

## Setup (manual)

1. Install [Godot 4](https://godotengine.org/) (standard build, 4.3+ recommended).
2. In Godot: **Import** → open this folder → select `project.godot`.
3. Press **F5** (or Play) to run.

No addons or extra packages required.

## Main menu

On launch you get:

- **Classic / Random** — pick a mode, then a difficulty
  - **Classic** — fixed map (current layout)
  - **Random** — randomized spawn/exit and rock tiles; every **25** waves the board rebuilds, towers clear, lives reset, and gold is based on kills on that map (`max(starting gold, kills × 3)`)
- **Easy / Medium / Hard** — begin a run (starting gold **350 / 200 / 100**)
- **Leaderboard** — separate top 10 boards for **Easy / Medium / Hard**. Web, PC, Android, and iOS **pull the same worldwide boards** when online (cached locally). Runs that opened/used the debug menu cannot be submitted.
- **Quit** — close the game (desktop and Android)

When you lose all lives, you are sent to the **leaderboard** for that run’s difficulty. If your wave score ranks in the top 10 for that board, you can enter a name (letters, numbers, spaces; max 12). Older single-board saves migrate into Medium.

**Shared scores:** boards are stored in repo [`leaderboard.json`](leaderboard.json). Clients **read** from GitHub; **submitting** uses a small Cloudflare Worker ([`leaderboard-api/`](leaderboard-api/)) that writes that file (apps never hold a GitHub token). Set `API_BASE_URL` in [`scripts/online_config.gd`](scripts/online_config.gd) after deploying the Worker. After a match, a qualifying score is pushed when you submit and again when you leave the leaderboard if it has not synced yet. Offline play uses the last cached / local `user://leaderboard.json`.

## How to play

- Select a tower from the left shop, then **left-click** the grid to place it.
- Hover a shop tower or a placed tower for a description (stats, effects, air/ground multipliers).
- **Hold left-click and drag** to paint-place many walls/towers in a row.
- Place cheap **Walls** to shape the maze, then build a real tower **on top of a wall** (no need to sell the wall first).
- You **cannot** build a wall or tower on top of an existing tower — **sell it first**.
- Towers **block the path**. You cannot place a tower that fully cuts off spawn → exit.
- Click a placed tower to select it; **Ctrl+click** or **Shift+click** to select multiple.
- **Deselect** (sidebar), **Esc**, or **right-click** the board clears the selection.
- Select towers and press **Upgrade** (or **U**): each tower can take **3** stat upgrades (damage/range/rate). Yellow pips show progress.
- After +3, choose a **final** elemental buff: **Fire / Ice / Poison / Lightning** (sidebar buttons). One per tower — keeps the tower’s type and adds a light extra effect (e.g. Burn + Ice still burns, with a mild slow).
- **Sell Selected** sells every selected tower/wall (~50% refund of base + upgrade gold).
- After the main menu, build freely with **no timer**. Press **Start Round** when ready.
- That starts a **build countdown**, then waves auto-run with intermissions between them.
- After **Start Round**, the build countdown is always skippable (small gold bonus for time left).
- After a wave ends, the break timer is always skippable (small gold bonus for time left).
- Kill **25%** of a wave to unlock **Send Next Wave**: next-wave enemies start spawning immediately while leftovers stay on the map, plus a slight early-send gold bonus.
- Boss every **10** waves; **two bosses** every **50** waves.
- **Flying boss** every **15** waves — flies an **S-curve** over walls/towers (air creeps use the same style).
- Light flying **scouts** start around **wave 8**; after **wave 20** every wave mixes air with ground (banner **AIR MIX**).
- Every **7** waves (**7, 14, 21…**) is a **SPEED WAVE** — much faster, glassier creeps and denser spawns.
- Top bar **Left** shows enemies remaining until the board clears (on map + still spawning).
- Kill enemies for gold. Leaks cost lives. Game over at 0 lives → leaderboard.
- After each wave is cleared, earn a **clear bonus**: gold based on kills that round (`WAVE_CLEAR_BONUS_PER_KILL` in `data/wave_scaler.gd`).
- In-game **End Run** asks for confirmation, then sends your wave score to the leaderboard (same as dying).

### Towers (costs are tunable in `data/towers.gd`)

| Tower | Cost | Role |
|--------|------|------|
| Wall | 5 | Path-blocking only (no attack). Build any real tower on top of a wall to replace it. |
| Gunner | 40 | Basic single-target; slight air bonus (`air_damage_mult` 1.25) |
| Rapid | 55 | Fast / low damage; strong vs air (1.6×) |
| Cannon | 75 | Boss hunter (2.4× bosses, prioritizes them); splash; weak vs air |
| Burn | 50 | Ignite DoT; weak vs air (0.7×) |
| Freeze | 60 | Slow; good vs air (1.4×) |
| Poison | 70 | Poison DoT + light splash; slight air penalty (0.85×) |
| Lightning | 80 | Chain damage; strong vs air (2.0×) |
| Spike | 45 | Melee ground-only; high damage, very short range |
| Anti-Air | 65 | Air-only flak; long range |

Air/ground multipliers and `target_filter` (`any` / `ground` / `air`) are tunable in `data/towers.gd`.

Starting gold by difficulty (`data/wave_scaler.gd`): **Easy 350**, **Medium 200**, **Hard 100**.

## Debug / playtest

Toggle panel with **F1** or **~**. Opening the debug menu or using debug hotkeys makes that run **ineligible** for the leaderboard.

| Hotkey | Action |
|--------|--------|
| G | +1000 gold |
| L | +5 lives |
| N | Force next wave (ignores timer / skip unlock; keeps enemies on the map) |
| U | Upgrade selected towers |
| K | Clear enemies |
| R | Restart run |

Panel also: **Force Next Wave**, jump to wave 10/15/50, god mode, restart.

Tune balance in:

- `data/towers.gd` — costs and combat stats
- `data/wave_scaler.gd` — wave scaling, lives, starting gold

## Headless smoke test

```text
godot --headless --path . -s res://scripts/smoke_test.gd
```

Expect `SMOKE_TEST_OK`.

## Mobile / touch

The game supports phones and tablets (native Android/iOS and mobile web). Mobile devices use landscape (either direction), force fullscreen while playing, and release orientation when the app is closed or backgrounded. Desktop PCs are not forced into fullscreen:

- **Drag** on the board to paint-place
- **Tap** a tower to select + show its info card
- **Long-press** a tower to multi-select (or use right-side **Multi: On**)
- **Deselect** button, or tap empty/unplaceable cells / outside the board
- Larger buttons; shop on the **left**, actions on the **right** (no scrollbar)

### Send / play packages

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

## Export (Windows) → `pc/`

1. Install Godot export templates (Editor → Manage Export Templates).
2. Project → Export → **Windows Desktop**, or run `.\export_builds.ps1`.
3. Send `pc/WaveDefence.exe` (or the whole `pc/` folder).

### Export (Web) → `docs/`

1. Install Godot **Web** export templates.
2. Project → Export → **Web**, or `.\export_builds.ps1 -WebOnly`.
3. Enable GitHub Pages: branch `main`, folder `/docs`.
4. Share `https://zephino.github.io/WaveDefence/`.

Optional custom domain (not free): point your domain at GitHub Pages so the link does not show `github.io`.

## Project layout

- `scenes/main.tscn` — entry scene
- `scripts/` — game systems
- `data/` — tunable numbers
- `docs/` — Web / GitHub Pages build
- `leaderboard.json` — shared worldwide top-10 boards
- `leaderboard-api/` — Cloudflare Worker (POST gateway → GitHub)
- `pc/` — Windows play package
- `phone/android/` — Android APK
- `phone/ios/` — iOS IPA (exported on Mac)
- `export_builds.ps1` — rebuild packages from this source
- `LICENSE` — All Rights Reserved
- `CHANGELOG.md` — version history
