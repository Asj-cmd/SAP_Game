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
| Furniture Kit (1.0), by Kenney (140 models) | https://kenney.nl/assets/furniture-kit | CC0 1.0 (page and `License.txt` in the zip, checked 2026-11-13); zip sha256 `e67652d0932cee41683f74711c03d3e192a2af9979ef8e6b237711f5482d46b0` | 2026-11-13 | P3-1 kit pick (house furniture and appliances). Each piece goes through `tools/import_asset.gd`: ×260 (the pack is about half real size, ×2.6 = the house's 1.3× furniture scale, STYLE §3.1) or `--height=` to a threshold, pivot at the base, one mesh, Kenney's own colours dropped and its material names mapped to the theme's (`wood`, `painted`, `fabric`, `steel`). Trial set from P3-1: kitchen counter, fridge, table, chair, washer, double bed, wardrobe (bookcase with doors), sofa | `autobuild/fetch_kenney.mjs furniture-kit` → `autobuild/Incoming/kenney/furniture-kit/` (gitignored). Derived: `godot/art/props/kenney/*.glb` (+ `.source.json`) |
| Universal Animation Library [Standard], by Quaternius | https://quaternius.com | CC0 1.0 (`License.txt` in the zip, checked 2026-11-13) | 2026-11-12 (downloaded by the user) | `Idle_Loop` frame 0 is baked into the figures' rest pose by `figure_bake.mjs` (P1-5). P2-2 (2026-11-13): `tools/build_figure_anims.gd` resamples Idle_Loop, Walk_Formal_Loop, Walk_Loop, Jog_Fwd_Loop, Sprint_Loop, Crouch_Idle_Loop, Crouch_Fwd_Loop, Jump_Start, Jump_Land, PickUp_Table and Interact onto the figure rig at 30 fps: rotation tracks for 22 body bones (no fingers, no scale tracks), the pelvis as a change from idle scaled ×1.07 to the bodies' legs, jumps trimmed and never lifting the pelvis, the crouch's and jump's arms replaced by stiff hanging arms. New arm poses (cash overhead, panic arms up, the throw's push) are made by IK, not taken from the library. Stride speeds measured from `UAL1_Standard_RM.glb`. The .glb files are not in git | Zip in `autobuild/Incoming/` (gitignored, 16 MB). Derived: `godot/art/characters/figure_anims.res` (24 clips, 348 KB) + `figure_anims.json` (lengths, stride speeds) |
| Brick Wall 001 texture (Poly Haven), 3 × 3 m | https://polyhaven.com/a/brick_wall_001 | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse map only, 1k JPG, md5-checked by `autobuild/fetch_texture.mjs`. Not used in the level yet (P3-2) | `godot/art/textures/brick_wall_001/` (+ `SOURCE.txt`) |
| Concrete Block Wall texture (Poly Haven), 2 × 2 m | https://polyhaven.com/a/concrete_block_wall | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used yet (P3-2) | `godot/art/textures/concrete_block_wall/` (+ `SOURCE.txt`) |
| Concrete Floor Painted texture (Poly Haven), 2 × 2 m | https://polyhaven.com/a/concrete_floor_painted | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used yet (P3-2) | `godot/art/textures/concrete_floor_painted/` (+ `SOURCE.txt`) |
| Floor Tiles 06 texture (Poly Haven), 3 × 3 m | https://polyhaven.com/a/floor_tiles_06 | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used yet (P3-2) | `godot/art/textures/floor_tiles_06/` (+ `SOURCE.txt`) |
| Grey Roof Tiles texture (Poly Haven), 3 × 3 m | https://polyhaven.com/a/grey_roof_tiles | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used yet (P3-2) | `godot/art/textures/grey_roof_tiles/` (+ `SOURCE.txt`) |
| Interior Tiles texture (Poly Haven), 1.9 × 1.9 m | https://polyhaven.com/a/interior_tiles | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used yet (P3-2) | `godot/art/textures/interior_tiles/` (+ `SOURCE.txt`) |
| Laminate Floor 02 texture (Poly Haven), 1.7 × 1.7 m | https://polyhaven.com/a/laminate_floor_02 | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used yet (P3-2) | `godot/art/textures/laminate_floor_02/` (+ `SOURCE.txt`) |
| Painted Plaster Wall texture (Poly Haven), 2 × 2 m | https://polyhaven.com/a/painted_plaster_wall | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used yet (P3-2) | `godot/art/textures/painted_plaster_wall/` (+ `SOURCE.txt`) |
| Animated low poly men (Quaternius, 2019 pack: Male_Casual / LongSleeve / Shirt / Suit, flat and Smooth_ variants) | https://quaternius.com | CC0 1.0 (`License.txt` in the zip, checked 2026-11-14) | 2026-11-13 (downloaded by the user) | P2-1b pick (REVIEW). `Male_LongSleeve.fbx` re-rigged onto the figure skeleton by `tools/rerig_character.gd`: posed into the rig's rest stance, weights rebound to the rig's bone names, painted (bare / shirt / trousers / shoes by weight), head projected onto an ellipsoid with the ellipsoid's own normals, inside-out triangles dropped, smoothed normals. 1,894 triangles. Not yet drawn in play (the theme still points at `figure_male.gltf`) | Zip in `autobuild/Incoming/` (gitignored, 18 MB). Derived: `godot/art/characters/figure_lp_male.gltf` + `figure_lp_male0.bin` |
| Animated low poly women (Quaternius, 2019 pack: Female_Alternative / Casual / Dress / TankTop, flat and Smooth_) | https://quaternius.com | CC0 1.0 (`License.txt`, checked 2026-11-14) | 2026-11-13 (downloaded by the user) | P2-1b pick (REVIEW). `Female_Casual.fbx` through the same tool onto `figure_female.gltf`'s skeleton; hair strands dropped (the scalp `HairBase` kept). 1,596 triangles. Not yet drawn in play | Zip in `autobuild/Incoming/` (gitignored, 8 MB). Derived: `godot/art/characters/figure_lp_female.gltf` + `figure_lp_female0.bin` |
| Ultimate Modular Men / Women (Quaternius, "Individual Characters" glTF) | https://quaternius.com | CC0 1.0 (`License.txt` in each zip, checked 2026-11-14; the women's file is headed "Ultimate Modular Males" but is the same CC0 text) | 2026-11-13 (downloaded by the user) | Evaluated in P2-1b, **not used** (see "Not used, on purpose") | Zips in `autobuild/Incoming/` (gitignored, 54 + 46 MB) |

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

