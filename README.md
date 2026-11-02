# Wave Defence

An endless maze-building tower defence game. Monsters walk from the start to the
exit; you build walls and towers to make their path as long as possible and shoot
them down on the way. Every monster that gets through costs a life. How many
waves can you survive?

**Play now in your browser:** **https://zephino.github.io/WaveDefence/**
(works on computers, phones and tablets — no download needed).

**Version:** shown on the main menu (also in [`VERSION`](VERSION)).
**License:** proprietary — [All Rights Reserved](LICENSE). Contact via the
[Zephino/WaveDefence](https://github.com/Zephino/WaveDefence) GitHub profile.

---

## Contents

- [Getting the game](#getting-the-game)
- [Your first game](#your-first-game)
- [The main menu](#the-main-menu)
- [Game modes](#game-modes)
- [Difficulty](#difficulty)
- [How a round works](#how-a-round-works)
- [Building your maze](#building-your-maze)
- [Towers](#towers)
- [Monsters and waves](#monsters-and-waves)
- [Clash mode](#clash-mode)
- [Online Clash with friends](#online-clash-with-friends)
- [Controls](#controls)
- [Leaderboard](#leaderboard)
- [Settings](#settings)
- [Tips](#tips)

---

## Getting the game

- **Browser (easiest):** open **https://zephino.github.io/WaveDefence/**. Click or
  tap the game once if the controls seem stuck.
- **Windows:** play `pc/WaveDefence.exe`.
- **Android:** install `phone/android/WaveDefence.apk`.
- **iPhone / iPad:** use the browser link (Safari works fine).

**On a phone:** the game plays sideways (landscape). In **Settings** you can go
**Fullscreen**, or use **Install app** (Chrome) / **Share → Add to Home Screen**
(Safari) to get an app icon.

**Playing offline:** open the game (or the installed app) **once while online**
so everything downloads. After that you can play with no internet, even in
airplane mode. Leaderboard scores wait on your device and upload when you're back
online. Use **Settings → Update app** while online to get the newest version.

**Typing on a phone browser:** tapping a text box (join code, leaderboard name,
map seed, Suggest a Feature) opens a small pop-up with your keyboard. What you
type goes into the box.

---

## Your first game

The first time you open the game, it offers a short **tutorial** (an easy practice
game that isn't scored). You can replay it anytime from **Settings → Replay
Tutorial**. The basics:

1. Pick **Classic** (Map), **Classic** (Monsters), and a difficulty (start with **Easy**).
2. Choose **Standard** map, then start.
3. Open **Towers** and place a few **Walls** to bend the path, then put real
   towers (like **Gunner**) on or beside the walls.
4. Press **Start Round**. You get a short build countdown, then waves start coming
   on their own.
5. Kill monsters for gold, spend it on more towers and upgrades, and don't let
   your lives hit zero.

---

## The main menu

From top to bottom:

- **Map**, **Monsters**, and **Difficulty** columns — pick a map and monster type,
  then press a difficulty to start. On a computer, hover any button for a short
  description.
- **Settings**
- **Leaderboard** and **Play Online** (join a friend's Clash match with a code)
- **Quit** (on phones and the web it asks first)
- **Suggest a Feature** — send an idea to the developer, anonymously, from inside
  the game.

The bottom of the menu may show your best Medium wave on this device.

---

## Game modes

### Map

| Map | What it is |
|-----|-----------|
| **Classic** | One board for the whole game. After picking a difficulty, choose **Standard** (fixed left-to-right corridor) or **Custom layout** (a random board made from a **seed** number — type one in, or leave blank for a random one). |
| **Random** | A new board every **25 waves**. You can type a starting seed. The screen shows each board's seed so you can replay it later in Classic → Custom. |
| **Siege** | A bigger board with the **exit in the middle** and monsters coming in from the edge. The entrance moves every **5 waves** (your towers stay). Scroll to zoom; move the view with **Actions → Pan**, by holding **Space**, or with the right/middle mouse button. |
| **Clash** | 2–4 players side by side, each defending their own lane, sending monsters at each other. See [Clash mode](#clash-mode). |

### Monsters

| Monsters | What it is |
|----------|-----------|
| **Classic** | The normal mix of ground monsters, fliers and bosses. |
| **Randomize** | Monsters come in elemental types (Ember, Frost, Venom, Spark, Brute) that resist some damage (Fire, Ice, Poison, Lightning). Resistances grow as waves go on; by wave 50 they can have all four. Mix your tower types! |

Clash always uses Classic monsters.

---

## Difficulty

Applies to Classic, Random and Siege. Clash has its own setup.

| | Easy | Medium | Hard |
|---|---|---|---|
| Starting gold | 350 | 200 | 100 |
| Lives | 20 | 15 | 10 |
| Monster health | +30% | +60% | +100% |
| Monster speed | +5% | +10% | +15% |
| Monsters per wave | normal | +10% | +20% |
| Gold from kills and bonuses | 100% | 90% | 80% |
| First boss | wave 10 | wave 8 | wave 6 |
| First fliers | wave 8 | wave 6 | wave 4 |

---

## How a round works

1. **Build time.** At the start there's **no timer** — build as long as you like.
2. Press **Start Round**. A short **build countdown** runs, then the first wave comes.
3. After each wave there's a short **break**, then the next wave starts by itself.
4. **Skip the timer** anytime during a countdown or break for a little bonus gold
   (more gold for more time left).
5. **Send Next Wave early:** once you've killed **25%** of a wave, you can call the
   next wave right away for bonus gold. Monsters already on the board stay.
6. Clearing a wave pays a **clear bonus** based on how many monsters you killed.
7. The game ends when your lives reach **0** (or you press **End Run** and confirm).
   You'll see a **run summary** with tips, then the leaderboard.

The top of the screen shows your gold, lives, the wave, the timer, and **Left**
(monsters still to come or on the board). The **next wave** line warns you what's
coming (boss, fliers, speed wave…).

---

## Building your maze

- Monsters always take the **shortest open path** from start to exit. Your job is
  to make that path long, and line it with towers.
- **Walls** are cheap (5 gold) and only block. Use them to shape the maze.
- **Build a tower on a wall** to replace it: pick a combat tower and tap the wall.
- You **can't** block the path completely — the game won't let you place a piece
  that seals it. (If the path somehow ends up blocked when a wave starts, the
  blocking pieces are removed and refunded.)
- You can't build on top of a tower — **sell it first**.
- **Upgrade:** select towers and press **Upgrade** (or **U**). Each tower takes
  **3** upgrades (yellow pips show how many).
- **Final element:** after 3 upgrades, choose **Fire, Ice, Poison or Lightning**
  for an extra effect (for example, burn plus a slight slow). One per tower.
- **Sell:** select towers or walls and press **Sell** for about half of what you
  spent.
- **Move the start or end (wave 10+):** between waves, a cyan bar on the top-left
  of the map lets you slide the start or exit one square left or right for
  **200 gold** per move (it can't seal the path).

---

## Towers

| Tower | Cost | What it does |
|-------|------|--------------|
| Wall | 5 | Blocks the path only. Build a real tower on it to replace it. |
| Gunner | 40 | Basic single-target shooter. Slightly better vs fliers. |
| Rapid | 55 | Fast, low damage. Strong vs fliers. |
| Cannon | 75 | Boss hunter (much more damage to bosses), splash damage. Weak vs fliers. |
| Burn | 50 | Sets monsters on fire (damage over time). Weak vs fliers. |
| Freeze | 60 | Slows monsters. Good vs fliers. |
| Poison | 70 | Poison over time plus a little splash. |
| Lightning | 80 | Chains between monsters. Very strong vs fliers. |
| Spike | 45 | Melee, ground only. Huge damage at very short range — put it right next to the path. |
| Anti-Air | 65 | Fliers only. Long-range missiles. |
| Vortex | 90 | Unlocks at wave **12**. No damage; takes a 3×3 area and spins monsters on its ring around once, buying time. |
| Gatling | 25,000 | Unlocks at wave **30**. Late-game monster with an extreme fire rate. |
| Command | 100 | Doesn't shoot. Select it to use paid abilities: **Air Strike**, **Barricade Spike** and **Recon Flare** are traps you place on the path (gold is only spent when placed, and they wait for monsters); **Supply Drop** boosts nearby towers' fire rate. |

Hover a tower (or tap it on a phone) to see its full stats.

---

## Monsters and waves

- Waves get bigger and tougher forever.
- **Bosses** come every **10 waves**, and **two bosses** every **50**. Some boss
  waves turn into a **SNAKE**: the whole wave becomes one long, tough chain.
- **Flying bosses** come every **15 waves**. Fliers ignore your maze and weave
  over it in an S-shape, so you need towers that hit air.
- **Fliers** start showing up around **wave 8**, and after **wave 20** every wave
  mixes fliers in.
- Every **7th wave** (7, 14, 21…) is a **SPEED WAVE**: much faster but weaker
  monsters, packed close together.
- On Medium and Hard, bosses and fliers arrive sooner (see [Difficulty](#difficulty)).
- **Tap or click a monster** to see its name, health and kill gold.

---

## Clash mode

You against 1–3 opponents (bots, or friends online), each with your own lane.
Monsters enter at the **top** of each lane and walk to the **bottom**.

- **Your lane is the leftmost.** You can only build there, and towers only hit
  monsters in their own lane (shots stop at the brown lane dividers).
- **Send monsters:** open **Send** and buy packs to send at an opponent. Every pack
  **raises your income** for the rest of the match. Income is paid each time a wave
  is cleared.
- **Send shop levels:** start at Lv1 (Scout, Pack, Brute). Upgrade for **1,500 /
  5,000 / 15,000** gold to unlock stronger packs for **everyone** — bosses, fliers,
  and the **Wrecker**, which smashes towers and walls in its lane.
- **Leaks spill over:** a monster that gets past you moves on to the next lane.
- **Last lane standing wins.** Everyone starts with **320 gold** and 20 lives.
- After the first **Start Round**, later rounds start on the timer.
- **Bots:** choose 2–4 players and each bot's difficulty: **Easy, Medium, Hard**,
  or **Cheater** (+500 gold, +100 lives, and slowly heals back up after dropping to
  10 lives — great for long endless fights). Each bot picks a plan for the match
  (big maze, lots of damage, or a mix) and repairs its lane right away if a
  Wrecker smashes it.

---

## Online Clash with friends

Play Clash with friends on other devices — computer, phone, or browser — using a
**6-digit code**.

**To host:**
1. Pick **Clash** and any difficulty. Set the players and bots as usual.
2. Press **Invite Friends** and share the **6-digit code**.
3. Friends join; you can still add, remove or change bots in the lobby.
4. When everyone has pressed **Ready**, press **Start**.

**To join:** press **Play Online** on the main menu, type the code, then press
**Ready**.

**How it works:**
- Each friend takes a new lane. When all **4** lanes are full, a joining friend
  **replaces a bot**.
- Each round, friends press **Ready** (it's on the Start Round button), and the
  host can start once everyone is ready. The break timer still runs out on its own,
  so nobody can hold up the game.
- If a friend leaves, a **bot takes over** their lane. If the host leaves, the match
  ends for everyone.
- If you're knocked out, you can keep watching until the match ends.
- Pausing doesn't stop an online match for the others. Online matches don't go on
  the leaderboard. Everyone needs the same game version.

---

## Controls

### Computer

| Action | How |
|--------|-----|
| Place a tower | Pick it in **Towers**, then click the board |
| Place many | Hold the left button and drag |
| Select a tower | Click it (**Ctrl/Shift+click** to select several) |
| Deselect | **Right-click**, **Esc**, or **Actions → Deselect** |
| Upgrade selected | **Actions → Upgrade** or **U** |
| Inspect a monster | Click it, or hover |
| Zoom (big maps) | Mouse wheel |
| Move the view (big maps) | Hold **Space** and drag, middle/right mouse, or **Actions → Pan** |
| Pause | **Esc** or the **Pause** button |

### Phone / tablet

| Action | How |
|--------|-----|
| Place a tower | Pick it in **Towers**, then tap the board |
| Place many | Drag your finger |
| Select a tower | Tap it (shows its info card) |
| Select several | **Long-press** towers, or **Actions → Multi: On** |
| Deselect | Tap an empty spot or outside the board, or **Actions → Deselect** |
| Move the view (big maps) | **Actions → Pan**, then drag |

### The on-screen panels

Under your gold and lives is the **Controls** launcher. It opens **Towers**,
**Send** (Clash only) and **Actions** as small floating windows. Drag a window's
title bar to move it; **Pin** keeps it open; **Hide** shrinks the launcher (the
timer and Start Round stay visible).

**Pause menu:** resume, see the upcoming waves in plain words, change volume,
**copy the map seed**, save a picture of your maze, or quit to the menu (there's no
mid-game save).

---

## Leaderboard

- There's a top-10 board for **every map and difficulty** (Classic / Random /
  Siege / Clash × Easy / Medium / Hard), shared worldwide.
- When your game ends, if your wave makes the top 10, type a name (letters,
  numbers, spaces, `_` and `-`, up to 12 characters) to save it.
- A **picture of your board** is saved with your score so others can **View** how
  your maze looked. Classic / Random / Siege scores show the map seed; Clash scores
  show how many players and each bot's difficulty.
- Runs where you used the debug tools, tutorial runs, and online Clash matches
  can't be submitted.

---

## Settings

- **Large Controls**, **Effects**, **Performance mode**, **Show tower range**,
  **High contrast**, **Show enemy HP bars**, **Show grid coordinates**,
  **Screenshot watermark**
- **Master / Music / SFX** volume, plus **Mute music** / **Mute sounds**
- **Build speed** (1.0×–2.5×) — speeds up only the build and break timers, not the
  fighting
- **View Seeds** — preview Classic, Random and Siege boards from a seed
- **Achievements** — tough goals, saved on this device
- **Replay Tutorial**
- **Fullscreen**, **Install app** and **Update app** (web version)

Music starts on your first click or tap (browsers block sound before that).

---

## Tips

- A long, winding maze beats lots of towers on a short path. Walls are cheap!
- Put towers where the path passes by them **more than once**.
- Plan for **fliers** before wave 8 (sooner on Medium/Hard): Rapid, Lightning,
  Freeze and Anti-Air are your friends.
- **Cannons** shred bosses; **Spikes** hit hard but must touch the path.
- **Freeze** or **Vortex** in front of your damage towers buys them more time.
- In Randomize, mix elements so resistant monsters can't walk through.
- In Clash, sending packs early grows your income — but don't starve your own lane.

---

*Developing or building the game? See [`DEVELOPMENT.md`](DEVELOPMENT.md).
Version history is in [`CHANGELOG.md`](CHANGELOG.md).*
