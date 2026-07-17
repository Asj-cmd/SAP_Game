# Graph Report - .  (2026-07-17)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1517 nodes · 1996 edges · 128 communities (95 shown, 33 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 29 edges (avg confidence: 0.55)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7ee4c0db`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 77
- Community 78
- Community 79
- Community 80
- Community 81
- Community 82
- Community 83
- Community 84
- Community 85
- Community 86
- Community 87
- Community 88
- Community 89
- Community 90
- Community 91
- Community 92
- Community 93
- Community 94
- Community 95
- Community 96
- Community 97
- Community 98
- Community 99
- Community 100
- Community 101
- Community 102
- Community 103
- Community 104
- Community 105
- Community 106
- Community 107
- Community 108
- Community 109
- Community 110
- Community 111
- Community 112
- Community 113
- Community 115
- Community 116
- Community 117
- Community 118
- Community 119
- Community 120
- Community 121
- Community 122
- Community 123

## God Nodes (most connected - your core abstractions)
1. `GameRoom` - 36 edges
2. `GameController` - 24 edges
3. `Quick Reference` - 24 edges
4. `Rule Sections` - 24 edges
5. `heightAt()` - 22 edges
6. `Game` - 20 edges
7. `TSL Complete Reference` - 19 edges
8. `InputController` - 18 edges
9. `buildEnvironment()` - 17 edges
10. `build_character()` - 16 edges

## Surprising Connections (you probably didn't know these)
- `WallSpanSegment` --references--> `Rect`  [EXTRACTED]
  client/src/three/world/HeightField.ts → client/src/geometry/floorplan.ts
- `Game` --references--> `InputController`  [EXTRACTED]
  .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/game/Game.ts → .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/core/InputController.ts
- `Game` --references--> `Pickup`  [EXTRACTED]
  .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/game/Game.ts → .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/entities/Pickup.ts
- `Game` --references--> `DebugTools`  [EXTRACTED]
  .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/game/Game.ts → .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/systems/DebugTools.ts
- `Game` --references--> `DebugTuning`  [EXTRACTED]
  .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/game/Game.ts → .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/systems/DebugTools.ts

## Import Cycles
- None detected.

## Communities (128 total, 33 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.07
Nodes (34): app, clientDist, codeToRoomId, gameServer, handler, httpServer, roomIdToCode, clamp() (+26 more)

### Community 1 - "Community 1"
Cohesion: 0.12
Nodes (34): add_box(), _add_camera(), add_capsule(), add_cone(), add_flattened_hemisphere(), add_frustum(), add_head_and_face(), add_sphere() (+26 more)

### Community 2 - "Community 2"
Cohesion: 0.06
Nodes (34): 0. Modern Setup (FUNDAMENTAL), 10. TSL - Three.js Shading Language (MEDIUM), 11. WebGPU Renderer (MEDIUM), 12. Loading & Assets (MEDIUM), 13. Core Web Vitals (MEDIUM-HIGH), 14. Camera & Controls (LOW-MEDIUM), 15. Animation (MEDIUM), 16. Physics (MEDIUM) (+26 more)

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (32): 0. Read This First, 10. What Is Explicitly NOT in Phase 1, 11. Definition of Done for Phase 1, 1. Tech Stack (Non-Negotiable), 2. Project Structure, 3.1 World Dimensions, 3.2 Zone Map (pixel coordinates), 3.3 Entry Points (+24 more)

### Community 4 - "Community 4"
Cohesion: 0.06
Nodes (31): dependencies, lil-gui, three, devDependencies, @playwright/test, pngjs, @types/node, @types/pngjs (+23 more)

### Community 5 - "Community 5"
Cohesion: 0.10
Nodes (9): getZoneAt(), isEnemyBedroom(), isOwnHome(), jailBasementForTeam(), Action, dist(), GameController, InputState (+1 more)

### Community 6 - "Community 6"
Cohesion: 0.12
Nodes (26): dressHouses(), mirrorPlacement(), mirrorRot(), placeIndividually(), solidRect(), buildInstancedProps(), dummy, applyMaterialRoles() (+18 more)

### Community 7 - "Community 7"
Cohesion: 0.06
Nodes (30): colyseus, @colyseus/schema, @colyseus/ws-transport, cors, express, dependencies, colyseus, @colyseus/schema (+22 more)

