# Assets — the ledger

Every third-party file the game uses or ships, and every original one that could be mistaken
for third-party. **Free sources only** (DECISIONS.md D10): CC0 first, CC-BY only if credited in
`CREDITS.md`. Never: NC or ND licences, ripped game assets, paid packs, paid AI tools or credits,
anything whose licence is unclear. Add a row **before** a file lands in `godot/`.

Columns: **Name** · **Source** (URL) · **Licence** · **Date** (added to the project) ·
**Modified?** (what we changed) · **Where** (path in the repo, or "not in git").

## Third-party

| Name | Source | Licence | Date | Modified? | Where |
|---|---|---|---|---|---|
| Universal Base Characters [Standard] (free version), by Quaternius | https://quaternius.com | CC0 1.0 (`License_Standard.txt` in the zip, checked 2026-11-13) | 2026-11-12 (downloaded by the user) | Yes, by `autobuild/figure_bake.mjs` (P1-5, 2026-11-13): eye and eyebrow meshes and all textures dropped; head projected onto an ellipsoid (no face, no ears); idle frame from the Animation Library baked into the rest pose; ×100 to centimetres; painted-clothes vertex colour added; bone nudges applied at runtime by the theme. P2-1 (2026-11-13): welded and decimated 12.6k → 5,000 triangles each (quadric half-edge collapse, skin weights kept), shading normals from a smoothed copy so the muscle relief stops catching the light, collar raised over the shoulders. The family of six (dad, mom, elder girl/boy, younger girl/boy) is drawn from these two bodies by height and bone scale in `default_theme.tres` | Zip in `autobuild/Incoming/` (gitignored, 129 MB). Derived: `godot/art/characters/figure_male.gltf/.bin`, `figure_female.gltf/.bin` |
| Wooden Table 02 (Poly Haven) | https://polyhaven.com/a/wooden_table_02 | CC0 1.0 (polyhaven.com/license) | 2026-11-13 | Yes, by `tools/import_asset.gd` (P1-6, pipeline sample): uniform ×150 to a 120 tall top (STYLE §3.1 threshold), pivot at the base, one mesh, 196 triangles, textures dropped, material renamed `wood` (theme). 170 × 120 × 106 cm. Not placed in the level yet (P3-3 decides) | `godot/art/props/wooden_table_02.glb` (+ `.source.json`). Raw download in `autobuild/Incoming/polyhaven/` (gitignored) |
| Arm Chair 01 (Poly Haven) | https://polyhaven.com/a/ArmChair_01 | CC0 1.0 (polyhaven.com/license) | 2026-11-13 | Yes, by `tools/import_asset.gd` (P1-6, pipeline sample): metres ×130 (1.3× real, STYLE §3.1), pivot at the base, decimated 5626 → 2366 triangles, textures dropped, material renamed `fabric` (theme). 110 × 139 × 100 cm. Not placed in the level yet | `godot/art/props/armchair_01.glb` (+ `.source.json`). Raw download in `autobuild/Incoming/polyhaven/` (gitignored) |
| Universal Animation Library [Standard], by Quaternius | https://quaternius.com | CC0 1.0 (`License.txt` in the zip, checked 2026-11-13) | 2026-11-12 (downloaded by the user) | One pose used so far: `Idle_Loop` frame 0, baked into the figures' rest pose by `figure_bake.mjs` (P1-5). The .glb itself is not in git. P2-2 picks the clips | Zip in `autobuild/Incoming/` (gitignored, 16 MB). Holds `UAL1_Standard.glb` and `UAL1_Standard_RM.glb` (root motion) for Godot |

**What the free character pack actually contains** (central directory read 2026-11-13): two
full bodies only, `Superhero_Male_FullBody` and `Superhero_Female_FullBody` (glTF for Godot,
FBX for Unity), their skin/eye/hair textures, and 8 hair/eyebrow/beard meshes. **It has no
"Regular" or "Teen" bodies.** Those are in the paid Source version, which D10 rules out. P2-1
builds all four family members from these two bodies (see DECISIONS.md, P1-2 row; REVIEW).
We use only the bodies. Hair, eyebrows, eyes and the skin textures are dropped per D2.

## Original (made for this project)

| Name | Source | Licence | Date | Modified? | Where |
|---|---|---|---|---|---|
| Cash bundle | Procedural, `godot/art/blender/build_cash.py` | Project's own | before autobuild | — | `godot/art/models/cash.glb` |
| Placeholder figures A/B (blocky voxel look) | Procedural, `godot/art/blender/` | Project's own | before autobuild | — | `godot/art/models/character_a.glb`, `character_b.glb`. Replaced by the P2-1 family; still the fallback when the theme's figures are missing |
| Sky, ground, lighting, blockout | Code (`world_backdrop.gd`, `greybox_main.gd`) | Project's own | 2026-11-12 | — | No asset files |
| ArtTheme (figure, cash, house and floor materials; sky, sun, fills, ambient, tonemap, room lamps) | `godot/game/art/art_theme.gd` + data in `godot/art/theme/default_theme.tres` | Project's own | 2026-11-13 | — | Plain StandardMaterial3D values, no textures. Every imported mesh is re-materialed from it (P1-4) |

## Code that is not ours

| Name | Source | Licence | Date | Note |
|---|---|---|---|---|
| Godot MCP editor plugin (`godot/addons/godot_mcp`, "by mkdevkit", v0.1.0) | Unknown. No URL or licence file in the repo | **Not recorded** | before autobuild | A dev tool. Its three runtime bridges are autoloads in `project.godot`, so they would ship in an export. Before P7-1, remove the plugin and autoloads from the release build, or record its licence. Not used by the autobuild (no MCP in unattended runs) |
| Godot Engine 4.7.1 | https://godotengine.org | MIT | — | Its licence text must go in the credits/about screen (P7-3) |

## Not used, on purpose

- Quaternius **Source** (paid) editions: D10, no money.
- Any asset whose only source is another game.
