# Graph Report - SAP_Game  (2026-07-18)

## Corpus Check
- 164 files · ~112,308 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1593 nodes · 2103 edges · 140 communities (101 shown, 39 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 29 edges (avg confidence: 0.55)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `5d19b49c`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- GameRoom
- build_family.py
- Quick Reference
- Cash Grab — Phase 1 MVP: Product Requirements Document
- devDependencies
- GameController
- HouseDresser.ts
- package.json
- Migration Checklist
- CharacterModel.ts
- Rule Sections
- inspect-threejs-canvas.mjs
- build_furniture.py
- package.json
- EnvironmentBuilder.ts
- compilerOptions
- TSL Complete Reference
- audit_reference_report.py
- floorplan.ts
- HeightField.ts
- build_nature.py
- Physics Integration
- Beginner's Guide: Getting Started (Step-by-Step)
- compilerOptions
- GLTF Loading & Optimization
- Game.ts
- Game
- Game Design And Level Design
- build_character.py
- Mobile Optimization
- LobbyView
- compilerOptions
- Asset Compression
- Debug & DevTools
- TSL Post-Processing
- AAA Graphics Implementation Blueprint
- Three.js Game Director
- InputController
- Gameplay Workflows
- Instructions
- TSL Material Node Slots
- Key Tips
- Director Phase Playbook
- Game Feel
- WindowBuilder.ts
- Animation System
- Spatial Audio
- Error Handling & Context Recovery
- Lighting & Shadows Advanced
- Post-Processing Optimization
- WebXR Setup
- Shader And Material Cookbook
- Debug And Profile Checklists
- Game UI Patterns
- Core Web Vitals & Loading
- Optimization Techniques
- Raycasting Optimization
- Procedural Model Recipes
- Render, Lighting, And VFX Recipes
- QA And Release Checklists
- Shader Techniques
- Shader Optimization for Mobile
- TSL Compute Shaders
- Technical Art For Three.js Games
- Pickup
- Physics Engine Selection
- scripts
- geometry-instanced-mesh
- render-delta-time
- tsl-why-use
- prompt-templates.md
- Visual Scorecard
- HudOverlay
- build_cashbundle.py
- Three.js Gameplay Systems
- memory-dispose-geometry
- Object Pooling
- Three.js AAA Graphics Builder
- Bot Playtest
- Visual Test Harness
- setup-use-import-maps
- Three.js QA Release
- Project Skills
- Three.js Debug Profiler
- Three.js Game UI Designer
- Loop
- Hud
- inspect_glb.mjs
- prompt-templates.md
- prompt-templates.md
- AudioSystem
- CameraRig
- 3D Modeling
- prompt-templates.md
- dispose.ts
- prompt-templates.md
- prompt-templates.md
- main.ts
- bot-playtest.template.ts
- visual.spec.ts
- aaa-game-quality-gate.md
- aaa-visual-scorecard.md
- material-lighting-quality.md
- performance-safe-visual-detail.md
- procedural-model-quality.md
- technical-art-quality.md
- mobile-input.md
- performance-profile.md
- scene-debugging.md
- probe_asset_credentials.sh
- game-ui-quality.md
- hud-readability.md
- mobile-input.md
- responsive-ui-fit.md
- endless-runner-premium-quality.md
- game-design-level-design.md
- game-feel.md
- new-game-definition-of-done.md
- bot-playtest.md
- playtest-qa.md
- release.md
- visual-test-harness.md
- visual-verification.md
- What You Must Do When Invoked
- constants.ts
- graphify reference: extra exports and benchmark
- Cash Grab — Project Memory (auto-loaded)
- graphify reference: query, path, explain
- graphify reference: add a URL and watch a folder
- graphify reference: commit hook and native CLAUDE.md integration
- graphify reference: incremental update and cluster-only
- graphify reference: GitHub clone and cross-repo merge
- graphify reference: transcribe video and audio
- extraction-spec.md
- SceneManager

## God Nodes (most connected - your core abstractions)
1. `GameRoom` - 37 edges
2. `GameController` - 25 edges
3. `Quick Reference` - 24 edges
4. `Rule Sections` - 24 edges
5. `heightAt()` - 22 edges
6. `Game` - 20 edges
7. `buildEnvironment()` - 19 edges
8. `TSL Complete Reference` - 19 edges
9. `InputController` - 18 edges
10. `build_character()` - 16 edges

## Surprising Connections (you probably didn't know these)
- `Game` --references--> `InputController`  [EXTRACTED]
  .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/game/Game.ts → .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/core/InputController.ts
- `Game` --references--> `Pickup`  [EXTRACTED]
  .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/game/Game.ts → .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/entities/Pickup.ts
- `Game` --references--> `DebugTools`  [EXTRACTED]
  .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/game/Game.ts → .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/systems/DebugTools.ts
- `Game` --references--> `DebugTuning`  [EXTRACTED]
  .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/game/Game.ts → .claude/skills/threejs-gameplay-systems/assets/threejs-vite-game/src/systems/DebugTools.ts
- `buildCorridorSteps()` --calls--> `teamSideAt()`  [EXTRACTED]
  client/src/three/world/StaircaseBuilder.ts → client/src/constants.ts

## Import Cycles
- None detected.

## Communities (140 total, 39 thin omitted)

### Community 0 - "GameRoom"
Cohesion: 0.07
Nodes (34): app, clientDist, codeToRoomId, gameServer, handler, httpServer, roomIdToCode, clamp() (+26 more)

### Community 1 - "build_family.py"
Cohesion: 0.12
Nodes (34): add_box(), _add_camera(), add_capsule(), add_cone(), add_flattened_hemisphere(), add_frustum(), add_head_and_face(), add_sphere() (+26 more)

### Community 2 - "Quick Reference"
Cohesion: 0.06
Nodes (34): 0. Modern Setup (FUNDAMENTAL), 10. TSL - Three.js Shading Language (MEDIUM), 11. WebGPU Renderer (MEDIUM), 12. Loading & Assets (MEDIUM), 13. Core Web Vitals (MEDIUM-HIGH), 14. Camera & Controls (LOW-MEDIUM), 15. Animation (MEDIUM), 16. Physics (MEDIUM) (+26 more)

### Community 3 - "Cash Grab — Phase 1 MVP: Product Requirements Document"
Cohesion: 0.06
Nodes (32): 0. Read This First, 10. What Is Explicitly NOT in Phase 1, 11. Definition of Done for Phase 1, 1. Tech Stack (Non-Negotiable), 2. Project Structure, 3.1 World Dimensions, 3.2 Zone Map (pixel coordinates), 3.3 Entry Points (+24 more)

### Community 4 - "devDependencies"
Cohesion: 0.06
Nodes (31): dependencies, lil-gui, three, devDependencies, @playwright/test, pngjs, @types/node, @types/pngjs (+23 more)

### Community 6 - "HouseDresser.ts"
Cohesion: 0.13
Nodes (25): dressHouses(), mirrorPlacement(), mirrorRot(), placeIndividually(), solidRect(), buildInstancedProps(), dummy, applyMaterialRoles() (+17 more)

### Community 7 - "package.json"
Cohesion: 0.06
Nodes (30): colyseus, @colyseus/schema, @colyseus/ws-transport, cors, express, dependencies, colyseus, @colyseus/schema (+22 more)

### Community 8 - "Migration Checklist"
Cohesion: 0.07
Nodes (27): Aliases Removed, BAD - Deprecated, BAD - Old API, Color Management (r151+), Common Migration Issues, Geometry Changes (r125+), GOOD - Current, GOOD - Current API (+19 more)

### Community 9 - "CharacterModel.ts"
Cohesion: 0.15
Nodes (11): Team, CharacterModel, FAMILY_ORDER, FamilyVariant, loadBundleTemplate(), pickFamilyVariant(), VARIANT_TOP, VARIANT_URL() (+3 more)

### Community 10 - "Rule Sections"
Cohesion: 0.08
Nodes (24): Priority 0: Modern Setup & Imports (FUNDAMENTAL), Priority 10: TSL - Three.js Shading Language (MEDIUM), Priority 11: WebGPU Renderer (MEDIUM), Priority 12: Loading & Assets (MEDIUM), Priority 13: Core Web Vitals (MEDIUM-HIGH), Priority 14: Camera & Controls (LOW-MEDIUM), Priority 15: Animation System (MEDIUM), Priority 16: Physics Integration (MEDIUM) (+16 more)

### Community 11 - "inspect-threejs-canvas.mjs"
Cohesion: 0.11
Nodes (15): checkRenderBudget(), computePixelMetrics(), main(), parseArgs(), RENDER_BUDGETS, sampleCanvas(), ThreeGameDiagnostics, ThreeGameTestHooks (+7 more)

### Community 12 - "build_furniture.py"
Cohesion: 0.26
Nodes (22): _add_camera(), box(), build_bed(), build_coffee_table(), build_crate(), build_dresser(), build_jail_bars(), build_nightstand() (+14 more)

### Community 13 - "package.json"
Cohesion: 0.09
Nodes (22): dependencies, colyseus.js, three, devDependencies, playwright-core, @types/three, typescript, vite (+14 more)

### Community 14 - "EnvironmentBuilder.ts"
Cohesion: 0.17
Nodes (27): teamSideAt(), DOORS, WALLS, buildEnvironment(), coloredBox(), doorBase(), doorFrameBase(), doorFrameGeoms() (+19 more)

### Community 15 - "compilerOptions"
Cohesion: 0.10
Nodes (20): compilerOptions, allowImportingTsExtensions, isolatedModules, module, moduleResolution, noEmit, noFallthroughCasesInSwitch, noUnusedLocals (+12 more)

### Community 16 - "TSL Complete Reference"
Cohesion: 0.10
Nodes (18): Arrays, Camera Data, Color Adjustments, Conditionals, Flow Control, Fog, Loops, Normal Nodes (+10 more)

### Community 17 - "audit_reference_report.py"
Cohesion: 0.19
Nodes (18): has_audio_blocker(), has_audio_output_evidence(), has_external_blocker(), has_external_output_evidence(), main(), marker_pattern(), missing_markers(), normalize() (+10 more)

### Community 18 - "floorplan.ts"
Cohesion: 0.17
Nodes (16): COLORS, DEFAULT_PITCH, FOLLOW_DISTANCE, ROOF_BASE, getZoneAt(), isEnemyBedroom(), isOwnHome(), jailBasementForTeam() (+8 more)

### Community 19 - "HeightField.ts"
Cohesion: 0.13
Nodes (14): Door, Rect, CashBundleView, CharacterController, Environment, Axis, clamp01(), corridorHeight() (+6 more)

### Community 20 - "build_nature.py"
Cohesion: 0.24
Nodes (18): _add_camera(), box(), build_bush(), build_fence(), build_fountain(), build_shed(), build_stone_path(), build_tree() (+10 more)

### Community 21 - "Physics Integration"
Cohesion: 0.11
Nodes (18): BAD - Bidirectional sync, Basic Usage, Basic Usage, Best Practices, Body Types, Cannon-es, Collider Shapes, Debug Visualization (+10 more)

### Community 22 - "Beginner's Guide: Getting Started (Step-by-Step)"
Cohesion: 0.11
Nodes (18): 1. One-time setup, 2. Start the game, 3. Get your friends in, Actually Running the Game, Beginner's Guide: Getting Started (Step-by-Step), Cash Grab, Controls, For developers (+10 more)

### Community 23 - "compilerOptions"
Cohesion: 0.11
Nodes (18): compilerOptions, emitDecoratorMetadata, esModuleInterop, experimentalDecorators, forceConsistentCasingInFileNames, lib, module, moduleResolution (+10 more)

### Community 24 - "GLTF Loading & Optimization"
Cohesion: 0.11
Nodes (17): Best Practices, CDN Decoder Paths, Compression Results, Draco Compression, Draco vs Meshopt, Full Loader Setup, Full Optimization Pipeline, GLTF Loading & Optimization (+9 more)

### Community 25 - "Game.ts"
Cohesion: 0.16
Nodes (8): PointerState, ArenaBounds, Player, PlayerTuning, ARENA, DebugTools, DebugTuning, createSeededRandom()

### Community 26 - "Game"
Cohesion: 0.19
Nodes (3): createRenderer(), resizeRenderer(), Game

### Community 27 - "Game Design And Level Design"
Cohesion: 0.11
Nodes (17): Arcade Racer, Billiards / Pool / Snooker, Boss Fight / Action Arena, Core Loop Contract, Design Brief Gate, Difficulty And Pacing, Dogfight / Space Shooter, Endless Runner (+9 more)

### Community 28 - "build_character.py"
Cohesion: 0.22
Nodes (16): _add_camera(), add_head_and_face(), bind_mesh_to_armature(), build_animations(), build_armature(), build_body_mesh(), clear_scene(), _closest_point_on_segment() (+8 more)

### Community 29 - "Mobile Optimization"
Cohesion: 0.12
Nodes (16): BAD - Multiple passes, Device Detection, Draw Calls, GOOD - Combined SuperShader, Level of Detail, Material Hierarchy (Fast to Slow), Memory Management, Mobile Checklist (+8 more)

### Community 30 - "LobbyView"
Cohesion: 0.16
Nodes (4): LobbyView, onGameStart(), ColyseusClient, HOST

### Community 31 - "compilerOptions"
Cohesion: 0.12
Nodes (16): compilerOptions, esModuleInterop, isolatedModules, lib, module, moduleResolution, noEmit, resolveJsonModule (+8 more)

### Community 32 - "Asset Compression"
Cohesion: 0.12
Nodes (15): Asset Compression, CLI Optimization, Draco Compression, Geometry Compression, gltf-transform (Recommended), KTX2 Setup, Level of Detail (LOD), Meshopt (Alternative to Draco) (+7 more)

### Community 33 - "Debug & DevTools"
Cohesion: 0.12
Nodes (15): Browser DevTools Performance Tab, Chrome WebGPU DevTools, Clean Render Loop, Context Lost Handling, Debug Checklist, Debug & DevTools, Debug Helpers, GPU Timing Queries (WebGPU) (+7 more)

### Community 34 - "TSL Post-Processing"
Cohesion: 0.13
Nodes (14): Alternative: pmndrs/postprocessing, Available Effects, Best Practices, Bloom, Color Grading Pipeline, Common Patterns, Depth of Field, EffectComposer (WebGL Traditional) (+6 more)

### Community 35 - "AAA Graphics Implementation Blueprint"
Cohesion: 0.13
Nodes (14): AAA Graphics Implementation Blueprint, Browser Game Budgets, Diagnostics, Hybrid AI Asset Pipeline, Implementation Order, Material Library, Model Factories, Procedural Texture And Decal Kit (+6 more)

### Community 36 - "Three.js Game Director"
Cohesion: 0.13
Nodes (14): External Asset Sourcing Gate, Final Response, Ledgers, Packaged Runtime Resources, Phase Routing, Premium Completion Rule, Purpose, Reference Gate (+6 more)

### Community 38 - "Gameplay Workflows"
Cohesion: 0.13
Nodes (14): Architecture Boundaries, Audio Hooks, Camera And Controls, Collision And Physics, Common Failures, Design And Level Iteration, Diagnostics, First Playable Slice (+6 more)

### Community 39 - "Instructions"
Cohesion: 0.14
Nodes (13): 1. Create a mesh from raw vertex data, 2. Use bmesh for advanced mesh editing, 3. Apply modifiers programmatically, 4. Create curves and surfaces, 5. Procedural generation patterns, 6. Assign materials to faces, Blender 3D Modeling, Example 1: Parametric staircase (+5 more)

### Community 40 - "TSL Material Node Slots"
Cohesion: 0.14
Nodes (13): Alpha Cutout, Basic Slots, Color with Time Animation, Core Slots, Custom Normal Mapping, Lighting Slots, MeshPhysicalNodeMaterial Specific, Output Slots (+5 more)

### Community 41 - "Key Tips"
Cohesion: 0.14
Nodes (13): 1. Use `renderAsync` for Compute-Heavy Scenes, 2. Force WebGL for Testing, 3. Feature Detection, 4. GPU-Persistent Buffers with `instancedArray`, 5. Storage Textures for Read-Write Compute, 6. Workgroup Shared Memory, 7. Indirect Draws for GPU-Driven Rendering, Best Practices (+5 more)

### Community 42 - "Director Phase Playbook"
Cohesion: 0.14
Nodes (13): Allowed External-Generation Skip Reasons, Completion Gate, Director Phase Playbook, Ledger Templates, Non-Negotiable Rules, Phase 1: Discovery And Playable Contract, Phase 2: Gameplay Systems, Phase 3: External Asset Sourcing (+5 more)

### Community 43 - "Game Feel"
Cohesion: 0.14
Nodes (13): Anti-Patterns, Audio Feel Coupling, Camera Kick / FOV Punch, Determinism, Game Feel, Gamepad Rumble, Hitstop, Impact Flash (+5 more)

### Community 44 - "WindowBuilder.ts"
Cohesion: 0.36
Nodes (11): STAIR_CORRIDORS, buildCorridorSideWalls(), buildCorridorSteps(), buildStaircaseGeoms(), buildStairwellWallGeoms(), clamp01(), sideSpans(), smoothstep() (+3 more)

### Community 45 - "Animation System"
Cohesion: 0.15
Nodes (12): Animation Blending, Animation System, Basic Usage, Best Practices, Creating Custom Animations, Events, Loop Modes, Morph Targets (+4 more)

### Community 46 - "Spatial Audio"
Cohesion: 0.15
Nodes (12): Audio Analyzer, Audio Controls, Audio Formats, Best Practices, Components, Distance Models, Loading Audio, Multiple Audio Sources (+4 more)

### Community 47 - "Error Handling & Context Recovery"
Cohesion: 0.15
Nodes (12): Best Practices, Common Causes of Context Loss, Error Handling & Context Recovery, Graceful Degradation, Memory Monitoring, Production Logging, React Error Boundary, Recovery Strategies (+4 more)

### Community 48 - "Lighting & Shadows Advanced"
Cohesion: 0.15
Nodes (12): Bake Lightmaps for Static Scenes, Cascaded Shadow Maps (CSM) for Large Scenes, Checklist, Disable Shadow Auto-Update for Static Scenes, Environment Maps for Ambient Light, Fake Shadows for Simple Cases, Light Probes, Lighting & Shadows Advanced (+4 more)

### Community 49 - "Post-Processing Optimization"
Cohesion: 0.15
Nodes (12): Add Antialiasing at the End, Apply Tone Mapping at Pipeline End, Bloom Parameter Tuning, Configure Renderer for Post-Processing, Disable Multisampling When Not Needed, Merge Compatible Effects, Performance Checklist, Post-Processing Optimization (+4 more)

### Community 50 - "WebXR Setup"
Cohesion: 0.15
Nodes (12): AR Features, AR Hit Testing, Basic Setup, Best Practices, Browser Support (2025), Controllers, Hand Tracking, Reference Spaces (+4 more)

### Community 51 - "Shader And Material Cookbook"
Cohesion: 0.15
Nodes (12): (a) Fresnel rim glow, (b) Scrolling emissive panels, (c) Wind sway (foliage / flags), Cheap Tricks, (d) Dissolve / spawn, Glass: real vs fake, Gradient Sky Dome, onBeforeCompile Patterns (+4 more)

### Community 52 - "Debug And Profile Checklists"
Cohesion: 0.15
Nodes (12): Animation, Loop, And Physics, Asset Loading, Audio Loading And Playback, Blank Or Bad Canvas, Bug Report Format, Common Mistakes, Debug And Profile Checklists, Input And Mobile Bugs (+4 more)

### Community 53 - "Game UI Patterns"
Cohesion: 0.15
Nodes (12): 2D Asset Generation, Common Failures, Game UI Patterns, HUD Composition, Menus And Overlays, Required States, Responsive Constraints, State Wiring (+4 more)

### Community 54 - "Core Web Vitals & Loading"
Cohesion: 0.17
Nodes (11): Checklist, Code-Split Three.js Modules, Core Web Vitals & Loading, Lazy Load 3D Content Below the Fold, Offload to Web Workers, Performance Budget, Placeholder Geometry, Preload Critical Assets (+3 more)

### Community 55 - "Optimization Techniques"
Cohesion: 0.17
Nodes (11): 1. InstancedMesh (Identical Objects), 2. BatchedMesh (Varied Geometries), 3. Merge Static Geometry, 4. Share Materials, 5. Array Textures (Modern Browsers), 6. Frustum Culling, Decision Tree, Draw Call Optimization (+3 more)

### Community 56 - "Raycasting Optimization"
Cohesion: 0.17
Nodes (11): Basic Raycaster, Best Practices, BVH Options, GPU Picking, Layers for Filtering, Octree for Scenes, Raycasting Optimization, References (+3 more)

### Community 57 - "Procedural Model Recipes"
Cohesion: 0.17
Nodes (11): Diagnostics Checklist, Hero Character Recipe, Hero Vehicle Recipe, Material And Detail Rules, Minimum Premium Asset Pass, Modeling Principles, Obstacle And Enemy Families, Procedural Geometry Techniques (+3 more)

### Community 58 - "Render, Lighting, And VFX Recipes"
Cohesion: 0.17
Nodes (11): Camera Composition, Event-Driven VFX, Fog, Background, And Depth, Lighting Stack, Materials, Performance Checks, Post-Processing, Readability Checks (+3 more)

### Community 59 - "QA And Release Checklists"
Cohesion: 0.17
Nodes (11): Browser QA Matrix, Bug Report Format, Common Release Failures, Evidence Format, Interaction QA, Mobile QA, Performance QA, QA And Release Checklists (+3 more)

### Community 60 - "Shader Techniques"
Cohesion: 0.18
Nodes (10): Advanced Effects, Basic Shader Structure, Dissolve Effect, Post-Processing Effects, Shader Languages by Engine, Shader Optimization, Shader Pipeline Overview, Shader Techniques (+2 more)

### Community 61 - "Shader Optimization for Mobile"
Cohesion: 0.18
Nodes (10): Avoid `discard`, Avoid Dynamic Loops, Minimize Varying Variables, Mobile Shader Checklist, Pack Data into RGBA Channels, Precompute on CPU, Replace Conditionals with `mix()` and `step()`, Shader Optimization for Mobile (+2 more)

### Community 62 - "TSL Compute Shaders"
Cohesion: 0.18
Nodes (10): Atomic Operations, Barriers, Basic Compute Shader, Best Practices, Compute Variables, GPGPU with Render Targets (WebGL Fallback), Particle System Example, Performance Comparison (+2 more)

### Community 63 - "Technical Art For Three.js Games"
Cohesion: 0.18
Nodes (10): Color And Readability, Decals, Trim, And Surface Detail, Generated And Imported Asset Cleanup, Instancing, LOD, And Culling, Material And Shader System, Render Budget Starting Points, Technical Art Brief, Technical Art For Three.js Games (+2 more)

### Community 65 - "Physics Engine Selection"
Cohesion: 0.18
Nodes (10): Architecture Rules, Choose By Game Type, Common Failures, Current Recommendation, Physics Engine Selection, Rapier Setup Pattern, Source Basis, Tuning Rules (+2 more)

### Community 66 - "scripts"
Cohesion: 0.18
Nodes (10): description, name, private, scripts, build:client, dev:client, dev:server, install:all (+2 more)

### Community 67 - "geometry-instanced-mesh"
Cohesion: 0.20
Nodes (9): Bad Example, geometry-instanced-mesh, Good Example, Performance Comparison, Raycasting, References, Updating Instances, When NOT to Use (+1 more)

### Community 68 - "render-delta-time"
Cohesion: 0.20
Nodes (9): Bad Example, Common Patterns, Good Example, Lerp with Delta, Movement, References, render-delta-time, Time-based Effects (+1 more)

### Community 69 - "tsl-why-use"
Cohesion: 0.20
Nodes (9): Animated Color, Bad Example, Custom Function, Good Example, More TSL Examples, References, tsl-why-use, Vertex Displacement (+1 more)

### Community 70 - "prompt-templates.md"
Cohesion: 0.20
Nodes (9): AAA Graphics Production Pass Prompt, Before/After Visual Critique Prompt, Fresh-Eyes Scorecard Review Prompt, Material, Lighting, and Render Quality Pass Prompt, Procedural Hero Asset Pass Prompt, Technical Art Pass Prompt, Three.js AAA Graphics Prompt Templates, Visual Polish Prompt (+1 more)

### Community 71 - "Visual Scorecard"
Cohesion: 0.20
Nodes (9): Automatic Failures, Calibration Anchors, Categories, Fresh-Eyes Review, Measured Evidence, Report Format, Scoring Scale, Thresholds (+1 more)

### Community 73 - "build_cashbundle.py"
Cohesion: 0.39
Nodes (8): _add_camera(), build_bundle(), clear_scene(), export_glb(), main(), make_material(), Builds the cash bundle prop: a small stack of bills with a paper band and a coup, render_preview()

### Community 74 - "Three.js Gameplay Systems"
Cohesion: 0.22
Nodes (8): Common Failure Modes, Final Response, Library Guidance, Packaged Scaffold, Purpose, Three.js Gameplay Systems, Use When, Workflow

### Community 75 - "memory-dispose-geometry"
Cohesion: 0.25
Nodes (7): Bad Example, Good Example, memory-dispose-geometry, React Example, Recursive Disposal, References, Why It Matters

### Community 76 - "Object Pooling"
Cohesion: 0.25
Nodes (7): Anti-Pattern, Best Practices, Example: Bullet Pool, Implementation, Key Benefits, Object Pooling, When to Use

### Community 77 - "Three.js AAA Graphics Builder"
Cohesion: 0.25
Nodes (7): Core Rule, Final Response, Purpose, Required References, Three.js AAA Graphics Builder, Use When, Workflow

### Community 78 - "Bot Playtest"
Cohesion: 0.25
Nodes (7): Bot Playtest, Difficulty And Fairness Signals, Headless WebGL Caveats, Metrics And What They Mean, Prerequisites, Reporting, Setup

### Community 79 - "Visual Test Harness"
Cohesion: 0.25
Nodes (7): Asset Visibility Checks, Determinism Requirements, Harness States, Playwright Pattern, Report Requirements, Visual Test Harness, When To Add A Visual Harness

### Community 80 - "setup-use-import-maps"
Cohesion: 0.29
Nodes (6): Bad Example, Good Example, References, setup-use-import-maps, WebGPU Import Map, Why It Matters

### Community 81 - "Three.js QA Release"
Cohesion: 0.29
Nodes (6): Final Response, Packaged Canvas Inspector, Purpose, QA Workflow, Release Workflow, Three.js QA Release

### Community 82 - "Project Skills"
Cohesion: 0.33
Nodes (5): Deliberately excluded (and why), Project rule that overrides skill defaults, Project Skills, Three.js / 3D-art / shader / Blender add-ons (individually vetted), Three.js game bundle — `majidmanzarpour/threejs-game-skills` (973★)

### Community 83 - "Three.js Debug Profiler"
Cohesion: 0.33
Nodes (5): Debug Workflow, Final Response, Performance Workflow, Purpose, Three.js Debug Profiler

### Community 84 - "Three.js Game UI Designer"
Cohesion: 0.33
Nodes (5): Common Failure Modes, Final Response, Purpose, Three.js Game UI Designer, Workflow

### Community 87 - "inspect_glb.mjs"
Cohesion: 0.40
Nodes (4): buf, length, magic, version

### Community 88 - "prompt-templates.md"
Cohesion: 0.40
Nodes (4): Mobile Input Prompt, Performance Pass Prompt, Scene Debug Prompt, Three.js Debug/Profile Prompt Templates

### Community 89 - "prompt-templates.md"
Cohesion: 0.40
Nodes (4): AAA Three.js Game Pass Prompt, New Three.js Game Prompt, Premium Endless Runner Pass Prompt, Three.js Game Director Prompt Templates

### Community 92 - "3D Modeling"
Cohesion: 0.50
Nodes (3): 3D Modeling, Identity, Reference System Usage

### Community 93 - "prompt-templates.md"
Cohesion: 0.50
Nodes (3): Premium HUD/UI Pass Prompt, Responsive Game Menu Pass Prompt, Three.js Game UI Prompt Templates

### Community 94 - "dispose.ts"
Cohesion: 0.83
Nodes (3): disposeMaterial(), disposeObject3D(), isThreeTexture()

### Community 95 - "prompt-templates.md"
Cohesion: 0.50
Nodes (3): Game Design And Level Design Prompt, Gameplay System Prompt, Three.js Gameplay Systems Prompt Templates

### Community 96 - "prompt-templates.md"
Cohesion: 0.50
Nodes (3): Release Pass Prompt, Three.js QA/Release Prompt Templates, Visual Test Harness Prompt

### Community 128 - "What You Must Do When Invoked"
Cohesion: 0.08
Nodes (24): For /graphify add and --watch, For /graphify query, For the commit hook and native CLAUDE.md integration, For --update and --cluster-only, /graphify, Honesty Rules, Interpreter guard for subcommands, Part A - Structural extraction for code files (+16 more)

### Community 130 - "graphify reference: extra exports and benchmark"
Cohesion: 0.22
Nodes (8): graphify reference: extra exports and benchmark, Step 6b - Wiki (only if --wiki flag), Step 7 - Neo4j export (only if --neo4j or --neo4j-push flag), Step 7a - FalkorDB export (only if --falkordb or --falkordb-push flag), Step 7b - SVG export (only if --svg flag), Step 7c - GraphML export (only if --graphml flag), Step 7d - MCP server (only if --mcp flag), Step 8 - Token reduction benchmark (only if total_words > 5000)

### Community 131 - "Cash Grab — Project Memory (auto-loaded)"
Cohesion: 0.29
Nodes (6): Build & run, Cash Grab — Project Memory (auto-loaded), Fast context — use the knowledge graph before re-reading the whole repo, Planning docs (on branch `claude/cash-grab-game-skills-qxd4ne`), Standing rules (do not break), Status: Phases 1–3 done · Phase 4 (Characters & Chaos) next

### Community 132 - "graphify reference: query, path, explain"
Cohesion: 0.33
Nodes (5): For /graphify explain, For /graphify path, graphify reference: query, path, explain, Step 0 — Constrained query expansion (REQUIRED before traversal), Step 1 — Traversal

### Community 133 - "graphify reference: add a URL and watch a folder"
Cohesion: 0.50
Nodes (3): For /graphify add, For --watch, graphify reference: add a URL and watch a folder

### Community 134 - "graphify reference: commit hook and native CLAUDE.md integration"
Cohesion: 0.50
Nodes (3): For git commit hook, For native CLAUDE.md integration, graphify reference: commit hook and native CLAUDE.md integration

### Community 135 - "graphify reference: incremental update and cluster-only"
Cohesion: 0.50
Nodes (3): For --cluster-only, For --update (incremental re-extraction), graphify reference: incremental update and cluster-only

## Knowledge Gaps
- **847 isolated node(s):** `probe_asset_credentials.sh script`, `name`, `version`, `private`, `type` (+842 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **39 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `heightAt()` connect `HeightField.ts` to `constants.ts`, `HouseDresser.ts`, `CharacterModel.ts`, `EnvironmentBuilder.ts`, `floorplan.ts`?**
  _High betweenness centrality (0.002) - this node is a cross-community bridge._
- **Why does `SceneManager` connect `SceneManager` to `floorplan.ts`, `GameController`?**
  _High betweenness centrality (0.002) - this node is a cross-community bridge._
- **Why does `GameController` connect `GameController` to `constants.ts`, `HudOverlay`, `CharacterModel.ts`, `SceneManager`, `floorplan.ts`, `HeightField.ts`, `LobbyView`?**
  _High betweenness centrality (0.001) - this node is a cross-community bridge._
- **What connects `probe_asset_credentials.sh script`, `name`, `version` to the rest of the system?**
  _847 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `GameRoom` be split into smaller, more focused modules?**
  _Cohesion score 0.07182524990744169 - nodes in this community are weakly interconnected._
- **Should `build_family.py` be split into smaller, more focused modules?**
  _Cohesion score 0.1226890756302521 - nodes in this community are weakly interconnected._
- **Should `Quick Reference` be split into smaller, more focused modules?**
  _Cohesion score 0.05714285714285714 - nodes in this community are weakly interconnected._