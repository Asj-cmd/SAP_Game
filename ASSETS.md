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
| Furniture Kit (1.0), by Kenney (140 models) | https://kenney.nl/assets/furniture-kit | CC0 1.0 (page and `License.txt` in the zip, checked 2026-11-13); zip sha256 `e67652d0932cee41683f74711c03d3e192a2af9979ef8e6b237711f5482d46b0` | 2026-11-13 | P3-1 kit pick (house furniture and appliances). Each piece goes through `tools/import_asset.gd`: ×260 (the pack is about half real size, ×2.6 = the house's 1.3× furniture scale, STYLE §3.1) or `--height=` to a threshold, pivot at the base, one mesh, Kenney's own colours dropped and its material names mapped to the theme's (`wood`, `painted`, `fabric`, `steel`). Trial set from P3-1: kitchen counter, fridge, table, chair, washer, double bed, wardrobe (bookcase with doors), sofa. **P3-3 (2026-11-14) adds**, all ×260 except the screen (×180): `kitchenCabinet` → kitchen_counter (re-imported, worktop mapped), `kitchenCabinetDrawer` → kitchen_drawers, `kitchenSink`, `kitchenStove`, `dryer`, `sideTableDrawers` → console, `cabinetTelevisionDoors` → sideboard (also the bedroom dresser), `bookcaseClosed` → bookcase, `bookcaseOpen` → shelf_open, `desk`, `coatRackStanding` → coat_stand, `coatRack` (wall), `rugRectangle` → rug, `rugDoormat` → doormat, `computerScreen` → screen, `kitchenMicrowave`, `toaster`, `lampSquareTable` → table_lamp, `plantSmall1` → plant_small; new theme names `worktop`, `enamel`, `rug`, `rug_border`, `screen`, `lampshade`, `plant`. In game each blocking piece is scaled per axis to its collision box (FurnitureDresser). The chair and sofa are imported but placed nowhere (no seating until a seat can sit at a threshold) | `autobuild/fetch_kenney.mjs furniture-kit` → `autobuild/Incoming/kenney/furniture-kit/` (gitignored). Derived: `godot/art/props/kenney/*.glb` (+ `.source.json`) |
| Universal Animation Library [Standard], by Quaternius | https://quaternius.com | CC0 1.0 (`License.txt` in the zip, checked 2026-11-13) | 2026-11-12 (downloaded by the user) | `Idle_Loop` frame 0 is baked into the figures' rest pose by `figure_bake.mjs` (P1-5). P2-2 (2026-11-13): `tools/build_figure_anims.gd` resamples Idle_Loop, Walk_Formal_Loop, Walk_Loop, Jog_Fwd_Loop, Sprint_Loop, Crouch_Idle_Loop, Crouch_Fwd_Loop, Jump_Start, Jump_Land, PickUp_Table and Interact onto the figure rig at 30 fps: rotation tracks for 22 body bones (no fingers, no scale tracks), the pelvis as a change from idle scaled ×1.07 to the bodies' legs, jumps trimmed and never lifting the pelvis, the crouch's and jump's arms replaced by stiff hanging arms. New arm poses (cash overhead, panic arms up, the throw's push) are made by IK, not taken from the library. Stride speeds measured from `UAL1_Standard_RM.glb`. The .glb files are not in git | Zip in `autobuild/Incoming/` (gitignored, 16 MB). Derived: `godot/art/characters/figure_anims.res` (24 clips, 348 KB) + `figure_anims.json` (lengths, stride speeds) |
| Brick Wall 001 texture (Poly Haven), 3 × 3 m | https://polyhaven.com/a/brick_wall_001 | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse map only, 1k JPG, md5-checked by `autobuild/fetch_texture.mjs`. Used: outside walls of both houses (theme `wall_brick`, tinted, world UVs at 3 m) until P3-4, which replaced it with the softened copy below (generated from this file). Imported VRAM-compressed with mipmaps (P3-2) | `godot/art/textures/brick_wall_001/` (+ `SOURCE.txt`) |
| Concrete Block Wall texture (Poly Haven), 2 × 2 m | https://polyhaven.com/a/concrete_block_wall | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Used: jail walls (theme `wall_block`, brightened). Imported VRAM-compressed with mipmaps (P3-2) | `godot/art/textures/concrete_block_wall/` (+ `SOURCE.txt`) |
| Concrete Floor Painted texture (Poly Haven), 2 × 2 m | https://polyhaven.com/a/concrete_floor_painted | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used: tried as the jail floor in P3-2, read as dark mud at 2 m; the jail floor is flat painted concrete. Imported VRAM-compressed with mipmaps (P3-2) | `godot/art/textures/concrete_floor_painted/` (+ `SOURCE.txt`) |
| Floor Tiles 06 texture (Poly Haven), 3 × 3 m | https://polyhaven.com/a/floor_tiles_06 | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Not used yet (kitchen alternative). Imported VRAM-compressed with mipmaps (P3-2) | `godot/art/textures/floor_tiles_06/` (+ `SOURCE.txt`) |
| Grey Roof Tiles texture (Poly Haven), 3 × 3 m | https://polyhaven.com/a/grey_roof_tiles | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Used: the hipped roofs (theme `roof_tile`, tinted cooler). Imported VRAM-compressed with mipmaps (P3-2) | `godot/art/textures/grey_roof_tiles/` (+ `SOURCE.txt`) |
| Interior Tiles texture (Poly Haven), 1.9 × 1.9 m | https://polyhaven.com/a/interior_tiles | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Used: kitchen floor (theme `floor_tile`). Imported VRAM-compressed with mipmaps (P3-2) | `godot/art/textures/interior_tiles/` (+ `SOURCE.txt`) |
| Laminate Floor 02 texture (Poly Haven), 1.7 × 1.7 m | https://polyhaven.com/a/laminate_floor_02 | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Used: hall floors and stair treads (theme `floor_oak`). Imported VRAM-compressed with mipmaps (P3-2) | `godot/art/textures/laminate_floor_02/` (+ `SOURCE.txt`) |
| Painted Plaster Wall texture (Poly Haven), 2 × 2 m | https://polyhaven.com/a/painted_plaster_wall | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-14 | No. Diffuse 1k JPG, md5-checked. Used: every interior wall but the jail (theme `wall_plaster`). Imported VRAM-compressed with mipmaps (P3-2) | `godot/art/textures/painted_plaster_wall/` (+ `SOURCE.txt`) |
| Asphalt 02 texture (Poly Haven), 3 × 3 m | https://polyhaven.com/a/asphalt_02 | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-15 | No. Diffuse 1k JPG, md5-checked by `autobuild/fetch_texture.mjs`. Used: the two streets (theme `exterior_materials.asphalt`, P3-4) | `godot/art/textures/asphalt_02/` (+ `SOURCE.txt`) |
| Bark Brown 02 texture (Poly Haven), 1 × 1 m | https://polyhaven.com/a/bark_brown_02 | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-15 | No. Diffuse 1k JPG, md5-checked. Used: tree trunks (`bark`, P3-4) | `godot/art/textures/bark_brown_02/` (+ `SOURCE.txt`) |
| Concrete Pavement texture (Poly Haven), 1.8 × 1.8 m | https://polyhaven.com/a/concrete_pavement | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-15 | No. Diffuse 1k JPG, md5-checked. Used: pavements and paths (`pavement`, P3-4) | `godot/art/textures/concrete_pavement/` (+ `SOURCE.txt`) |
| Gravel Floor texture (Poly Haven), 2.25 × 2.25 m | https://polyhaven.com/a/gravel_floor | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-15 | No. Diffuse 1k JPG, md5-checked. Used: the neutral ground outside both yards (`gravel`, P3-4) | `godot/art/textures/gravel_floor/` (+ `SOURCE.txt`) |
| Weathered Brown Planks texture (Poly Haven), 1.8 × 1.8 m | https://polyhaven.com/a/weathered_brown_planks | CC0 1.0 (polyhaven.com/license; `SOURCE.txt`) | 2026-11-15 | No. Diffuse 1k JPG, md5-checked. Used: the timber fences (`fence_wood`, `fence_post`, P3-4) | `godot/art/textures/weathered_brown_planks/` (+ `SOURCE.txt`) |
| Animated low poly men (Quaternius, 2019 pack: Male_Casual / LongSleeve / Shirt / Suit, flat and Smooth_ variants) | https://quaternius.com | CC0 1.0 (`License.txt` in the zip, checked 2026-11-14) | 2026-11-13 (downloaded by the user) | P2-1b pick (REVIEW). `Male_LongSleeve.fbx` re-rigged onto the figure skeleton by `tools/rerig_character.gd`: posed into the rig's rest stance, weights rebound to the rig's bone names, painted (bare / shirt / trousers / shoes by weight), head projected onto an ellipsoid (from the chin up) with the ellipsoid's own normals, egged points weighted to the Head bone, one subdivision level on the egg, inside-out triangles dropped, smoothed normals. 3,987 triangles. Drawn in play as dad and the boys since P2-1b | Zip in `autobuild/Incoming/` (gitignored, 18 MB). Derived: `godot/art/characters/figure_lp_male.gltf` + `figure_lp_male0.bin` (elder boy since 2026-11-15). Also, same tool, 2026-11-15 (P2-1b second pass): `Male_Shirt.fbx` → `figure_lp_shirt` (dad, 3,755 triangles), `Male_Casual.fbx` → `figure_lp_casual` (younger boy, 3,695); a second top colour is painted as its own `trim` region |
| Animated low poly women (Quaternius, 2019 pack: Female_Alternative / Casual / Dress / TankTop, flat and Smooth_) | https://quaternius.com | CC0 1.0 (`License.txt`, checked 2026-11-14) | 2026-11-13 (downloaded by the user) | P2-1b pick (REVIEW). `Female_Casual.fbx` through the same tool onto `figure_female.gltf`'s skeleton; hair strands dropped (the scalp `HairBase` kept), same head treatment. 3,027 triangles. Drawn in play as mom and the girls since P2-1b | Zip in `autobuild/Incoming/` (gitignored, 8 MB). Derived: `godot/art/characters/figure_lp_female.gltf` + `figure_lp_female0.bin` (a spare since 2026-11-15, drawn by no member). Also, same tool, 2026-11-15: `Female_Dress.fbx` → `figure_lp_dress` (mom, 3,503 triangles; head egg depth capped at 1.27 × width because of her bun), `Female_Alternative.fbx` → `figure_lp_alt` (elder girl, 3,284), `Female_TankTop.fbx` → `figure_lp_tank` (younger girl, 2,991) |
| Hair shapes and dad's belly on the six family bodies (P2-6) | Our own: generated by `godot/tools/rerig_character.gd` (`--hair=`, `--belly=`), options per body in `autobuild/rerig_family.mjs` | Ours (no third-party asset; the packs' own hair meshes stay dropped) | 2026-11-17 | Plain closed shapes placed from the head ellipsoid, painted as a `hair` region, rigid on the Head bone: 64 to 340 triangles a figure. Bodies with hair: shirt 3,992, dress 3,805, alt 3,624, male 4,051, tank 3,331, casual 3,764 triangles (these replace the counts in the two rows above). *PT2-8 (2026-11-18): bigger mohawks (16 / 13 cm), a 34 cm beehive, uneven two-blob pigtails; now 64 to 468 triangles of hair; dress 3,919, alt 3,752, male 4,051, tank 3,459, casual 3,764 (shirt unchanged)* | Inside `godot/art/characters/figure_lp_{shirt,dress,alt,male,tank,casual}.gltf` + `0.bin` |
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
| Lawn and foliage textures (generated, 1024 px seamless tiles) | Procedural: `godot/tools/make_outdoor_textures.gd` (`node autobuild/run_tool.mjs make_outdoor_textures`), fixed seeds | Project's own | 2026-11-15 | — | `godot/art/textures/generated/lawn_diff.png`, `foliage_diff.png`. Made because Poly Haven's grasses are all meadow, mud or leaf litter (P3-4). Since P3-4's finish, imported VRAM-compressed with mipmaps like the house textures |
| Soft brick texture (derived from Brick Wall 001, 1024 px JPG) | Derived from https://polyhaven.com/a/brick_wall_001 by `godot/tools/make_outdoor_textures.gd` | CC0 1.0 (source's licence) | 2026-11-15 | **Yes**: contrast cut to 0.55 about the image mean, mean pulled 35 % toward STYLE §3.3 brick `(0.55, 0.33, 0.25)` | `godot/art/textures/generated/brick_soft_diff.jpg`. Used: theme `wall_brick` (outside walls, neighbours, railings' plinths and piers), tile 145 cm. The source stays in the repo as the input |
| Exterior (fences, railings, two short dead-end streets, enclosing hedges, tree belts) | Code: `godot/game/art/exterior_builder.gd`, `fence_cutaway.gdshader`; materials in the theme | Project's own | 2026-11-15 | 2026-11-17 (P3-7): the neighbours' houses are gone; tall hedges and tree belts enclose the lot. No new texture (the hedge uses the existing foliage) | No model files. Presentation only, no collision (P3-4) |