### Community 8 - "Community 8"
Cohesion: 0.07
Nodes (27): Aliases Removed, BAD - Deprecated, BAD - Old API, Color Management (r151+), Common Migration Issues, Geometry Changes (r125+), GOOD - Current, GOOD - Current API (+19 more)

### Community 9 - "Community 9"
Cohesion: 0.11
Nodes (12): Team, CharacterController, CharacterModel, FAMILY_ORDER, FamilyVariant, loadBundleTemplate(), pickFamilyVariant(), VARIANT_TOP (+4 more)

### Community 10 - "Community 10"
Cohesion: 0.08
Nodes (24): Priority 0: Modern Setup & Imports (FUNDAMENTAL), Priority 10: TSL - Three.js Shading Language (MEDIUM), Priority 11: WebGPU Renderer (MEDIUM), Priority 12: Loading & Assets (MEDIUM), Priority 13: Core Web Vitals (MEDIUM-HIGH), Priority 14: Camera & Controls (LOW-MEDIUM), Priority 15: Animation System (MEDIUM), Priority 16: Physics Integration (MEDIUM) (+16 more)

### Community 11 - "Community 11"
Cohesion: 0.11
Nodes (15): checkRenderBudget(), computePixelMetrics(), main(), parseArgs(), RENDER_BUDGETS, sampleCanvas(), ThreeGameDiagnostics, ThreeGameTestHooks (+7 more)

### Community 12 - "Community 12"
Cohesion: 0.26
Nodes (22): _add_camera(), box(), build_bed(), build_coffee_table(), build_crate(), build_dresser(), build_jail_bars(), build_nightstand() (+14 more)

### Community 13 - "Community 13"
Cohesion: 0.09
Nodes (22): dependencies, colyseus.js, three, devDependencies, playwright-core, @types/three, typescript, vite (+14 more)

### Community 14 - "Community 14"
Cohesion: 0.21
Nodes (20): DOORS, buildEnvironment(), coloredBox(), doorBase(), doorFrameBase(), doorFrameGeoms(), foundationGeoms(), intersectRect() (+12 more)

### Community 15 - "Community 15"
Cohesion: 0.10
Nodes (20): compilerOptions, allowImportingTsExtensions, isolatedModules, module, moduleResolution, noEmit, noFallthroughCasesInSwitch, noUnusedLocals (+12 more)

### Community 16 - "Community 16"
Cohesion: 0.10
Nodes (18): Arrays, Camera Data, Color Adjustments, Conditionals, Flow Control, Fog, Loops, Normal Nodes (+10 more)

### Community 17 - "Community 17"
Cohesion: 0.19
Nodes (18): has_audio_blocker(), has_audio_output_evidence(), has_external_blocker(), has_external_output_evidence(), main(), marker_pattern(), missing_markers(), normalize() (+10 more)

### Community 18 - "Community 18"
Cohesion: 0.17
Nodes (11): COLORS, ROOF_BASE, Door, Rect, ZONE_RECTS, ZoneId, ZoneRect, Environment (+3 more)

### Community 19 - "Community 19"
Cohesion: 0.15
Nodes (10): CameraRig, CashBundleView, Axis, clamp01(), corridorHeight(), heightAt(), inCorridor(), probeSpan() (+2 more)

### Community 20 - "Community 20"
Cohesion: 0.24
Nodes (18): _add_camera(), box(), build_bush(), build_fence(), build_fountain(), build_shed(), build_stone_path(), build_tree() (+10 more)

### Community 21 - "Community 21"
Cohesion: 0.11
Nodes (18): BAD - Bidirectional sync, Basic Usage, Basic Usage, Best Practices, Body Types, Cannon-es, Collider Shapes, Debug Visualization (+10 more)

### Community 22 - "Community 22"
Cohesion: 0.11
Nodes (18): 1. One-time setup, 2. Start the game, 3. Get your friends in, Actually Running the Game, Beginner's Guide: Getting Started (Step-by-Step), Cash Grab, Controls, For developers (+10 more)

### Community 23 - "Community 23"
Cohesion: 0.11
Nodes (18): compilerOptions, emitDecoratorMetadata, esModuleInterop, experimentalDecorators, forceConsistentCasingInFileNames, lib, module, moduleResolution (+10 more)

### Community 24 - "Community 24"
Cohesion: 0.11
Nodes (17): Best Practices, CDN Decoder Paths, Compression Results, Draco Compression, Draco vs Meshopt, Full Loader Setup, Full Optimization Pipeline, GLTF Loading & Optimization (+9 more)

