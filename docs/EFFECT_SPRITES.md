# Attack effect sprites — replacement guide

Sheets live in `assets/sprites/effects/`. Metadata is `effects_manifest.json` (frame size, count, fps, loop, pivot).

Cosmetic only — damage, splash, chains, slows, and DoT stay in `projectile.gd` / `tower.gd`.

## Mapping

| Sheet | Role | Towers |
|-------|------|--------|
| `fx_tracer` | projectile | gunner, rapid, gatling |
| `fx_flak_shell` | projectile | antiair |
| `fx_cannon_shell` | projectile | cannon |
| `fx_fireball` | projectile | burn |
| `fx_ice_shard` | projectile | freeze |
| `fx_poison_glob` | projectile | poison |
| `fx_lightning_bolt` | tiled chain segment | lightning |
| `fx_muzzle_flash` | muzzle | gunner, rapid, gatling, cannon, antiair |
| `fx_hit_spark` | impact | gunner, rapid, gatling |
| `fx_explosion` | splash impact | cannon |
| `fx_fire_burst` | impact | burn |
| `fx_frost_burst` | impact | freeze |
| `fx_poison_cloud` | splash impact | poison |
| `fx_lightning_spark` | chain hop impact | lightning |
| `fx_flak_burst` | impact | antiair |
| `fx_spike_burst` | melee impact | spike |

Directional shots face **right (+x)** in the sheet; the game rotates by travel angle.

## Replace later

1. Overwrite PNGs with the same names and layout (one row of equal frames).
2. Update `effects_manifest.json` if frame count / size / fps / pivot change.
3. Reimport in Godot or run an export.
4. Optional check: extend smoke / call `EffectSprites.validate_assets()`.

Backup ZIP: `docs/archive/WaveDefence_effects.zip`
