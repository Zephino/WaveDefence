# Tower sprites — replacement guide

Tower visuals are **data-driven**. Gameplay (damage, range, fire rate, walls, Vortex rules) does **not** read pixel art. You can swap placeholder art for Claude’s final pack by replacing files only.

## Where assets live

| Path | Purpose |
|------|---------|
| `assets/sprites/towers/` | Live sheets, `*_frames.json`, icons, wall autotile |
| `docs/archive/WaveDefence_Animated_Towers_COMPLETE.zip` | Original pack backup |
| `scripts/tower_sprites.gd` | Loader / metadata / validation |

Stable filenames (do not rename):

- `tower_<id>_sheet.png` — 160×80, 4×2 of 40×40 (row 0 idle, row 1 action/shoot/activate/signal)
- `tower_<id>_frames.json` — frame size, rows, FPS, animation names
- `tower_<id>.png` — 40×40 shop / still icon
- `tower_wall_autotile_16.png` — 160×160, 16 fortress tiles (N=1, E=2, S=4, W=8)
- `tower_vortex_3x3_sheet.png` — 480×240, 4×2 of 120×120 (idle / activate)
- `icon_element_*.png`, `icon_command_*.png` — 16×16 UI icons

`<id>` is one of: `wall`, `gunner`, `rapid`, `cannon`, `burn`, `freeze`, `poison`, `lightning`, `spike`, `antiair`, `gatling`, `vortex`, `command`.

## How to replace art later

1. Export Claude’s sheets with the **same filenames**, **same pixel sizes**, and **same row layout** as above.
2. Overwrite the files under `assets/sprites/towers/` (keep the matching `*_frames.json` unless FPS/rows change — if they change, edit JSON only).
3. Open the project once in Godot **or** run a web/desktop export so Godot reimports PNGs (creates/updates `*.import`).
4. Validate:

```powershell
godot --headless --path . -s res://scripts/tower_sprite_validate.gd
```

Expect `TOWER_SPRITE_VALIDATE_OK`. If a sheet is the wrong size or missing an idle/action row, the tool prints the mismatch.

5. No GDScript changes are required when dimensions and layout match.

### Godot reimport notes

- Project already uses nearest-neighbor canvas filtering (`textures/canvas_textures/default_texture_filter=0`) for crisp pixels.
- After replacing a PNG, if the editor is open: select the texture → **Reimport**, or delete the stale `.import` and reopen.
- Headless export (`export_builds.ps1`) also triggers import.

## Animation events (visual only)

| Tower | Idle | Action trigger |
|-------|------|----------------|
| Combat towers | looping row 0 | each shot (`_fire_at`) |
| Vortex | 120×120 idle | when an enemy is pulled into orbit |
| Command | idle | when an ability is successfully cast |
| Wall | 16-tile autotile | brief `placement` anim on build; neighbors refresh on place/remove |

Attack math and projectiles are unchanged; animations never gate damage.

## Wall fortress bitmask

`index = (N?1:0) | (E?2:0) | (S?4:0) | (W?8:0)`  
Tile rect: `(index % 4) * 40`, `(index // 4) * 40`, `40×40`.  
Any adjacent **structure** (wall or combat tower) counts as a neighbor so maze links stay connected when towers sit on the fortress line.

## Vortex

In-world art uses `tower_vortex_3x3_sheet.png` (120×120 frames). Shop icon stays `tower_vortex.png` (40×40). Build footprint / path rules are unchanged — the large art is centered on the anchor cell only.
