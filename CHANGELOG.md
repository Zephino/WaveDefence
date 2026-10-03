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
- Renamed game mode **Endless** → **Random** (menu, HUD, docs)
- Menu button text: “Random — shifting maps every 25 waves”

### Reason
Both modes are endless wave runs; “Endless” was confusing next to Classic.

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
- Scores save to the board for the run’s difficulty; old single-board saves migrate to Medium

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
- Final Fire/Ice/Poison/Lightning upgrades are light buffs that keep the tower’s type and primary effect
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
The release folders need the actual install/run files, kept in sync by re-exporting after code changes—not duplicate source trees.

## Version 00.01.39
Date: 10/03/2026
Time: 12:19 AM

### Changes
- Split release outputs into `pc/` and `phone/` folders
- Windows export → `pc/WaveDefence.exe`; Android export → `phone/WaveDefence.apk`
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
- **Cannon** is now the boss-focused tower: 2.4× boss damage, prioritizes bosses in range
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
- Clears live enemies first; still requires an open spawn→exit path

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
- Skip Timer unlocks after killing 25% of a wave’s enemies (first build timer always skippable)
- HUD shows countdown; Send Wave replaced with Skip Timer

### Reason
Match classic timed wave pacing while still letting prepared players push waves early.

## Version 00.01.12
Date: 10/02/2026
Time: 11:14 PM

### Changes
- Fixed wall→tower upgrade briefly opening the cell so enemies could repath through it
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