## Code that is not ours

| Name | Source | Licence | Date | Note |
|---|---|---|---|---|
| Godot MCP editor plugin (`godot/addons/godot_mcp`, "by mkdevkit", v0.1.0) | Unknown. No URL or licence file in the repo | **Not recorded** | before autobuild | A dev tool. Its three runtime bridges are autoloads in `project.godot`, so they would ship in an export. Before P7-1, remove the plugin and autoloads from the release build, or record its licence. Not used by the autobuild (no MCP in unattended runs) | **P7-1 done:** the three autoloads are removed from `project.godot` and `addons/*` is in the export preset's `exclude_filter`; `autobuild/build.mjs` refuses to build if they come back. Not in the export.
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

## Audio (P5-3) - Kenney, CC0 1.0, fetched 2026-11-17, unmodified .ogg, only the used files copied to godot/art/audio/sfx/
Packs: impact-sounds (https://kenney.nl/assets/impact-sounds), interface-sounds (https://kenney.nl/assets/interface-sounds), rpg-audio (https://kenney.nl/assets/rpg-audio). Zip hashes in autobuild/Incoming/kenney/<slug>/SOURCE.txt (gitignored).

| File | From | Event |
|---|---|---|
| step_wood_1-3 | impact-sounds footstep_wood_000-002 | footsteps |
| grab_1, grab_2 | rpg-audio bookFlip2, bookFlip3 (PT3-2: a paper flutter, 0.43 s / 0.23 s; sha256 3409042a…f73c, c85db5dc…67be) | grab |
| `retired/grab_1`, `retired/grab_2` | rpg-audio cloth1, cloth2 | **Retired, not shipped** (PT3-2) |
| throw | rpg-audio cloth3 | throw |
| seize_thump, seize_cloth | impact-sounds impactSoft_heavy_000; rpg-audio cloth4 | caught |
| free | rpg-audio metalLatch | free an ally |
| land | impact-sounds impactSoft_medium_000 | landing |
| cash_1, cash_2 | rpg-audio bookPlace1, bookPlace2 (PT3-2: a soft paper-bundle thud, 0.28 s / 0.35 s; 26f3ce60…d977, 831874e8…731e) | deposit |
| drop | rpg-audio dropLeather (PT3-2, 0.42 s; 097e1d3b…1a45) | a carrier lets go of a bundle straight down |
| bundle_land | rpg-audio bookPlace3 (PT3-2, 0.26 s; b1afa711…b06e) | a thrown or dropped bundle comes to rest |
| `retired/cash_1`, `retired/cash_2` | rpg-audio handleCoins, handleCoins2 | **Retired, not shipped** (PT3-2: the coin clicks the user heard as a gun being loaded) |
| sting | interface-sounds bong_001 | round end (and a match with no winner); also the `spotted` alarm (PT2-2), the same file played at pitch 1.25 |
| tick | interface-sounds tick_001 | countdown |
| ui_click | interface-sounds click_001 | every button |

PT3-2: every new cash file is an unmodified Kenney file, under 0.6 s, with no leading silence (sound starts at 0.00-0.04 s). Their levels are set in the `GameAudio.EVENTS` dB, matched to the old files by rms over the first 0.25 s (`tools/audio_probe.gd --ends`). None has click, latch, snap, cock, reload or metal in its name. `godot/art/audio/sfx/retired/` has a `.gdignore` and is in the export `exclude_filter`.

## Music and stings (PT2-4), fetched 2026-11-17
CC0 proof for each source sits next to the download in `autobuild/Incoming/` (gitignored): the saved page plus a SOURCE.txt with URL, licence and hashes.

| File | Name / author | Licence | URL | Modified? | sha256 of the shipped file |
|---|---|---|---|---|---|
| `godot/content/music/candidates/jazz_improvisation_loop.ogg` (was `art/audio/music/loop.ogg`) | "jazz improvisation looped", Pro Sensory (Alex McCulloch) | CC0 | https://opengameart.org/content/jazz-improvisation-looped | **Candidate, not shipped** since PT3-1 (the user found it like phone hold music). No: the site's own .ogg rendition of the .mp3 (131.9 s); its loop end was 128.3 s | 46581d10…16d6 |
| `godot/art/audio/music/jingle_win.ogg` | Music Jingles `jingles_PIZZI02`, Kenney | CC0 1.0 | https://kenney.nl/assets/music-jingles | No (0.96 s, a rising scale) | 4967dc3c…3e3e |
| `godot/art/audio/music/jingle_lose.ogg` | Music Jingles `jingles_PIZZI07`, Kenney | CC0 1.0 | https://kenney.nl/assets/music-jingles | No (1.32 s, falling by semitones) | 91870588…ce7c |
| `godot/content/sfx/jailed.ogg` | "Boings" `bung_01.mp3`, EZduzziteh | CC0 | https://opengameart.org/node/183317 | Yes: silence trimmed to 0.35 s, 10 ms fades, MP3 → Ogg Vorbis q5 (`godot/tools/decode_audio.gd` + `autobuild/encode_ogg.mjs`) | e32ce9da…5223 |

Kenney zip sha256 in `autobuild/Incoming/kenney/music-jingles/SOURCE.txt`. The `spotted` alarm still reuses `sting` at pitch 1.25 (PT2-2). The user may replace `jailed.ogg` with their own recording (HOW_TO_PLAY.md); log it here as theirs.
Encoder used for jailed.ogg: `wasm-media-encoders` 0.7.0 (npm, MIT; libvorbis BSD), installed outside the repo, not shipped.

## Menu music (PT3-1), fetched 2026-11-18
Proof: the saved OpenGameArt pages and `SOURCE.txt` in `autobuild/Incoming/music/pt3_1/` (gitignored). `godot/content/music/candidates/` has a `.gdignore` (Godot neither imports nor exports it) and is also in the export's `exclude_filter`.

| File | Name / author | Licence | URL | Modified? | sha256 of the file |
|---|---|---|---|---|---|
| `godot/content/music/menu.ogg` (shipped; the same file is kept as `candidates/trouble_in_the_garden.ogg`) | "Trouble in the Garden", HaelDB | CC0 (the page offers CC0 or OGA-BY 3.0; used under CC0) | https://opengameart.org/content/trouble-in-the-garden | No (106.0 s; sound ends at 104.3 s, GameAudio loops at 104.4 s) | ce261e0c…3df6 |
| `godot/content/music/candidates/deliberate_concealment.ogg` | "Deliberate Concealment", northivanastan | CC0 | https://opengameart.org/content/deliberate-concealment | **Candidate, not shipped.** No (157.0 s, sound to 155.9 s) | 237269cf…cb2b |
| `godot/content/music/candidates/sneaking_around.ogg` | "Sneaking Around", Umplix | CC0 | https://opengameart.org/content/sneaking-around | **Candidate, not shipped.** The site's own .ogg rendition of the .wav (88.0 s, sound 0.3..85.9 s) | da948cd5…9ba0 |

## UI fonts and icons (PT2-6), fetched 2026-11-18
Fonts from the Google Fonts repository on GitHub (`google/fonts`, `ofl/<family>/`), each with its OFL.txt shipped beside it (the export's `include_filter` takes `art/ui/fonts/*.txt`). Icons from Kenney's Game Icons (`node autobuild/fetch_kenney.mjs game-icons`; zip sha256 7a86d8d58e0b851e22004b3c70bf90b003632bbf9ac633424daa3bb17d9e7e4e; licence file and SOURCE.txt in gitignored `autobuild/Incoming/kenney/game-icons/`; `Kenney-License.txt` copied beside the icons).

| File | Name / author | Licence | URL | Modified? | sha256 of the shipped file |
|---|---|---|---|---|---|
| `godot/art/ui/fonts/Anton-Regular.ttf` | Anton, Vernon Adams / The Anton Project Authors | SIL OFL 1.1 (`Anton-OFL.txt`) | https://github.com/google/fonts/tree/main/ofl/anton | No | a4ba3a92…7cab |
| `godot/art/ui/fonts/Inter-Variable.ttf` | Inter (variable, opsz + wght), Rasmus Andersson / The Inter Project Authors | SIL OFL 1.1 (`Inter-OFL.txt`) | https://github.com/google/fonts/tree/main/ofl/inter | No (renamed from `Inter[opsz,wght].ttf`; weights 450 and 650 picked at run time) | 29160a80…9031 |
| `godot/art/ui/icons/locked.png` | Game Icons `PNG/White/2x/locked.png`, Kenney | CC0 1.0 | https://kenney.nl/assets/game-icons | No (HUD: jailed) | b83e9f3d…9cd1 |
| `godot/art/ui/icons/unlocked.png` | Game Icons `unlocked.png`, Kenney | CC0 1.0 | https://kenney.nl/assets/game-icons | No (HUD: free a teammate) | fd9e8d85…6a80 |
| `godot/art/ui/icons/trophy.png` | Game Icons `trophy.png`, Kenney | CC0 1.0 | https://kenney.nl/assets/game-icons | No (results card) | 9525a3a0…8714 |
| `godot/art/ui/icons/exclamation.png` | Game Icons `exclamation.png`, Kenney | CC0 1.0 | https://kenney.nl/assets/game-icons | No. Not used (copied, then this session's permissions refused deleting it) | 60faed66…9928 |

The HUD's banknote icon is drawn in code (`UiTheme.cash_icon`); the pack has none.
