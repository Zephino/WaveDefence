# Web build (GitHub Pages)

Godot HTML5 export output. Enable Pages on the repo:

**Settings → Pages → Deploy from a branch → `main` / `/docs`**

Play URL (after first deploy):

`https://zephino.github.io/WaveDefence/`

Rebuild:

```powershell
.\export_builds.ps1 -WebOnly
```

Wait for the game to finish loading, then click or tap once — browsers start music on that first gesture. Click the game canvas once if input seems stuck (browser focus).
