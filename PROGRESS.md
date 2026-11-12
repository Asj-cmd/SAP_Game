# Progress log

Newest first. One entry per task: date, task id, what changed, what the frames showed, numbers, what is left.

## 2026-11-11 — setup, re-measured on the REAL branch (planning session)
- First measured the stale Aug-15 GitHub branch by mistake (474 s stalls, no winner, no verbs). The user's 29 local commits were then merged and pushed (merge `5ac27d6`); everything below is from that version.
- 16 suites green (carry 33, command_codec 23, greybox_level 20, movement 86, navigation 28, prediction 28 checks etc. — pinned in `autobuild/test_baseline.json`). Bot match deterministic, winner team_a, 42 s of stalls, 6 captures, 6 legal encounters.
- Frame seen (`spawn_default`): a blocky voxel-style person (red shirt, blue trousers) standing on a dark-red floor beside a flat grey wall, black void behind, debug text covering the top-left. Characters exist but are crude; the world is still grey boxes.
- Still open from the docs: tick overruns (bot decision + routing > 33 ms), slide, drop-from-height, presentation for jump/throw, Steam transport, all real art, real two-machine playtest.
- Software-rendered capture works under xvfb with `--rendering-driver opengl3`; on the Windows dev PC it runs windowed.