## Chosen sources, nothing downloaded yet (P3-1)

Each file still gets its own row above when it lands in `godot/`.

| Source | Licence | For | Checked |
|---|---|---|---|
| Poly Haven textures, https://polyhaven.com/textures (API `api.polyhaven.com`) | CC0 1.0 (polyhaven.com/license) | Wall, floor, ceiling, tile, concrete, brick, roof surfaces (shortlist in STYLE §3.3) | 2026-11-13: API reachable from node, 700+ textures listed |
| ambientCG, https://ambientcg.com (API `ambientcg.com/api/v2/full_json`) | CC0 1.0 (ambientcg.com/license) | Carpet, wallpaper, upholstery, which Poly Haven lacks | 2026-11-13: 16 carpets, 6 wallpapers, ~100 fabrics; licence page says CC0 |

## Not used, on purpose

- Quaternius **Source** (paid) editions: D10, no money.
- Any asset whose only source is another game.
- P3-1: **Poly Haven furniture** for the house. Almost all of it is antique or gothic, it has no
  kitchen units, fridge, washer, modern bed or wardrobe, and it runs 5–60k triangles. The two
  samples in `godot/art/props/` stay as pipeline examples and are not placed.
- P2-1b: **Quaternius Ultimate Modular Men/Women**. CC0, but the bodies are sculpted (biceps,
  hips, chest), most outfits are costumes (knight, astronaut, witch, SWAT), the casual ones are
  4.5–5.8k triangles, and the rig is its own (Root/Hips/Abdomen…, IK feet), so they buy nothing
  over the low-poly pack, which is plainer and half the triangles.
- P1-5/P2-1 bodies (Universal Base Characters "Superhero") are replaced by the low-poly bodies once
  P2-1b is finished; the pack stays recorded above because the rig and the animation set come from it.
- P3-1: **KayKit Furniture Bits**. Toy-chunky proportions fail STYLE §3.3.
- P3-1: **Quaternius Ultimate House Interior**. CC0, but rounded and stylised, FBX/OBJ/Blend only,
  and only on Google Drive (no repeatable fetch). One coherent pack (Kenney) beats two.
- P3-1: **Kenney Furniture Kit's** modular `wall*`, `doorway*`, `floor*`, `stairs*` and `paneling`
  pieces. They are half-real tiles that do not fit the blockout. The shell is generated (P3-2).