### Community 25 - "Community 25"
Cohesion: 0.16
Nodes (8): PointerState, ArenaBounds, Player, PlayerTuning, ARENA, DebugTools, DebugTuning, createSeededRandom()

### Community 26 - "Community 26"
Cohesion: 0.19
Nodes (3): createRenderer(), resizeRenderer(), Game

### Community 27 - "Community 27"
Cohesion: 0.11
Nodes (17): Arcade Racer, Billiards / Pool / Snooker, Boss Fight / Action Arena, Core Loop Contract, Design Brief Gate, Difficulty And Pacing, Dogfight / Space Shooter, Endless Runner (+9 more)

### Community 28 - "Community 28"
Cohesion: 0.22
Nodes (16): _add_camera(), add_head_and_face(), bind_mesh_to_armature(), build_animations(), build_armature(), build_body_mesh(), clear_scene(), _closest_point_on_segment() (+8 more)

### Community 29 - "Community 29"
Cohesion: 0.12
Nodes (16): BAD - Multiple passes, Device Detection, Draw Calls, GOOD - Combined SuperShader, Level of Detail, Material Hierarchy (Fast to Slow), Memory Management, Mobile Checklist (+8 more)

### Community 30 - "Community 30"
Cohesion: 0.16
Nodes (4): LobbyView, onGameStart(), ColyseusClient, HOST

### Community 31 - "Community 31"
Cohesion: 0.12
Nodes (16): compilerOptions, esModuleInterop, isolatedModules, lib, module, moduleResolution, noEmit, resolveJsonModule (+8 more)

### Community 32 - "Community 32"
Cohesion: 0.12
Nodes (15): Asset Compression, CLI Optimization, Draco Compression, Geometry Compression, gltf-transform (Recommended), KTX2 Setup, Level of Detail (LOD), Meshopt (Alternative to Draco) (+7 more)

### Community 33 - "Community 33"
Cohesion: 0.12
Nodes (15): Browser DevTools Performance Tab, Chrome WebGPU DevTools, Clean Render Loop, Context Lost Handling, Debug Checklist, Debug & DevTools, Debug Helpers, GPU Timing Queries (WebGPU) (+7 more)

### Community 34 - "Community 34"
Cohesion: 0.13
Nodes (14): Alternative: pmndrs/postprocessing, Available Effects, Best Practices, Bloom, Color Grading Pipeline, Common Patterns, Depth of Field, EffectComposer (WebGL Traditional) (+6 more)

### Community 35 - "Community 35"
Cohesion: 0.13
Nodes (14): AAA Graphics Implementation Blueprint, Browser Game Budgets, Diagnostics, Hybrid AI Asset Pipeline, Implementation Order, Material Library, Model Factories, Procedural Texture And Decal Kit (+6 more)

### Community 36 - "Community 36"
Cohesion: 0.13
Nodes (14): External Asset Sourcing Gate, Final Response, Ledgers, Packaged Runtime Resources, Phase Routing, Premium Completion Rule, Purpose, Reference Gate (+6 more)

### Community 38 - "Community 38"
Cohesion: 0.13
Nodes (14): Architecture Boundaries, Audio Hooks, Camera And Controls, Collision And Physics, Common Failures, Design And Level Iteration, Diagnostics, First Playable Slice (+6 more)

### Community 39 - "Community 39"
Cohesion: 0.14
Nodes (13): 1. Create a mesh from raw vertex data, 2. Use bmesh for advanced mesh editing, 3. Apply modifiers programmatically, 4. Create curves and surfaces, 5. Procedural generation patterns, 6. Assign materials to faces, Blender 3D Modeling, Example 1: Parametric staircase (+5 more)

### Community 40 - "Community 40"
Cohesion: 0.14
Nodes (13): Alpha Cutout, Basic Slots, Color with Time Animation, Core Slots, Custom Normal Mapping, Lighting Slots, MeshPhysicalNodeMaterial Specific, Output Slots (+5 more)

### Community 41 - "Community 41"
Cohesion: 0.14
Nodes (13): 1. Use `renderAsync` for Compute-Heavy Scenes, 2. Force WebGL for Testing, 3. Feature Detection, 4. GPU-Persistent Buffers with `instancedArray`, 5. Storage Textures for Read-Write Compute, 6. Workgroup Shared Memory, 7. Indirect Draws for GPU-Driven Rendering, Best Practices (+5 more)

