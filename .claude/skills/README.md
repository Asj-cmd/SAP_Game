# Project Skills

Project-scoped Claude Code skills, committed so they travel with this branch —
any session that checks out this repo loads them automatically (no per-session
`npx skills add` needed). All skills here are **content-only** (SKILL.md +
markdown/json references); none ship executable payloads that run on load.

## Three.js game bundle — `majidmanzarpour/threejs-game-skills` (973★)

- `threejs-game-director` — orchestrator entrypoint; routes the sibling skills.
- `threejs-gameplay-systems` — mechanics, architecture, input, camera, collision, game feel.
- `threejs-aaa-graphics-builder` — models, materials, lighting, VFX, render budget.
- `threejs-game-ui-designer` — HUDs, menus, overlays, responsive/touch UI.
- `threejs-debug-profiler` — draw-call/triangle/memory profiling; hold 60fps.
- `threejs-qa-release` — production build + release checks.

## Three.js / 3D-art / shader / Blender add-ons (individually vetted)

- `three-best-practices` — MIT; 120+ Three.js perf/memory/draw-call rules,
  compiled from mrdoob's official Three.js `llms` branch + Utsubo's tips.
  Source: `emalorenzo/three-agent-skills`.
- `blender-3d-modeling` — Apache-2.0; procedural bpy/bmesh modeling (meshes,
  modifiers, parametric shapes) — matches our headless
  `blender --background --python` asset pipeline. Source: `Andrew1326/dominations`.
- `3d-modeling` — 3D-art guidance: topology, UV mapping, retopo, LOD, high→low
  baking, glTF/FBX export. Source: `majiayu000/claude-skill-registry`.
- `shader-techniques` — shader programming / VFX / custom materials guidance.
  Source: `majiayu000/claude-skill-registry`.

## Deliberately excluded (and why)

- `threejs-3d-generator` / `-image-generator` / `-audio-generator` — need paid
  API keys (Tripo/Gemini/ElevenLabs). Add only if we opt into those services.
- `r3f-best-practices` — React Three Fiber; we use vanilla Three.js.
- `jeffallan/game-developer` — Unity/Unreal/ECS-focused; off-stack for our
  web/Three.js/Colyseus game.
- `code-buddy` Blender skill — the referenced path no longer exists upstream.
- WebGPU/`skillfish`/`caude-skill-manager`/docx items from the install grab-bag
  — broken commands, wrong stack, or irrelevant.

## Project rule that overrides skill defaults

Per every PRD: **do not write test code / test files / automated test or QA
harnesses.** If `threejs-qa-release` (or any skill) suggests automated bot
playtests or a visual test harness, do not use those — verify manually against
the PRD checklist.
