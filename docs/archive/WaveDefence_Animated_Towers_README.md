# WaveDefence tower sprite pack – Godot 4

Copy `assets/sprites/towers/` into your Godot project. Every tower has a transparent `tower_NAME.png` 40×40 idle frame; a `tower_NAME_sheet.png` 160×80 (4 columns, 2 rows of 40×40), row 0 idle, row 1 shoot/cast/trigger; plus `tower_NAME_vfx_sheet.png` same layout with isolated effect layers; `tower_NAME_frames.json` and corresponding animated GIF previews.

The idle and combat effect animations are *prototypes*. Actual firing should be synchronized to the existing projectile/tower attack callbacks, not played endlessly. Keep existing gameplay and stats unchanged. Nearest texture filter recommended in Godot to preserve crisp pixels; center sprites at (20,20).

Wall: `tower_wall_autotile_16.png` is a 4×4 atlas of 40px neighbor masks. N=1, E=2, S=4, W=8. Compute mask for each wall cell and choose index `% 4` column and `// 4` row. Recompute on placement/deletion; a combat tower placed atop a wall should not remove that wall's visual connection. The wall itself doesn't shoot; `placement.gif` is cosmetic only.

Vortex: `tower_vortex_3x3_sheet.png` is 480×240, with four 120×120 frames per row (idle / activate). Center artwork on the 3×3 block; `tower_vortex.png` remains its 40×40 shop icon. The 3×3 zone should not be interpreted as collision/hitbox art – keep existing build rules.

Extra: elemental 16×16 and Command ability 16×16 icons are included.

To rebuild the *exact derived animations* from included sources, run `python tools/build_towers.py` after `pip install pillow`. Source images are in `tools/references/` and processed base poses in `tools/base_art/`. The builder does not overwrite existing game code.

QA: `VALIDATION.json` reports actual sheet dimensions, opaque color counts, binary alpha, and nonempty cells. This is graphical asset validation only; Godot runtime integration has not been tested.

## Godot helper

`tools/tower_sprite_loader.gd` constructs a `SpriteFrames` resource from each atlas. Move it into your Godot project; use `$AnimatedSprite2D.sprite_frames = WaveTowerSprites.make_frames("gunner")`. On a shot, `$AnimatedSprite2D.play("action")`; on completion, return to `idle`. For 3×3 Vortex, call `make_frames("vortex", true)` on a node centered across the locked 3×3 zone. For the continuous wall, call `WaveTowerSprites.wall_tile(mask)` and set a Sprite2D texture, updating it when neighbors change. Avoid overlaying the VFX atlas on the *already composited* main animation sheet; use VFX with the still base pose if separately layered.