### Community 42 - "Community 42"
Cohesion: 0.14
Nodes (13): Allowed External-Generation Skip Reasons, Completion Gate, Director Phase Playbook, Ledger Templates, Non-Negotiable Rules, Phase 1: Discovery And Playable Contract, Phase 2: Gameplay Systems, Phase 3: External Asset Sourcing (+5 more)

### Community 43 - "Community 43"
Cohesion: 0.14
Nodes (13): Anti-Patterns, Audio Feel Coupling, Camera Kick / FOV Punch, Determinism, Game Feel, Gamepad Rumble, Hitstop, Impact Flash (+5 more)

### Community 44 - "Community 44"
Cohesion: 0.29
Nodes (12): WALLS, wallSegments(), buildWallBoxes(), buildWindows(), findWallIndex(), plainBox(), proudRunRect(), runRect() (+4 more)

### Community 45 - "Community 45"
Cohesion: 0.15
Nodes (12): Animation Blending, Animation System, Basic Usage, Best Practices, Creating Custom Animations, Events, Loop Modes, Morph Targets (+4 more)

### Community 46 - "Community 46"
Cohesion: 0.15
Nodes (12): Audio Analyzer, Audio Controls, Audio Formats, Best Practices, Components, Distance Models, Loading Audio, Multiple Audio Sources (+4 more)

### Community 47 - "Community 47"
Cohesion: 0.15
Nodes (12): Best Practices, Common Causes of Context Loss, Error Handling & Context Recovery, Graceful Degradation, Memory Monitoring, Production Logging, React Error Boundary, Recovery Strategies (+4 more)

### Community 48 - "Community 48"
Cohesion: 0.15
Nodes (12): Bake Lightmaps for Static Scenes, Cascaded Shadow Maps (CSM) for Large Scenes, Checklist, Disable Shadow Auto-Update for Static Scenes, Environment Maps for Ambient Light, Fake Shadows for Simple Cases, Light Probes, Lighting & Shadows Advanced (+4 more)

### Community 49 - "Community 49"
Cohesion: 0.15
Nodes (12): Add Antialiasing at the End, Apply Tone Mapping at Pipeline End, Bloom Parameter Tuning, Configure Renderer for Post-Processing, Disable Multisampling When Not Needed, Merge Compatible Effects, Performance Checklist, Post-Processing Optimization (+4 more)

### Community 50 - "Community 50"
Cohesion: 0.15
Nodes (12): AR Features, AR Hit Testing, Basic Setup, Best Practices, Browser Support (2025), Controllers, Hand Tracking, Reference Spaces (+4 more)

### Community 51 - "Community 51"
Cohesion: 0.15
Nodes (12): (a) Fresnel rim glow, (b) Scrolling emissive panels, (c) Wind sway (foliage / flags), Cheap Tricks, (d) Dissolve / spawn, Glass: real vs fake, Gradient Sky Dome, onBeforeCompile Patterns (+4 more)

### Community 52 - "Community 52"
Cohesion: 0.15
Nodes (12): Animation, Loop, And Physics, Asset Loading, Audio Loading And Playback, Blank Or Bad Canvas, Bug Report Format, Common Mistakes, Debug And Profile Checklists, Input And Mobile Bugs (+4 more)

### Community 53 - "Community 53"
Cohesion: 0.15
Nodes (12): 2D Asset Generation, Common Failures, Game UI Patterns, HUD Composition, Menus And Overlays, Required States, Responsive Constraints, State Wiring (+4 more)

### Community 54 - "Community 54"
Cohesion: 0.17
Nodes (11): Checklist, Code-Split Three.js Modules, Core Web Vitals & Loading, Lazy Load 3D Content Below the Fold, Offload to Web Workers, Performance Budget, Placeholder Geometry, Preload Critical Assets (+3 more)

### Community 55 - "Community 55"
Cohesion: 0.17
Nodes (11): 1. InstancedMesh (Identical Objects), 2. BatchedMesh (Varied Geometries), 3. Merge Static Geometry, 4. Share Materials, 5. Array Textures (Modern Browsers), 6. Frustum Culling, Decision Tree, Draw Call Optimization (+3 more)

