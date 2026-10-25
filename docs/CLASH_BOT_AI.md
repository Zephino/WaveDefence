# Clash bot AI

## Placement rules (no more walled-off lanes)
Every bot placement goes through `ClashBotAI._place_owned()`, which applies the same rules as a
human (`BuildSystem.can_place_at`): own lane only, not on spawn/exit, buildable, and never sealing
the lane's spawn→exit path. The pathfinder is rebuilt after each piece so the next check sees the
real board. Refused placements refund the gold. After a mid-wave repair, `main.gd` also runs the
same unblock failsafe used between rounds.

Previously, template mazes skipped the path check and mid-wave repairs had none at all. A lane sealed
mid-wave made every ground send to that bot fail to spawn (and be deleted), so the bot took no damage.

## Difficulty levels
| Level | Plan | Tower choice | Placement | Upgrades |
|---|---|---|---|---|
| Easy | any (incl. towers-only) | uniform random | first legal spot, 30% random open cell; half-built templates | rare |
| Medium | mostly maze/hybrid | value-weighted, 50% random | random among top 6 spots by path coverage | sometimes |
| Hard | always maze/hybrid | chooses tower **and** spot together: most damage on the path per gold | best spot; also swaps walls→towers by the same rule; extra walls to stretch the corridor | only when better value than a new tower, then spends leftovers |
| Cheater | Hard brain | same as Hard | same as Hard | same as Hard, plus +500 gold, +100 lives, healing |

All levels obey the placement rules.

## Learning (`ClashBotMemory`, saved in `user://clash_bot_memory.cfg`)
After each wave a bot scores that wave (0..1): half for path length, half for few leaks.
- **Maze styles** are a bandit: Easy ignores memory, Medium uses the best style 70% of the time,
  Hard/Cheater use UCB1 (try every style, then mostly use what works while re-testing occasionally).
- **Tower types** keep a running reward; Medium+ buy towers that coincided with fewer leaks.
- **In-match**: leaked fliers raise "air threat" → more air-capable towers; leaked ground mobs raise
  "ground threat" → more maze-stretching walls.

## Tests
```
godot --headless --path . -s res://scripts/clash_bot_seal_test.gd   # expect 0 sealed
godot --headless --path . -s res://scripts/clash_bot_eval.gd        # expect BOT_EVAL OK
```
`clash_bot_eval.gd` gives each difficulty the same maze style per trial and compares path coverage
(damage × path cells covered). It also checks learning and flier adaptation. It takes a few minutes.
