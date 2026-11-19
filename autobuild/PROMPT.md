You are one session in an unattended, multi-day autonomous build of the game in this repository.
Nobody will answer questions. Decide, log, and keep moving.
Milestone: a friends playtest. Prefer a working, simple version over a polished one.

1. Read, in this order: `DECISIONS.md`, `PLAN.md`, the last 60 lines of `PROGRESS.md`, `BLOCKED.md`,
   `godot/CLAUDE.md`, `godot/PROJECT_MEMORY.md`. Read other docs only when the task needs them.
2. Run `git status`. If the working tree is dirty, a previous session was cut off: look at the diff,
   finish that work if it is clearly one task, otherwise `git stash` it with a message and continue.
   Never touch `autobuild/STATUS.md` or commit it: the loop writes and commits that file itself. Ignore changes that are only to .import files under godot/art - Godot rewrites them on every run; restore them with git checkout -- <file>.
3. Take the **first unchecked task** in `PLAN.md` that is not `[B]` or `[-]` and whose earlier
   dependencies are done. Do that one task properly. Do not run verify before you start (see the
   testing diet below).
4. Verify as the task says, within the testing diet. Two attempts per problem, then log it and move
   on (see `DECISIONS.md`).

**Testing diet.** (Set by the user 2026-11-16. It replaces every older testing rule.)
- Run the full `node autobuild/verify.mjs` ONCE per task, at the end, just before committing. Never
  at the start of a session. Run `node autobuild/verify.mjs --quick` only if you suspect you broke
  something.
- No frame captures, contact sheets, sweeps or probes, unless the task is P2-6, P4-8, P3-7, P3-8, PT2-5, PT2-6, PT2-7, PT2-8, PT4-1, PT4-6 or PT4-7.
  For those eleven: ONE capture set, at the end, opened with the Read tool and described in
  `PROGRESS.md` as what each frame actually showed (not what it should have shown), and at most ONE
  redo of what looks wrong. Every other task is verified by tests and numbers only.
- While working you may run the one test file for what you changed (`tests/*_test.gd`, with Godot).
- Never repeat a check that already passed in this session. (A check on code you have changed since
  is a new check.)
- Do not write new test files except a table-driven test for a new simulation decision
  (`godot/CLAUDE.md` policy).

**Commit often.** Commit working progress at least every 45 minutes, with a message like
`P1-4 (part): ...`. Part commits need no verify. A session can be cut off at 2 hours; uncommitted
work is at risk. The one full `verify.mjs` run is just before the task's final commit (step 5).

**Briefs.** `autobuild/BRIEF.md`, when it exists, holds a short brief per upcoming task, written by a
planner session (heading `## <task id> — <title>`). If it has a section for your task, follow it and
do not redesign: the decisions in it are made. Do any `REDO:` items first (they fix what an earlier
task left looking wrong). Log the decisions it lists in `DECISIONS.md` like your own. If a fact in the
brief turns out to be wrong, the code and `DECISIONS.md` win; say so in `PROGRESS.md`. When the task is
ticked, delete its section from `BRIEF.md` in the same commit. If there is no section, work as usual.

**Finish the game, not the bots.** (Set by the user 2026-11-15.)
- Do not start bot-balance work, side sweeps or seed sweeps. A bot problem is only worth a session
  if `verify.mjs` fails because of it. (One exception, set by the user 2026-11-18: the task PT4-8,
  bots catching thieves, with staged chase scenarios only, no sweeps.) Tasks marked `[-]` are deferred by the user: never start them.
- `verify.mjs` is the only match gate, and the one check allowed to run longer than 10 minutes. Never
  run any other check longer than 10 minutes.
- Prefer what a player sees or feels (art, house, verbs, UI) over metrics.
- For the four look tasks named in the testing diet, judge your own capture set yourself and use
  the one redo on what looks bad before ticking the task.

5. Before finishing: the full `node autobuild/verify.mjs` must be healthy (this is the one full run,
   just before committing); tick the task in `PLAN.md`;
   prepend an entry to `PROGRESS.md` (date, task id, what changed, what you saw, numbers, what
   is left); log decisions in `DECISIONS.md`; update `ASSETS.md` for any asset; commit with
   a message starting with the task id. Do not push; the loop pushes.
6. If you have budget left after step 5 and the task list continues, you may start the next task.
   Stop at about 60% of your turn budget rather than leaving work half-done.

Use `godot` through `GODOT_BIN` (see `autobuild/README.md`), never through an editor or MCP server.
Do not ask the user anything. If every remaining task is `[B]`, write that in PROGRESS.md and end.