### Community 56 - "Community 56"
Cohesion: 0.17
Nodes (11): Basic Raycaster, Best Practices, BVH Options, GPU Picking, Layers for Filtering, Octree for Scenes, Raycasting Optimization, References (+3 more)

### Community 57 - "Community 57"
Cohesion: 0.17
Nodes (11): Diagnostics Checklist, Hero Character Recipe, Hero Vehicle Recipe, Material And Detail Rules, Minimum Premium Asset Pass, Modeling Principles, Obstacle And Enemy Families, Procedural Geometry Techniques (+3 more)

### Community 58 - "Community 58"
Cohesion: 0.17
Nodes (11): Camera Composition, Event-Driven VFX, Fog, Background, And Depth, Lighting Stack, Materials, Performance Checks, Post-Processing, Readability Checks (+3 more)

### Community 59 - "Community 59"
Cohesion: 0.17
Nodes (11): Browser QA Matrix, Bug Report Format, Common Release Failures, Evidence Format, Interaction QA, Mobile QA, Performance QA, QA And Release Checklists (+3 more)

### Community 60 - "Community 60"
Cohesion: 0.18
Nodes (10): Advanced Effects, Basic Shader Structure, Dissolve Effect, Post-Processing Effects, Shader Languages by Engine, Shader Optimization, Shader Pipeline Overview, Shader Techniques (+2 more)

### Community 61 - "Community 61"
Cohesion: 0.18
Nodes (10): Avoid `discard`, Avoid Dynamic Loops, Minimize Varying Variables, Mobile Shader Checklist, Pack Data into RGBA Channels, Precompute on CPU, Replace Conditionals with `mix()` and `step()`, Shader Optimization for Mobile (+2 more)

### Community 62 - "Community 62"
Cohesion: 0.18
Nodes (10): Atomic Operations, Barriers, Basic Compute Shader, Best Practices, Compute Variables, GPGPU with Render Targets (WebGL Fallback), Particle System Example, Performance Comparison (+2 more)

### Community 63 - "Community 63"
Cohesion: 0.18
Nodes (10): Color And Readability, Decals, Trim, And Surface Detail, Generated And Imported Asset Cleanup, Instancing, LOD, And Culling, Material And Shader System, Render Budget Starting Points, Technical Art Brief, Technical Art For Three.js Games (+2 more)

### Community 65 - "Community 65"
Cohesion: 0.18
Nodes (10): Architecture Rules, Choose By Game Type, Common Failures, Current Recommendation, Physics Engine Selection, Rapier Setup Pattern, Source Basis, Tuning Rules (+2 more)

### Community 66 - "Community 66"
Cohesion: 0.18
Nodes (10): description, name, private, scripts, build:client, dev:client, dev:server, install:all (+2 more)

### Community 67 - "Community 67"
Cohesion: 0.20
Nodes (9): Bad Example, geometry-instanced-mesh, Good Example, Performance Comparison, Raycasting, References, Updating Instances, When NOT to Use (+1 more)

### Community 68 - "Community 68"
Cohesion: 0.20
Nodes (9): Bad Example, Common Patterns, Good Example, Lerp with Delta, Movement, References, render-delta-time, Time-based Effects (+1 more)

### Community 69 - "Community 69"
Cohesion: 0.20
Nodes (9): Animated Color, Bad Example, Custom Function, Good Example, More TSL Examples, References, tsl-why-use, Vertex Displacement (+1 more)

### Community 70 - "Community 70"
Cohesion: 0.20
Nodes (9): AAA Graphics Production Pass Prompt, Before/After Visual Critique Prompt, Fresh-Eyes Scorecard Review Prompt, Material, Lighting, and Render Quality Pass Prompt, Procedural Hero Asset Pass Prompt, Technical Art Pass Prompt, Three.js AAA Graphics Prompt Templates, Visual Polish Prompt (+1 more)

### Community 71 - "Community 71"
Cohesion: 0.20
Nodes (9): Automatic Failures, Calibration Anchors, Categories, Fresh-Eyes Review, Measured Evidence, Report Format, Scoring Scale, Thresholds (+1 more)

### Community 73 - "Community 73"
Cohesion: 0.39
Nodes (8): _add_camera(), build_bundle(), clear_scene(), export_glb(), main(), make_material(), Builds the cash bundle prop: a small stack of bills with a paper band and a coup, render_preview()

