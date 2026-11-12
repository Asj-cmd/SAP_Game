# Progress log

Newest first. One entry per task: date, task id, what changed, what the frames showed, numbers, what is left.

## 2026-11-11 — P0-1 Baseline (Windows dev PC)
- Godot: `GODOT_BIN=C:\Godot\Godot_v4.7.1-stable_win64_console.exe` → `4.7.1.stable.official.a13da4feb`. Machine: Windows 10 Home 19045, GT 730M laptop (Compatibility renderer only, per D6).
- `node autobuild/verify.mjs` → **VERIFY: healthy**. 16 suites at exactly the pinned counts (bot_director 26, camera_controls 16, capture_system 42, carry 33, command_codec 23, content_validator 37, greybox_level 20, identity 15, lobby 42, movement 86, navigation 28, ordering 6, prediction 28, scoring_flow 44, snapshot 18, transport 28). Bot match: deterministic, winner team_a, 42 s stalls, 0 s idle, 6 captures, 6 legal encounters.
- `--frames` works windowed on this PC (no xvfb needed); 3 frames written. What they showed: `spawn_default` — voxel character (red shirt, blue-grey trousers) on a dark-red floor strip beside a grey wall, black void filling the left half, debug HUD over the top-left. `stall_spot_a` — red floor and red/grey wall slabs at close range, a black sliver at left, HUD over it. `stall_spot_b` — grey stair treads beside a navy-blue wall, black void at left. The HUD's `cam1 (200,493,1192)` line does not change with `--capture-at`, so it reports the player camera, not the capture camera.
- Housekeeping: every Godot run rewrites `godot/art/models/*.glb.import`; restored with `git checkout --`.
- Left: nothing for P0-1. Debug HUD and black void are P0-4 / P0-5.

## 2026-11-11 — setup, re-measured on the REAL branch (planning session)
- First measured the stale Aug-15 GitHub branch by mistake (474 s stalls, no winner, no verbs). The user's 29 local commits were then merged and pushed (merge `5ac27d6`); everything below is from that version.
- 16 suites green (carry 33, command_codec 23, greybox_level 20, movement 86, navigation 28, prediction 28 checks etc. — pinned in `autobuild/test_baseline.json`). Bot match deterministic, winner team_a, 42 s of stalls, 6 captures, 6 legal encounters.
- Frame seen (`spawn_default`): a blocky voxel-style person (red shirt, blue trousers) standing on a dark-red floor beside a flat grey wall, black void behind, debug text covering the top-left. Characters exist but are crude; the world is still grey boxes.
- Still open from the docs: tick overruns (bot decision + routing > 33 ms), slide, drop-from-height, presentation for jump/throw, Steam transport, all real art, real two-machine playtest.
- Software-rendered capture works under xvfb with `--rendering-driver opengl3`; on the Windows dev PC it runs windowed.
