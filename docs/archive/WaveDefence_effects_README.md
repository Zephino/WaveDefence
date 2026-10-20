# WaveDefence attack effects

Sheets live in `res://assets/sprites/effects/`. Each sheet is **one row** of equal frames, no padding.
`effects_manifest.json` lists frame size, frame count, fps, loop and pivot for every effect.

| Effect | Frame | Frames | Loop | Used by | What it is |
|---|---|---|---|---|---|
| fx_tracer | 16×16 | 4 | yes | gunner, rapid, gatling | bullet, faces right |
| fx_flak_shell | 16×16 | 4 | yes | antiair | flak round, faces right |
| fx_cannon_shell | 16×16 | 4 | yes | cannon | shell with fire trail, faces right |
| fx_fireball | 24×24 | 4 | yes | burn | fireball, faces right |
| fx_ice_shard | 24×24 | 4 | yes | freeze | spinning snowflake; sparkle trail on the left |
| fx_poison_glob | 24×24 | 4 | yes | poison | toxic blob, faces right |
| fx_lightning_bolt | 64×16 | 4 | yes | lightning | **tiling** gold bolt segment; repeat along each chain hop |
| fx_muzzle_flash | 20×20 | 4 | no | gunner, rapid, gatling, cannon, antiair | pivot (5,10) sits on the muzzle, faces right |
| fx_hit_spark | 24×24 | 5 | no | gunner, rapid, gatling | impact |
| fx_explosion | 48×48 | 7 | no | cannon | splash; scale to `splash_radius` (40 px = full frame) |
| fx_fire_burst | 32×32 | 6 | no | burn | impact |
| fx_frost_burst | 32×32 | 6 | no | freeze | impact |
| fx_poison_cloud | 40×40 | 6 | no | poison | splash cloud (matches 40 px splash) |
| fx_lightning_spark | 24×24 | 5 | no | lightning | impact at each chain hop |
| fx_flak_burst | 32×32 | 6 | no | antiair | air burst |
| fx_spike_burst | 32×32 | 5 | no | spike | melee strike; pivot (16,22) is ground level |

## Rules
- Pixel art: use **Nearest** texture filtering. Alpha uses only 0 / 96 / 176 / 255 (solid glow bands; translucency only for fading smoke).
- Directional projectiles are authored facing **right (+x)** — set `rotation = direction.angle()`.
- Built for 40 px tiles. In Large Controls (30 px) scale by `tile_px / 40`.
- Effects are cosmetic only. Gameplay (damage, splash, chains, slows, DoT) stays in `projectile.gd` / `tower.gd`.
- Lightning stays **yellow/gold**; Freeze stays blue/cyan; Poison green; Burn orange/red.

## Rebuild / validate
```
pip install pillow
python tools/effects/build_effects.py assets/sprites/effects      # regenerate all sheets
python tools/effects/validate_effects.py assets/sprites/effects   # size, frames, alpha, clipping checks
python tools/effects/preview.py 5                                 # contact sheet -> contact.png
```
To change an effect's look, edit its function in `build_effects.py`; to change speed, edit the fps in the `EFFECTS` table.
