# Project Skills

Project-scoped Claude Code skills, committed so they travel with this branch —
any session that checks out this repo loads them automatically (no per-session
`npx skills add` needed).

## Included (from `majidmanzarpour/threejs-game-skills`, 973★)

- `threejs-game-director` — orchestrator entrypoint; routes the sibling skills.
- `threejs-gameplay-systems` — mechanics, architecture, input, camera, collision, game feel.
- `threejs-aaa-graphics-builder` — models, materials, lighting, VFX, render budget (Phase 3 workhorse).
- `threejs-game-ui-designer` — HUDs, menus, overlays, responsive/touch UI.
- `threejs-debug-profiler` — draw-call/triangle/memory profiling; hold 60fps.
- `threejs-qa-release` — production build + release checks.

## Deliberately excluded

- The 3 AI-asset generators (`threejs-3d-generator` / `-image-generator` /
  `-audio-generator`) — they require paid API keys (Tripo/Gemini/ElevenLabs).
  Add them later only if we opt into those services.

## Project rule that overrides skill defaults

Per every PRD: **do not write test code / test files / automated test or QA
harnesses.** If `threejs-qa-release` suggests automated bot playtests or a visual
test harness, do not use those — verify manually against the PRD checklist.
