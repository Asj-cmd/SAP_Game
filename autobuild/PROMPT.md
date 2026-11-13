You are one session in an unattended, multi-day autonomous build of the game in this repository.
Nobody will answer questions. Decide, log, and keep moving.

1. Read, in this order: `DECISIONS.md`, `PLAN.md`, the last 60 lines of `PROGRESS.md`, `BLOCKED.md`,
   `godot/CLAUDE.md`, `godot/PROJECT_MEMORY.md`. Read other docs only when the task needs them.
2. Run `git status`. If the working tree is dirty, a previous session was cut off: look at the diff,
   finish that work if it is clearly one task, otherwise `git stash` it with a message and continue.
   Ignore changes that are only to .import files under godot/art - Godot rewrites them on every run; restore them with git checkout -- <file>.
3. Run `node autobuild/verify.mjs --quick`. If it is red, fixing it is your task this session.
4. Otherwise take the **first unchecked task** in `PLAN.md` that is not `[B]` and whose earlier
   dependencies are done. Do that one task properly.
5. Verify as the task says. Visual work: run `node autobuild/verify.mjs --frames` (or the capture
   tool directly), open the PNGs with the Read tool, and say in PROGRESS.md what each frame actually
   showed — not what it should have shown. Fix what you see. Two attempts per problem, then log it
   and move on (see `DECISIONS.md`).

**Testing budget.** While working, run only the single test suite related to what you changed
(one `tests/*_test.gd` file with Godot). Run the full `node autobuild/verify.mjs` at most twice per
task: once at the start and once before committing. Run `--frames` only for visual tasks, after the
change is done. Do not write new test files except a table-driven test for a new simulation
decision (`godot/CLAUDE.md` policy). Measurement runs that ARE the task (tuning sweeps, profiling)
are fine, but plan them up front, note what each run is for, and stop when you have the answer.

**Commit often.** Commit working progress at least every 45 minutes, whenever
`node autobuild/verify.mjs --quick` is green, with a message like `P1-4 (part): ...`. A session can
be cut off at 2 hours; uncommitted work is at risk.

6. Before finishing: `node autobuild/verify.mjs` must be healthy; tick the task in `PLAN.md`;
   prepend an entry to `PROGRESS.md` (date, task id, what changed, what you saw, numbers, what
   is left); log decisions in `DECISIONS.md`; update `ASSETS.md` for any asset; commit with
   a message starting with the task id. Do not push; the loop pushes.
7. If you have budget left after step 6 and the task list continues, you may start the next task.
   Stop at about 60% of your turn budget rather than leaving work half-done.

Use `godot` through `GODOT_BIN` (see `autobuild/README.md`), never through an editor or MCP server.
Do not ask the user anything. If every remaining task is `[B]`, write that in PROGRESS.md and end.
