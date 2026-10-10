## Version 00.02.29
Date: 10/10/2026
Time: 11:44 AM

### Changes
- Web/PWA music now loads raw PCM `.bin` beds (skips Godot's WAV importer) and falls back to procedural loops if those fail

### Reason
The installed web app stayed silent because Godot's imported WAV samples and an old service-worker cache do not play reliably in browsers, even after a tap.

## Version 00.02.28
Date: 10/10/2026
Time: 11:40 AM

### Changes
- Web music loads only PCM loops (rejects silent IMA-ADPCM imports) and starts after the first tap, with retries once the browser AudioContext resumes

### Reason
Godot reimported the new web beds as IMA-ADPCM, and the menu unlocked/played audio on load before a user gesture, so browsers stayed silent.

## Version 00.02.27
Date: 10/10/2026
Time: 11:36 AM

### Changes
- Install app no longer treats browser fullscreen as “already on home screen”; Chromium install prompt is offered first when available

### Reason
Settings → Install app falsely said the game was already installed when the page was only fullscreen in the browser.

## Version 00.02.26
Date: 10/10/2026
Time: 11:27 AM

### Changes
- Pause **Settings** now opens Master / Music / SFX volume sliders plus a **Mute music** toggle (same persisted settings as the main menu)

### Reason
Players needed to mute or change music volume during a run without quitting to the main menu.

## Version 00.02.25
Date: 10/10/2026
Time: 11:23 AM

### Changes
- Music generator now sets `MIX_CONSOLES = True` and blends all console profiles (NES, Game Boy, GBA, SNES, Master System, Game Gear, Genesis)
- Regenerated desktop `original_loop_*.wav` and web `web_loop_*.wav` beds with the mixed-console engine; previous WAVs remain in `audio/music/old_audio/`

### Reason
User requested every console profile and console mixing enabled for the remade retro music beds.

## Version 00.02.24
Date: 10/10/2026
Time: 11:01 AM

### Changes
- Added project rule `.cursor/rules/retro-looping-music.mdc` for original seamless retro looping music generation

### Reason
No music rule was present in project or user rules; install the provided retro looping-music generator rule for audio/Python work.

## Version 00.02.23
Date: 10/10/2026
Time: 10:59 AM

### Changes
- Burn / Freeze / Poison attack VFX now fly from the tower and home toward the moving enemy (with a short trail and impact pop)
- Web audio: resume AudioContext on first tap, use lighter mono `web_loop_*.wav` beds in the web pack, and keep heavy stereo originals for desktop only

### Reason
Elemental effects were static aim-bursts that did not track movers, and browser autoplay plus huge stereo WAVs left web builds silent while the PC build worked.

## Version 00.02.22
Date: 10/10/2026
Time: 10:33 AM

### Changes
- Music restarts on every web audio unlock / first SFX click so browsers that blocked autoplay still start the menu and in-game loops
- Music context is stored even before unlock; game runs unlock before selecting the bed; null/failed loops are skipped cleanly

### Reason
Web autoplay blocked the first music start, and later unlocks did not force a replay, so the game stayed silent while button SFX still worked.

## Version 00.02.21
Date: 10/10/2026
Time: 10:31 AM

### Changes
- Web Settings now includes **Install app** (Chrome install prompt or Safari Add to Home Screen help); removed the floating install chip so install lives only in Settings

### Reason
Players should install from Settings on phone browsers, not from a separate overlay button.

## Version 00.02.20
Date: 10/10/2026
Time: 10:21 AM

### Changes
- Phone **Fullscreen** now opens a real on-page tap target (Godot canvas clicks are not a trusted fullscreen gesture)
- Restored PWA install: **Install app** button when Chrome offers `beforeinstallprompt`, iPhone **Add to Home Screen** tip, manifest `short_name` + 192px icon
- Web export re-stamps `mobile_play.js` / cache version until Godot stops overwriting `docs/index.html`

### Reason
Live Pages HTML lost the mobile helper after export, so Fullscreen did nothing, and the install affordance disappeared on phones.

## Version 00.02.19
Date: 10/10/2026
Time: 3:21 AM

### Changes
- Music loops load through Godot’s imported `AudioStreamWAV` (so web/export packs work) and stay uncompressed PCM with forward looping instead of lossy import compression

### Reason
Exported builds only packed compressed samples, not the raw WAVs FileAccess was reading, so web music failed or sounded staticy.

## Version 00.02.18
Date: 10/10/2026
Time: 3:20 AM

### Changes
- Pause “Coming up” wave list now uses plain words (normal, faster enemies, air enemies, boss types) instead of cryptic symbols like `·`, `!`, and `A`

### Reason
The old W1 · W7 ! W8 A shorthand was unreadable without a legend.

## Version 00.02.17
Date: 10/10/2026
Time: 3:19 AM

### Changes
- Cleared staticy music: removed Music-bus amplify/limiter crush, stopped per-sample envelope zipper noise, used 16-step triangle levels, tucked noise drums, and regenerated loops with a gentle soft make-up instead of hard tanh boosting

### Reason
The beds were over-driven into soft clipping and volume stairs were updating every sample, which made the 8-bit loops sound grainy and unclear.

## Version 00.02.16
Date: 10/10/2026
Time: 3:14 AM

### Changes
- Raised the menu, standard, and siege loops so they are loud enough to hear, and made Master apply once (Music and SFX sliders no longer get multiplied by Master a second time)
- Music now starts again if the first play is dropped before the audio device is mixing

### Reason
Opening the game produced no audible music. The loops were about 21 dB below full scale, and a Music slider of 25 was attenuated again by the Master bus, so the bed sat near silence while button sounds stayed loud.

## Version 00.02.15
Date: 10/10/2026
Time: 3:05 AM

### Changes
- Replaced runtime gothic synthesis with original 32-bar 8-bit loops (`audio/music/original_loop_01`–`05.wav`), generated by `audio/music/generate_loops.py` (seamless, band-limited, no samples)

### Reason
Music should follow the NES looping-music rules: original, seamless, and free of high-pitched aliasing.

## Version 00.02.14
Date: 10/10/2026
Time: 2:50 AM

### Changes
- Fixed gothic music script types so `procedural_music.gd` compiles (`bar_phase`, `age`, `u`)

### Reason
Godot could not infer those variables, so music failed to build and the game started silent.

## Version 00.02.13
Date: 10/10/2026
Time: 2:55 AM

### Changes
- Gothic beds rewritten to flow: legato melody, organ chords that crossfade, calm/intense layers locked to the same tempo

### Reason
Notes were retriggering every fraction of a beat, and the tense layer was a different speed, so the music felt chopped.

## Version 00.02.12
Date: 10/10/2026
Time: 2:50 AM

### Changes
- Pause menu (Esc) shows map seed and **Copy seed** when the run has a seed (same clipboard format as the run summary)

### Reason
Players asked for copy-seed on the Esc menu, not only at game over.

## Version 00.02.11
Date: 10/10/2026
Time: 2:48 AM

### Changes
- Pause menu (Esc) is shown on the HUD layer and centered on the screen

### Reason
The overlay was a child of the Node2D board, so it sat on the map instead of the viewport center.

## Version 00.02.10
Date: 10/10/2026
Time: 2:45 AM

### Changes
- Gothic beds retuned darker and lower: cello-range melody, pedal organ, low church toll; removed 880 Hz bells and octave-up lead

### Reason
High-pitched bells/leads washed out the gothic feel.

## Version 00.02.09
Date: 10/10/2026
Time: 2:42 AM

### Changes
- Music now builds on the main thread after the first frame (WAV resources were failing silently on a worker thread); menu bed plays as soon as it is ready

### Reason
Players heard click/death SFX but no background music.

## Version 00.02.08
Date: 10/10/2026
Time: 2:55 AM

### Changes
- Gothic background music shortened to ~25–30 s seamless loops (still organ/bass/melody/drums); UI clicks stay short SFX, not the music bed

### Reason
Long tracks were heavy to generate; shorter loops still feel like music and wrap cleanly.

## Version 00.02.07
Date: 10/10/2026
Time: 2:50 AM

### Changes
- Music no longer builds during splash: SFX load immediately; gothic tracks generate on a background thread and cache to `user://` for later launches

### Reason
Generating five ~2-minute songs in autoload `_ready()` froze the game on the Godot splash.

## Version 00.02.06
Date: 10/10/2026
Time: 2:45 AM

### Changes
- Background music reworked as **gothic** tracks (~2 min menu, ~1.5 min in-run): harmonic minor / Phrygian, organ pads, bell lead, timpani; loops are period-matched for seamless repeats

### Reason
Players wanted real gothic music that does not click or drift when it loops.

## Version 00.02.05
Date: 10/10/2026
Time: 2:40 AM

### Changes
- **Copy seed** moved to the run summary (end screen); removed from in-run tower sidebar

### Reason
Seed sharing fits the end-of-run stats flow, not mid-game tower UI.

## Version 00.02.04
Date: 10/10/2026
Time: 2:35 AM

### Changes
- Background music is now **sequenced songs** (kick/snare/hat patterns, bass lines, bar chords, lead melodies) via `procedural_music.gd`; SFX unchanged including exit-leak tone

### Reason
Loops sounded like continuous tones; players wanted actual musical structure.

## Version 00.02.03
Date: 10/10/2026
Time: 2:30 AM

### Changes
- Version numbering corrected to continue **00.02.xx** (00.02.01–03); renames mistaken 00.03.xx labels in the changelog
- Run summary is centered and shown alone: tower shop, actions, top HUD, and debug panel hide while the modal is up; board selection and range ring clear
- Procedural music uses stereo grooves (kick, hats, arps, pads); UI and gameplay SFX refreshed; exit-leak sound unchanged
- Web export script tolerates harmless Godot non-zero exit when `docs/index.html` is written; refreshed GitHub Pages build

### Reason
End-of-run stats should be the only focus, and background audio should feel less flat without losing the leak cue players liked.

## Version 00.02.02
Date: 10/10/2026
Time: 2:18 AM

### Changes
- `play.ps1` no longer fails when Godot prints harmless stderr warnings during headless preflight (WinGet shim)

### Reason
Launcher reported exit code 1 even though the project loaded; PowerShell treated Godot leak warnings as terminating errors.

## Version 00.02.01
Date: 10/10/2026
Time: 2:15 AM

### Changes
- Onboarding: main-menu tooltips; first-run guided tutorial; Settings → Replay Tutorial
- Procedural music (menu / Classic+Random / Siege) and SFX with Master/Music/SFX sliders; tension rises as enemies near the exit; boss waves use a hotter mix
- Run summary (coaching stats) before leaderboard; device personal bests; persistent hard achievements (Settings → Achievements)
- In-game: pause menu with upcoming-wave timeline; build-speed slider (prep/intermission); next-wave briefing; copy seed; tower range ring; boss HP bar; optional enemy HP bars and grid coordinates; performance mode; maze PNG export
- High-contrast creep outlines; Command ability ready pulse

### Reason
Ship the onboarding + QoL + meta plan without mid-run saves (roguelike).

## Version 00.02.00
Date: 10/10/2026
Time: 1:36 AM

### Changes
- Main menu uses three columns: Map, Monsters, and Difficulty side by side

### Reason
Keep difficulty with the other run choices instead of a full-width block below.

## Version 00.01.99
Date: 10/10/2026
Time: 1:33 AM

### Changes
- Center the View Seeds map preview horizontally in the dialog

### Reason
The preview sat left-aligned while the rest of the controls were centered.

## Version 00.01.98
Date: 10/10/2026
Time: 1:32 AM

### Changes
- View Seeds is a compact no-scroll dialog: shorter chrome, map preview sized to the remaining space
- Removed the extra Preview button (Randomize / Enter / map-type change refresh the map)

### Reason
Players asked to drop scrolling in the seed browser by fitting everything on screen.

## Version 00.01.97
Date: 10/10/2026
Time: 1:29 AM

### Changes
- Fix menu popups collapsing to an empty bordered box (ScrollContainer had 0 height)
- Popups size to their content again; scroll wraps in only when taller than the screen

### Reason
Settings / View Seeds / Map setup appeared as a dim screen with a blank strip after the on-screen clamp change.

## Version 00.01.96
Date: 10/10/2026
Time: 1:25 AM

### Changes
- Settings / View Seeds / Map setup popups are capped to the visible screen with padding and scroll if content is tall
- Seed preview height scales down further on short viewports so the dialog stays fully on-screen

### Reason
Popup windows were overflowing off the bottom of the screen.

## Version 00.01.95
Date: 10/10/2026
Time: 1:23 AM

### Changes
- View Seeds map preview scales the whole board into a small box so Classic/Random/Siege maps are fully visible (no crop)

### Reason
The seed preview was too large / clipped, so players could not see the full layout.

## Version 00.01.94
Date: 10/10/2026
Time: 1:21 AM

### Changes
- Mouse-wheel zoom on Siege / oversized maps: scroll out shrinks the board (down to fit), scroll in restores native size
- Zoom is cursor-anchored; pan/placement use the zoomed coordinate space

### Reason
Siege boards are larger than the view; players asked to zoom out to see more of the map.

## Version 00.01.93
Date: 10/10/2026
Time: 1:19 AM

### Changes
- Settings is a menu **popup** (Large Controls, Effects, Fullscreen, Close) instead of inline controls
- **View Seeds** inside Settings previews Classic Custom / Random / Siege maps from a typed or randomized seed; **Use seed** fills Map setup
- Siege layout generation records `last_layout_seed` like random maps

### Reason
Players asked for Settings as its own small window and a way to browse map seeds before starting a run.

## Version 00.01.92
Date: 10/10/2026
Time: 1:14 AM

### Changes
- Burn / Freeze / Poison towers show short attack VFX (flame jet, ice shards, green cloud) capped at tower range
- Lightning bolt flashes and those VFX respect a new **Effects** Settings toggle (default on, saved in `user://settings.cfg`)

### Reason
Players wanted clearer elemental attack feedback, with an option to turn cosmetics off.

## Version 00.01.91
Date: 10/10/2026
Time: 1:05 AM

### Changes
- On large/Siege maps, left-click no longer starts pan on walls/towers, so towers can be built over walls again
- Dragging after pressing a wall/tower still pans; rocks/spawn/exit still pan on press

### Reason
Siege pan was stealing every click on occupied cells, which blocked the intended tower-on-wall placement.

## Version 00.01.90
Date: 10/10/2026
Time: 12:57 AM

### Changes
- Command combat abilities (Air Strike, Barricade Spike, Recon Flare) place as **path traps**; gold spends on successful place and the effect waits for enemies
- Supply Drop still applies instantly but only spends gold when at least one tower is buffed
- Ability buttons use tower-style tooltips (cost, aim, cooldown, stats); Command tower blurb updated

### Reason
Players were wasting gold on missed ability casts and had no hover stats for abilities like other towers.

## Version 00.01.89
Date: 10/10/2026
Time: 12:55 AM

### Changes
- Leaderboard fetch reads the **Cloudflare Worker** (live KV) when configured, instead of only the often-stale GitHub `data` file
- Never replace local boards with a completely empty remote payload
- Leaderboard unit test writes to a temp file so it cannot wipe player scores

### Reason
Global Easy scores existed on the Worker, but the game loaded an empty GitHub JSON and wiped the board.

## Version 00.01.88
Date: 10/10/2026
Time: 12:53 AM

### Changes
- Leaderboard entries store and show map **seed(s)** from the run
- Single seed displays inline; multiple seeds show **Seeds ×N** — click opens a dialog listing every map seed
- Cloudflare Worker `normalizeEntry` / POST keep the `seeds` array (redeploy Worker for global boards)

### Reason
Players asked to see which seeds high scores used, including every Random sector seed.

## Version 00.01.87
Date: 10/10/2026
Time: 12:51 AM

### Changes
- Classic/Random difficulty opens a **Map setup** step: Classic Standard vs Custom layout; optional seed (blank rolls one)
- Classic Custom uses a seeded random layout fixed for the whole run; Random uses a run seed with per-sector seeds
- HUD shows the current map **Seed** on Random and Classic Custom so maps can be replayed later

### Reason
Let players share and replay specific maze layouts via seeds while keeping Classic’s no-rotate runs.

## Version 00.01.86
Date: 10/10/2026
Time: 12:44 AM

### Changes
- Added **Siege** map mode: 32×32 board, center exit, outer-rim spawn that moves every 5 waves (towers stay); drag to pan when the map is larger than the view
- Remade the main menu: title + `ver:` on one line; Map | Monsters columns; difficulty / leaderboard / Settings / Quit below
- Settings: persistent **Large Controls** (smaller tiles, bigger buttons/sidebars) and web **Fullscreen** (yellow top-right Fullscreen button kept)

### Reason
Add a center-defense map mode with scrolling, and phone-friendly controls toggled only from the menu.

## Version 00.01.85
Date: 10/07/2026
Time: 11:35 PM

### Changes
- Rebuilt and shipped the GitHub Pages web build in `docs/` through **00.01.85** (includes Command tower + SNAKE boss from 00.01.83–84)
- Hardened `export_builds.ps1 -WebOnly` so version/cache stamps are verified on disk after Godot finishes writing

### Reason
Live site was still on 00.01.82 because newer features were never re-exported to `docs/`.

## Version 00.01.84
Date: 10/07/2026
Time: 11:30 PM

### Changes
- Added **Command** tower (100g): no auto-attack; click it to buy pay-per-use abilities
- Abilities: Air Strike (path cross damage), Supply Drop (tower fire-rate buff), Barricade Spike (ground slow+DoT), Recon Flare (mark for bonus damage)
- Each ability costs gold every cast; short cooldown after use; aim a path/board tile after selecting the ability

### Reason
Add a support “command post” playstyle where players spend gold on deliberate strikes and buffs instead of another auto-firing turret.

## Version 00.01.83
Date: 10/07/2026
Time: 11:25 PM

### Changes
- Boss waves can randomly become a **SNAKE**: all wave mobs spawn as a tougher ground chain that follows the head
- Snake head is a marked boss segment; body segments have ~30% more HP than normal creeps; banner shows **SNAKE**
- No air units on snake waves; segments spawn quickly so the chain stays tight

### Reason
Add a random boss-wave variant that feels distinct from normal / flying bosses.

## Version 00.01.82
Date: 10/03/2026
Time: 11:30 PM

### Changes
- Set live leaderboard `API_BASE_URL` to `https://wave-defence-leaderboard.thebotcoder.workers.dev`
- Deployed Cloudflare Worker; fixed invalid JSON on the `data` branch; hardened Worker error handling

### Reason
Finish Cloudflare upload path so scores can sync worldwide.

## Version 00.01.81
Date: 10/03/2026
Time: 11:27 PM

### Changes
- Setup app: handle missing `workers.dev` subdomain, add **Retry deploy only** button, enable `workers_dev` in wrangler.toml

### Reason
First deploy got stuck because Cloudflare requires a one-time workers.dev subdomain registration.

## Version 00.01.80
Date: 10/03/2026
Time: 11:25 PM

### Changes
- Fixed Windows setup app encoding so PowerShell can parse `Setup-Leaderboard.ps1` (ASCII-only text)

### Reason
Em-dashes in the script were mis-decoded and crashed the helper on launch.

## Version 00.01.79
Date: 10/03/2026
Time: 11:22 PM

### Changes
- Added Windows leaderboard setup app: `leaderboard-api/Setup-Leaderboard.bat` + `Setup-Leaderboard.ps1`

### Reason
Give a double-click guided UI for Cloudflare/GitHub token/deploy so setup does not require bash or pasting secrets into chat.

## Version 00.01.78
Date: 10/03/2026
Time: 11:21 PM

### Changes
- Added `leaderboard-api/setup-leaderboard.sh` one-shot Cloudflare setup (login, KV, GitHub secret, deploy)

### Reason
Make Worker setup a single script the user can run locally without pasting secrets into chat.

## Version 00.01.77
Date: 10/03/2026
Time: 11:17 PM

### Changes
- Shared leaderboards read/write the dedicated GitHub **`data`** branch (`leaderboard.json` only)
- Worker `GITHUB_BRANCH` and client `LEADERBOARD_READ_URL` point at `data` instead of `main`

### Reason
Keep score commits off the game history on `main`.

## Version 00.01.76
Date: 10/03/2026
Time: 11:12 PM

### Changes
- Leaderboard fetch no longer wipes local scores when global upload is not configured (merge instead of replace)
- Re-apply pending unsynced scores after a remote replace when upload is configured
- Clearer UI: â€œSaved on this deviceâ€ / â€œLocal (this device)â€ until `API_BASE_URL` is set

### Reason
Scores looked unsaved because the empty GitHub `leaderboard.json` was overwriting local boards on every sync, and the Cloudflare Worker URL was never set so uploads could not run.

## Version 00.01.75
Date: 10/03/2026
Time: 11:03 PM

### Changes
- Air creeps: HP ~70% of ground (was 85%), speed ~1.05Ã— ground (was 1.15Ã—)
- Flying bosses: HP 8.5Ã— creep (was 10Ã—), slightly slower

### Reason
Air units were too hard to kill for the pathing advantage they already have.

## Version 00.01.74
Date: 10/03/2026
Time: 10:55 PM

### Changes
- PC HUD matches mobile: tower shop on the left, actions on the right
- Debug (F1/~) is a floating overlay over the board instead of the right gutter

### Reason
Dual sidebars look better on desktop; debug needed a new home once Actions took the right strip.

## Version 00.01.73
Date: 10/03/2026
Time: 10:51 PM

### Changes
- Soften selected Map / Monsters green border and text (less bright)

### Reason
Selection highlight was too neon.

## Version 00.01.72
Date: 10/03/2026
Time: 10:52 PM

### Changes
- Fix web export so `VER` inject and service-worker `CACHE_VERSION` actually ship to GitHub Pages
- Keep menu version under the title and green Map/Monsters selection border

### Reason
Live site was still serving HTML/SW without cache-bust tags, so Incognito kept the old yellow menu.

## Version 00.01.71
Date: 10/03/2026
Time: 10:50 PM

### Changes
- Main menu version sits under the title (was below Quit and easy to miss on phones)
- Selected Map / Monsters options use a thicker green border + green text (not yellow tint)
- Ship web cache auto-clear + SW `CACHE_VERSION` stamp from prior fix

### Reason
Players still saw the old yellow highlight and thought the version vanished; phone scroll hid it under the menu.

## Version 00.01.70
Date: 10/03/2026
Time: 10:46 PM

### Changes
- Web: on VERSION change, unregister the service worker and clear caches (Ctrl+F5 cannot)
- Web export stamps `CACHE_VERSION` in the service worker from `VERSION`
- Main menu Map / Monsters choices show a green border on the selected option

### Reason
Chrome keeps serving the old PWA cache; players could not hard-refresh to a new build.

## Version 00.01.69
Date: 10/03/2026
Time: 10:44 PM

### Changes
- Main menu Map / Monsters choices show a green border on the selected option

### Reason
Make Classic vs Random selection easier to see at a glance.

## Version 00.01.68
Date: 10/03/2026
Time: 10:45 PM

### Changes
- Main menu **Monsters** row: Classic (standard mix) or Randomize (elemental types)
- Randomize monsters (Ember/Frost/Venom/Spark/Brute) have slight Fire/Ice/Poison/Lightning resists that grow to all 4 by wave 50
- HUD shows Map + Monsters mode; elemental hits/DoTs respect resists

### Reason
Let players control spawn flavor independently of map mode, with late-wave resist pressure.

## Version 00.01.67
Date: 10/03/2026
Time: 2:50 PM

### Changes
- New **Gatling** tower: 25000 gold, unlocks at wave 30, extreme fire rate (fast projectiles)
- Shop shows locked towers as `(W30)` until unlocked; other towers can still be built around Gatling

### Reason
Add a late-game special tower for Classic/Random runs past wave 30.

## Version 00.01.66
Date: 10/03/2026
Time: 2:41 PM

### Changes
- Early-send no longer re-queues unspawned leftovers (was stacking hundreds of enemies by ~wave 60 Classic)
- Block Send Next Wave when board pressure (alive + queued) hits a hard cap
- Cache ground path between spawns; rebuild only when towers change
- Fix web export post-process so version cache-bust + mobile helper actually stay in `docs/index.html`

### Reason
Classic runs around wave 60 were freezing/crashing under stacked early-send load.

## Version 00.01.65
Date: 10/03/2026
Time: 1:48 PM

### Changes
- After screen timeout / app switch, show a floating **Fullscreen** button on any screen (not only the main menu)
- Re-apply landscape CSS when the page becomes visible again

### Reason
Waking the phone dropped browser fullscreen with no way back mid-run.

## Version 00.01.64
Date: 10/03/2026
Time: 11:53 AM

### Changes
- Web menu **Fullscreen** button (no more tap-anywhere fullscreen)
- Removed unused mobile tip banner / auto-gesture fullscreen helpers

### Reason
Fullscreen should be an explicit control; extra unused mobile UI was getting in the way.

## Version 00.01.63
Date: 10/03/2026
Time: 11:43 AM

### Changes
- Web **Quit** exits fullscreen, clears CSS landscape rotate, unlocks orientation, and tries `history.back()` so users return to Discord/prior page

### Reason
Quit on the GitHub web build should undo mobile presentation and let people get back to what they were doing.

## Version 00.01.62
Date: 10/03/2026
Time: 11:41 AM

### Changes
- Stop re-requesting fullscreen / forcing canvas resize on **every** mobile tap (was black-flashing the WebGL view)
- Fullscreen is one-shot after the first gesture; CSS landscape only updates when orientation changes

### Reason
Button presses on the phone web build were blanking the screen until another tap.

## Version 00.01.61
Date: 10/03/2026
Time: 11:36 AM

### Changes
- Mobile web: **CSS 90Â° rotate** when the phone is upright so the game fills the screen as landscape without relying on OS orientation lock
- Stronger fullscreen attempts; tip to **Open in Chrome** / Add to Home Screen when Discord/in-app browsers block the top-bar hide

### Reason
In-app browsers keep the URL bar, and orientation.lock often fails â€” CSS rotate + real Chrome/PWA is the practical path.

## Version 00.01.60
Date: 10/03/2026
Time: 11:31 AM

### Changes
- Mobile web: fullscreen then landscape lock (Android-friendly order), retry on taps
- Full-screen **Rotate your phone** overlay when the browser is in portrait
- Enable web PWA landscape/fullscreen manifest; clearer iPhone Add-to-Home-Screen hint

### Reason
Phones detected mobile mode but browsers (especially iPhone Safari) block forced fullscreen/rotation.

## Version 00.01.59
Date: 10/03/2026
Time: 11:26 AM

### Changes
- Web export cache-busts `.pck` / `.wasm` / `.js` with the VERSION query so phones pick up new builds without a hard refresh

### Reason
GitHub Pages was serving a fresh 00.01.58 build, but phone browsers still showed cached 00.01.56.

## Version 00.01.58
Date: 10/03/2026
Time: 11:24 AM

### Changes
- Show the mobile-web fullscreen hint near the **top** of the main menu (was clipped off-screen under tall buttons)
- Stronger mobile-browser detection + touch/size fallbacks
- Scrollable main menu on phones so controls stay reachable

### Reason
Phone players could not see the â€œtap for fullscreenâ€ message.

## Version 00.01.57
Date: 10/03/2026
Time: 11:19 AM

### Changes
- Detect mobile devices including **mobile browsers** (`GameLayout.is_mobile_device`)
- On mobile: lock **sensor landscape** and enter **fullscreen** (web: after first tap, as browsers require a gesture)
- Desktop browsers/PCs are not forced fullscreen
- Web export viewport / mobile web-app meta tags for phone browsers

### Reason
Phone web play should match Androidâ€™s landscape fullscreen feel without affecting desktop players.

## Version 00.01.56
Date: 10/03/2026
Time: 10:44 AM

### Changes
- Proprietary **All Rights Reserved** `LICENSE` and GitHub repo wiring for Zephino/WaveDefence
- Web export to `docs/` for GitHub Pages; `export_builds.ps1 -WebOnly`
- Shared worldwide Easy/Medium/Hard leaderboards via `leaderboard.json` + Cloudflare Worker (`leaderboard-api/`)
- Clients bootstrap global boards on launch; push score on submit and again when leaving the leaderboard if still pending
- Menu/leaderboard show Global vs Local (offline) status

### Reason
Let anyone play in a browser, keep one shared scoreboard across web/PC/Android/iOS, and protect commercial use of the project.

## Version 00.01.55
Date: 10/03/2026
Time: 10:12 AM

### Changes
- Show **Quit** on the main menu for touch/Android (and all platforms), not desktop-only

### Reason
Android had no way to exit from the main menu.

## Version 00.01.54
Date: 10/03/2026
Time: 10:03 AM

### Changes
- Centralized in-app version reading via `VersionInfo` (menu + HUD)
- Falls back to `application/config/version` so exports always show the current version
- Synced VERSION / project / Android / iOS export version fields to 00.01.54

### Reason
Ensure the version shown in the app updates with each release build.

## Version 00.01.53
Date: 10/03/2026
Time: 10:02 AM

### Changes
- Added **Spike** tower (melee, ground-only, short range, high damage)
- Added **Anti-Air** tower (air-only flak, long range)
- Targeting filters for ground-only / air-only towers
- Split phone builds into `phone/android/` and `phone/ios/`; added iOS export preset
- `export_builds.ps1` exports Android here and skips iOS unless on macOS

### Reason
Add specialized ground melee and dedicated AA options, and support shipping Android + iOS phone packages in separate folders.

## Version 00.01.52
Date: 10/03/2026
Time: 1:36 AM

### Changes
- Renamed game mode **Endless** â†’ **Random** (menu, HUD, docs)
- Menu button text: â€œRandom â€” shifting maps every 25 wavesâ€

### Reason
Both modes are endless wave runs; â€œEndlessâ€ was confusing next to Classic.

## Version 00.01.51
Date: 10/03/2026
Time: 1:34 AM

### Changes
- Selected towers/walls use a green outline instead of yellow
- Selection also draws a green circle around the unit (range ring tinted green too)

### Reason
Make selected towers easier to spot and match a clearer green selection style.

## Version 00.01.50
Date: 10/03/2026
Time: 1:33 AM

### Changes
- In-game **Main Menu** replaced with **End Run**
- End Run shows a confirm popup, then submits the run to the leaderboard

### Reason
Leaving mid-run should score the attempt instead of discarding it with no confirmation.

## Version 00.01.49
Date: 10/03/2026
Time: 1:31 AM

### Changes
- Main menu **Classic / Endless** mode select
- Endless: random spawn/exit and rock tiles; new map every 25 waves with kill-based rebuild gold
- Classic keeps the fixed map; HUD shows mode / map sector

### Reason
Add a longer endless run with shifting boards, while keeping the original fixed-map experience.

## Version 00.01.48
Date: 10/03/2026
Time: 1:28 AM

### Changes
- Separate leaderboards for Easy / Medium / Hard (tabs on the leaderboard screen)
- Scores save to the board for the runâ€™s difficulty; old single-board saves migrate to Medium

### Reason
Easy and Hard runs were sharing one scoreboard, so difficulties were not comparable.

## Version 00.01.47
Date: 10/03/2026
Time: 1:26 AM

### Changes
- Phone releases screen orientation when the app is closed or backgrounded, then locks landscape again on resume

### Reason
Leaving the game should let the phone return to its normal portrait/auto-rotate behavior.

## Version 00.01.46
Date: 10/03/2026
Time: 1:22 AM

### Changes
- Phone orientation set to sensor landscape so the device can auto-rotate either landscape way

### Reason
Players should be able to hold the phone with either long edge down.

## Version 00.01.45
Date: 10/03/2026
Time: 1:21 AM

### Changes
- Phone UI: tower shop on the left, actions on the right (uses both side gutters)
- Removed the touch sidebar scrollbar

### Reason
The phone layout had empty space on the right while the left shop needed scrolling.

## Version 00.01.44
Date: 10/03/2026
Time: 1:20 AM

### Changes
- Walls and towers can no longer be placed on an existing tower (sell first)
- Removed shop multi-rebuild; only building a tower on top of a wall still replaces
- Docs/help updated for the new placement rules

### Reason
Players should sell a tower before putting anything else on that cell.

## Version 00.01.43
Date: 10/03/2026
Time: 1:13 AM

### Changes
- Final Fire/Ice/Poison/Lightning upgrades are light buffs that keep the towerâ€™s type and primary effect
- Same-element finals strengthen the existing effect; different elements add a mild bonus (e.g. Burn + Ice still burns and slows a little)

### Reason
Picking Ice on a maxed Fire tower was turning it into an Ice tower instead of adding a slight Ice buff.

## Version 00.01.42
Date: 10/03/2026
Time: 1:00 AM

### Changes
- Main menu Easy / Medium / Hard difficulty (starting gold 350 / 200 / 100)
- HUD shows the selected difficulty; Play Again keeps the same difficulty

### Reason
Give players a softer or tighter start by changing opening money.

## Version 00.01.41
Date: 10/03/2026
Time: 12:59 AM

### Changes
- Display stretch aspect set to `keep` so the game stays centered on phone screens (letterboxed when the aspect ratio differs)

### Reason
On the phone build, expand mode left the playfield stuck to the corner instead of centered.

## Version 00.01.40
Date: 10/03/2026
Time: 12:46 AM

### Changes
- Built real play packages: `pc/WaveDefence.exe` and `phone/WaveDefence.apk`
- Added `export_builds.ps1` so both folders refresh from the one project source
- Enabled ETC2/ASTC texture import for Android export
- Simplified Android preset (non-Gradle APK) and ignored release binary folders in the editor

### Reason
The release folders need the actual install/run files, kept in sync by re-exporting after code changesâ€”not duplicate source trees.

## Version 00.01.39
Date: 10/03/2026
Time: 12:19 AM

### Changes
- Split release outputs into `pc/` and `phone/` folders
- Windows export â†’ `pc/WaveDefence.exe`; Android export â†’ `phone/WaveDefence.apk`
- Added a short README in each folder for sending / installing

### Reason
Make it obvious which build to send for PC vs phone.

## Version 00.01.38
Date: 10/03/2026
Time: 12:16 AM

### Changes
- Touch / mobile play support: drag place, long-press multi-select, Multi toggle, tap-to-inspect
- Scrollable sidebar with larger buttons on touch devices
- Tap empty/unplaceable cells or outside the board to deselect
- Display stretch expand + landscape handheld orientation; Android export preset added
- Menu Quit hidden on mobile (system back/home used instead)

### Reason
Make the game playable on phones/tablets without requiring mouse and keyboard modifiers.

## Version 00.01.37
Date: 10/03/2026
Time: 12:10 AM

### Changes
- Placing a tower (or building over a wall) clears tower selection instead of selecting the new one

### Reason
Newly placed towers were staying selected, which got in the way of place/upgrade flow.

## Version 00.01.36
Date: 10/03/2026
Time: 12:07 AM

### Changes
- Added **SPEED WAVE** every 7 waves (faster creeps, lower HP, denser spawns)
- Banner shows SPEED WAVE; bosses on those waves get a milder speed bump

### Reason
Some waves needed a high-pressure rush tempo instead of only scaling HP.

## Version 00.01.35
Date: 10/03/2026
Time: 12:05 AM

### Changes
- Using the debug menu or debug hotkeys marks the run as invalid for the leaderboard
- Game over after a debug run shows the board but hides name entry

### Reason
Forced/debug runs should not be saveable as high scores.

## Version 00.01.34
Date: 10/03/2026
Time: 12:01 AM

### Changes
- Flying scouts now appear from about wave 8 (not only after wave 50)
- Full air/ground mix starts after wave 20 so mid-game (e.g. wave 40) always has flyers
- Flying-boss waves also include a few air creeps in the pack

### Reason
Forcing to wave 40 showed no flyers because mixed air previously waited until after wave 50.

## Version 00.01.33
Date: 10/02/2026
Time: 11:58 PM

### Changes
- Added **Deselect** sidebar button for clearing selected towers
- **Esc** and **right-click** on the board also clear selection

### Reason
Players needed a clear way to deselect towers after multi-select / upgrade flows.

## Version 00.01.32
Date: 10/02/2026
Time: 11:55 PM

### Changes
- Flying enemies now follow an S-curve air lane over the maze instead of a straight line
- Successive flyers use staggered phases so they don't all stack on one path

### Reason
Straight air paths were too easy to cover with a single tower line and looked flat.

## Version 00.01.31
Date: 10/02/2026
Time: 11:54 PM

### Changes
- Moved boss/air banners into the top bar next to Wave (no longer overlays other text)
- Wave-start status no longer repeats the banner words

### Reason
BOSS WAVE text was stacking over Gold/Wave/status and making the HUD unreadable.

## Version 00.01.30
Date: 10/02/2026
Time: 11:47 PM

### Changes
- **Cannon** is now the boss-focused tower: 2.4Ã— boss damage, prioritizes bosses in range
- Slightly less effective vs normal creeps and air; longer range, tighter splash
- Damage multipliers now support `boss_damage_mult` / `creep_damage_mult`

### Reason
Boss waves needed a clear tower choice built for high-HP boss targets.

## Version 00.01.29
Date: 10/02/2026
Time: 11:45 PM

### Changes
- Towers can be upgraded 3 times (stat boosts); pips show upgrade level
- After +3, choose one final elemental: Fire, Ice, Poison, or Lightning
- Sidebar **Upgrade** + final element buttons; hotkey **U** for stat upgrade
- Sell refund includes gold invested in upgrades
- Walls cannot be upgraded

### Reason
Players wanted a progression path on placed towers ending in a chosen elemental power.

## Version 00.01.28
Date: 10/02/2026
Time: 11:44 PM

### Changes
- Shop tower buttons show hover tooltips with blurb, cost, stats, effects, and air/ground multipliers
- Hovering a placed tower on the board shows the same description tooltip
- Added `TowerData.tooltip_for()` / per-tower `blurb` text in `data/towers.gd`

### Reason
Players needed readable tower descriptions without leaving the game or checking the README.

## Version 00.01.27
Date: 10/02/2026
Time: 11:43 PM

### Changes
- Added top-bar **Left** counter for enemies remaining until the board clears
- Counts enemies on the map plus those still waiting to spawn (hover shows the split)

### Reason
Players needed a clear readout of how many enemies are left before the round ends.

## Version 00.01.26
Date: 10/02/2026
Time: 11:42 PM

### Changes
- After wave 50, regular waves mix flying creeps with ground creeps (interleaved spawns)
- Air mix ratio starts at 20% and ramps toward 40% (`MIXED_AIR_*` in `data/wave_scaler.gd`)
- Banner shows **AIR MIX** on those waves (unless a flying boss banner already applies)

### Reason
Late endless play needed ongoing air pressure, not only scheduled flying bosses.

## Version 00.01.25
Date: 10/02/2026
Time: 11:41 PM

### Changes
- Towers now use per-target air/ground damage multipliers (`air_damage_mult` / `ground_damage_mult`)
- Lightning, Rapid, Freeze, and Gunner deal more damage to flying enemies
- Cannon, Burn, and Poison deal less to air (favor ground packs)
- Hit damage and burn/poison DoT both respect the multiplier

### Reason
Flying bosses need clear anti-air choices instead of every tower treating air and ground the same.

## Version 00.01.24
Date: 10/02/2026
Time: 11:38 PM

### Changes
- With towers selected, clicking a shop tower rebuilds the whole selection into that type
- Rebuild pays the new tower cost and refunds ~50% sell value for each replaced tower
- Same-type cells are kept; unaffordable cells are skipped

### Reason
Multi-select should support mass rebuild via the shop instead of only selling.

## Version 00.01.23
Date: 10/02/2026
Time: 11:33 PM

### Changes
- Moved debug panel into the right gutter beside the board so it no longer covers playfield cells
- Debug panel scrolls if needed to fit the available strip

### Reason
The debug menu was overlapping the maze and blocking placement / visibility.

## Version 00.01.22
Date: 10/02/2026
Time: 11:33 PM

### Changes
- Debug **Force Next Wave** / **N** no longer clears enemies; next-wave spawns overlap with leftovers
- Empty board still forces the next wave to start normally

### Reason
Debug force-round should match early-send overlap behavior instead of wiping the map.

## Version 00.01.21
Date: 10/02/2026
Time: 11:32 PM

### Changes
- **Send Next Wave** (after 25% kills) starts the next wave immediately while leftover enemies stay
- Early send grants a slight gold bonus; skipping build/intermission timers also grants a small time-based bonus
- Leftover enemies no longer inflate the next wave's 25% unlock progress

### Reason
Players expected to be able to call the next round early for overlapping pressure and a small gold reward.

## Version 00.01.20
Date: 10/02/2026
Time: 11:28 PM

### Changes
- Debug **Force Next Wave** (panel + **N**) starts the next wave immediately
- Bypasses prep/build/intermission timers and the 25% skip unlock
- Clears live enemies first; still requires an open spawnâ†’exit path

### Reason
Playtesting needed a way to force the next round even when no skip timer was available.

## Version 00.01.19
Date: 10/02/2026
Time: 11:28 PM

### Changes
- Fixed skip timer: rebuild path before skip checks; clearer fail reasons
- After any wave ends, the break is always skippable
- At 25% kills, **Skip Next Wait** arms an instant skip of the following break
- Failed enemy spawns no longer inflate the 25% kill requirement

### Reason
Skip felt broken because it stayed disabled during waves after 25% kills and post-wave skip rules were unclear.

## Version 00.01.18
Date: 10/02/2026
Time: 11:21 PM

### Changes
- Free-build prep phase with no timer until the player presses **Start Round**
- Start Round begins the build countdown, then waves/intermissions run as before

### Reason
Players asked for untimed maze building before committing to the round timer.

## Version 00.01.17
Date: 10/02/2026
Time: 11:20 PM

### Changes
- Hold left-click and drag to paint-place walls/towers across multiple cells

### Reason
Faster maze building without clicking every tile.

## Version 00.01.16
Date: 10/02/2026
Time: 11:19 PM

### Changes
- Reserved a fixed-width clipped sidebar for HUD buttons so they cannot overlap the board
- Moved the board origin via shared `GameLayout`; shortened wide button labels (tooltips instead)

### Reason
Long Skip/Sell button text widened the sidebar over the leftmost grid columns.

## Version 00.01.15
Date: 10/02/2026
Time: 11:18 PM

### Changes
- Increased board height from 14 rows to 15 rows

### Reason
Give the maze one more row of build space.

## Version 00.01.14
Date: 10/02/2026
Time: 11:18 PM

### Changes
- Multi-select towers/walls with Ctrl+click or Shift+click
- Sell Selected sells the whole selection and shows count + refund on the button

### Reason
Let players clear or reshape mazes faster by selling many blocks at once.

## Version 00.01.13
Date: 10/02/2026
Time: 11:17 PM

### Changes
- Waves auto-start on timers after Start (initial build + intermissions between waves)
- Skip Timer unlocks after killing 25% of a waveâ€™s enemies (first build timer always skippable)
- HUD shows countdown; Send Wave replaced with Skip Timer

### Reason
Match classic timed wave pacing while still letting prepared players push waves early.

## Version 00.01.12
Date: 10/02/2026
Time: 11:14 PM

### Changes
- Fixed wallâ†’tower upgrade briefly opening the cell so enemies could repath through it
- Wall replace no longer emits remove mid-swap; tower place also triggers enemy repath

### Reason
Building on a wall made creeps walk through that tile because repath ran while the wall was gone.

## Version 00.01.11
Date: 10/02/2026
Time: 11:10 PM

### Changes
- Fixed left HUD overlap: Send Wave was drawn on top of the Lightning tower button after Wall was added
- Stacked shop + actions in one sidebar column; disabled sticky button focus highlight

### Reason
Send Wave appeared to sit/hover over Lightning, making that tower hard to click.

## Version 00.01.10
Date: 10/02/2026
Time: 11:08 PM

### Changes
- Allow placing any non-wall tower directly on top of a Wall (replaces the wall; pay only the tower cost)

### Reason
Avoid selling walls before upgrading maze cells into attacking towers.

## Version 00.01.09
Date: 10/02/2026
Time: 11:04 PM

### Changes
- Added flying bosses every 15th wave that travel in a straight line over walls/towers
- Banner shows FLYING BOSS (can combine with ground boss waves); debug jump includes wave 15

### Reason
Give maze walls a counter: air bosses that ignore pathing blocks on a fixed schedule.

## Version 00.01.08
Date: 10/02/2026
Time: 11:03 PM

### Changes
- Added Wall block (cost 5): maze filler that only blocks pathing, no attack

### Reason
Cheap walls make maze building affordable without spending on full towers.

## Version 00.01.07
Date: 10/02/2026
Time: 10:59 PM

### Changes
- Centered the main menu with a full-rect `CenterContainer` instead of a hardcoded position

### Reason
The title screen menu was not centered on screen.

## Version 00.01.06
Date: 10/02/2026
Time: 10:59 PM

### Changes
- Award end-of-wave clear bonus gold based on enemies killed that round
- Show kills and bonus amount in the status line; formula tunable in `data/wave_scaler.gd`

### Reason
Reward clearing rounds with a kill-based gold bonus on top of per-kill bounties.

## Version 00.01.05
Date: 10/02/2026
Time: 10:55 PM

### Changes
- Added main menu with Start, Leaderboard, and Quit
- On losing all lives, boot to leaderboard; qualify for top 10 by wave to enter a name
- Persist leaderboard to `user://leaderboard.json`; in-game Main Menu button returns to title

### Reason
Add title-screen flow and a local high-score board for endless runs.

## Version 00.01.04
Date: 10/02/2026
Time: 10:52 PM

### Changes
- Fixed enemy movement using grid-local path points with `global_position` (map offset made creeps walk off-map / the wrong way)
- Enemies now follow paths in local space and are added to the scene before setup

### Reason
Creeps started by walking opposite/outside the grid because path targets ignored the map offset.

## Version 00.01.03
Date: 10/02/2026
Time: 10:50 PM

### Changes
- Fixed tower placement: fullscreen background ColorRect was capturing mouse clicks (MOUSE_FILTER_STOP)
- Added on-screen status reasons when a place fails; fixed sell using grid-local tower position

### Reason
Players could not place any towers because map clicks never reached the build system.

## Version 00.01.02
Date: 10/02/2026
Time: 10:48 PM

### Changes
- Fixed `play.ps1` / `play.bat` so the project path with a space (`Wave Defence`) is passed to Godot correctly
- Launcher now preflight-checks the project and keeps the window open with `godot_launch.log` if startup fails

### Reason
Double-clicking play.bat closed immediately because Godot received a truncated path (`...\Wave`) and aborted with no visible window.

## Version 00.01.01
Date: 10/02/2026
Time: 10:47 PM

### Changes
- Added `play.bat`, `play.ps1`, and `play.sh` to install Godot (via winget) if needed and launch the game
- Documented one-click / script launch in README

### Reason
Provide an easy way to install prerequisites and start the game without manual setup steps.

## Version 00.01.00
Date: 10/02/2026
Time: 10:43 PM

### Changes
- Created Godot 4 Wave Defence project with maze-builder pathing (AStarGrid2D) and illegal-build rejection
- Added endless waves with boss every 10 and double boss every 50, kill bounties, and lives
- Added basic towers (Gunner, Rapid, Cannon) and elemental towers (Burn, Freeze, Poison, Lightning)
- Added shop UI, sell refund, game over with wave reached, debug panel/hotkeys, README, and Windows export preset
- Added project Cursor rules, root VERSION, and this changelog

### Reason
Implement the approved maze-builder endless tower defence plan as a standalone Godot game with easy playtesting and tunable balance data.