### Community 74 - "Community 74"
Cohesion: 0.22
Nodes (8): Common Failure Modes, Final Response, Library Guidance, Packaged Scaffold, Purpose, Three.js Gameplay Systems, Use When, Workflow

### Community 75 - "Community 75"
Cohesion: 0.25
Nodes (7): Bad Example, Good Example, memory-dispose-geometry, React Example, Recursive Disposal, References, Why It Matters

### Community 76 - "Community 76"
Cohesion: 0.25
Nodes (7): Anti-Pattern, Best Practices, Example: Bullet Pool, Implementation, Key Benefits, Object Pooling, When to Use

### Community 77 - "Community 77"
Cohesion: 0.25
Nodes (7): Core Rule, Final Response, Purpose, Required References, Three.js AAA Graphics Builder, Use When, Workflow

### Community 78 - "Community 78"
Cohesion: 0.25
Nodes (7): Bot Playtest, Difficulty And Fairness Signals, Headless WebGL Caveats, Metrics And What They Mean, Prerequisites, Reporting, Setup

### Community 79 - "Community 79"
Cohesion: 0.25
Nodes (7): Asset Visibility Checks, Determinism Requirements, Harness States, Playwright Pattern, Report Requirements, Visual Test Harness, When To Add A Visual Harness

### Community 80 - "Community 80"
Cohesion: 0.29
Nodes (6): Bad Example, Good Example, References, setup-use-import-maps, WebGPU Import Map, Why It Matters

### Community 81 - "Community 81"
Cohesion: 0.29
Nodes (6): Final Response, Packaged Canvas Inspector, Purpose, QA Workflow, Release Workflow, Three.js QA Release

### Community 82 - "Community 82"
Cohesion: 0.33
Nodes (5): Deliberately excluded (and why), Project rule that overrides skill defaults, Project Skills, Three.js / 3D-art / shader / Blender add-ons (individually vetted), Three.js game bundle — `majidmanzarpour/threejs-game-skills` (973★)

### Community 83 - "Community 83"
Cohesion: 0.33
Nodes (5): Debug Workflow, Final Response, Performance Workflow, Purpose, Three.js Debug Profiler

### Community 84 - "Community 84"
Cohesion: 0.33
Nodes (5): Common Failure Modes, Final Response, Purpose, Three.js Game UI Designer, Workflow

### Community 87 - "Community 87"
Cohesion: 0.40
Nodes (4): buf, length, magic, version

### Community 88 - "Community 88"
Cohesion: 0.40
Nodes (4): Mobile Input Prompt, Performance Pass Prompt, Scene Debug Prompt, Three.js Debug/Profile Prompt Templates

### Community 89 - "Community 89"
Cohesion: 0.40
Nodes (4): AAA Three.js Game Pass Prompt, New Three.js Game Prompt, Premium Endless Runner Pass Prompt, Three.js Game Director Prompt Templates

### Community 92 - "Community 92"
Cohesion: 0.50
Nodes (3): 3D Modeling, Identity, Reference System Usage

### Community 93 - "Community 93"
Cohesion: 0.50
Nodes (3): Premium HUD/UI Pass Prompt, Responsive Game Menu Pass Prompt, Three.js Game UI Prompt Templates

### Community 94 - "Community 94"
Cohesion: 0.83
Nodes (3): disposeMaterial(), disposeObject3D(), isThreeTexture()

### Community 95 - "Community 95"
Cohesion: 0.50
Nodes (3): Game Design And Level Design Prompt, Gameplay System Prompt, Three.js Gameplay Systems Prompt Templates

### Community 96 - "Community 96"
Cohesion: 0.50
Nodes (3): Release Pass Prompt, Three.js QA/Release Prompt Templates, Visual Test Harness Prompt

## Knowledge Gaps
- **804 isolated node(s):** `probe_asset_credentials.sh script`, `name`, `version`, `private`, `type` (+799 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **33 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameController` connect `Community 5` to `Community 72`, `Community 9`, `Community 18`, `Community 19`, `Community 30`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._
- **Why does `InputController` connect `Community 37` to `Community 25`, `Community 26`?**
  _High betweenness centrality (0.001) - this node is a cross-community bridge._
- **What connects `probe_asset_credentials.sh script`, `name`, `version` to the rest of the system?**
  _804 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.07191780821917808 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.1226890756302521 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.05714285714285714 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.06060606060606061 - nodes in this community are weakly interconnected._