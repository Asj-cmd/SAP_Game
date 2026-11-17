# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P7-4 — Release sweep

This is the last open task in `PLAN.md`. The tasks above it are all `[x]` or `[-]`.

**Approach**
1. Run `git status`. Only restore `.import` churn under `godot/art` (`git checkout -- <file>`). Leave the
   "session 7 leftovers" stash alone; it is deferred bot work.
2. Run `node autobuild/build.mjs` once. It must end with `BUILD: ok` and a size close to 118.5 MB, and the
   smoke run must print no script errors. If it fails, you get two fix attempts, then BLOCKED.md.
3. Run the full `node autobuild/verify.mjs` ONCE, as the last check before committing. Do NOT pass
   `--frames` (see "Already decided").
4. Make a short docs pass with no new content:
   - In `godot/PROJECT_MEMORY.md` §2 "Where things stand", replace stale lines with: v1 task list done,
     rc1 tagged, what still waits on the user.
   - Check that `README.md`, `godot/PLAYTEST.md` and `STORE_CHECKLIST.md` do not contradict this.
5. Tick P7-4 and add the final PROGRESS entry with these parts:
   - build size, the verify numbers (tick budget per size, net_smoke ticks);
   - "every PLAN task done or deferred";
   - what is left for the user: BLOCKED.md (GodotSteam/Steamworks), a human playtest, the REVIEW items
     in DECISIONS.md, and pushing the tag.
   Delete this section from BRIEF.md in the same commit.
6. Commit `P7-4: release sweep, v0.1.0-rc1`. Then create an annotated tag on that commit:
   `git tag -a v0.1.0-rc1 -m "Cash Grab v0.1.0 release candidate 1"`.

**Already decided**
- No frame captures. The testing diet in `autobuild/PROMPT.md` (2026-11-16) replaces PLAN's
  "verify.mjs --frames over every room". P7-4 is not one of the four look tasks. The release sweep is
  `build.mjs`, the full `verify.mjs`, and the docs. Log this in DECISIONS.md as a plain decision (not
  REVIEW): "P7-4 ran verify without --frames per the testing diet; frames last judged per room in P3-7/P3-8".
- The version stays 0.1.0 (`godot/export_presets.cfg` already has 0.1.0.0). Do not bump it.
- The tag stays local. The loop pushes only `HEAD`. Pushing a tag is the user's call: write
  `git push origin v0.1.0-rc1` in the PROGRESS entry under "left for the user". Do not move or delete
  an existing tag. Today there are none.
- Do not upload the `build/` exe anywhere. Do not commit it if it is gitignored. Check `.gitignore`.
  If it is not ignored, add `build/` to `.gitignore`.

**Files likely touched**
- `PLAN.md`, `PROGRESS.md`, `DECISIONS.md`, `godot/PROJECT_MEMORY.md` (§2)
- `autobuild/BRIEF.md` (delete this section)
- possibly `.gitignore`, `README.md`, `godot/PLAYTEST.md` (stale lines only)

**Done means**
- `node autobuild/build.mjs` ends with `BUILD: ok`.
- The full `node autobuild/verify.mjs`, run once at the end, ends with `VERIFY: healthy`: all suites at
  their pinned counts, 3v3 tick budget ≤5 of 600 over, bot matches deterministic with a winner,
  net_smoke ticks agree, render gate within budget.
- P7-4 is `[x]` in PLAN.md, the PROGRESS entry is written, the commit is in, and `git tag` lists
  `v0.1.0-rc1` on that commit.

**Do NOT**
- Capture frames, sheets, sweeps or probes. No `--frames`, no `render_stats.mjs`, no `side_sweep.mjs`.
- Start Backlog items (voice chat, faces, decoys) or deferred bot tasks (P3-3d/e/f).
- Push, push tags, publish to Steam or itch, download GodotSteam or export templates.
- Write new tests or change game code. A failure here is a fix of at most two attempts, else BLOCKED.md.
- Re-run verify after it passed, or run it at the start.
