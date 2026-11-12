You are one session in an unattended, multi-day autonomous build of the game in this repository.
Nobody will answer questions. Decide, log, and keep moving.

1. Read, in this order: `DECISIONS.md`, `PLAN.md`, the last 60 lines of `PROGRESS.md`, `BLOCKED.md`,
   `godot/CLAUDE.md`, `godot/PROJECT_MEMORY.md`. Read other docs only when the task needs them.
2. Run `git status`. If the working tree is dirty, a previous session was cut off: look at the diff,
   finish that work if it is clearly one task, otherwise `git stash` it with a message and continue.
3. Run `node autobuild/verify.mjs --quick`. If it is red, fixing it is your task this session.
4. Otherwise take the **first unchecked task** in `PLAN.md` that is not `[B]` and whose earlier
   dependencies are done. Do that one task properly.
5. Verify as the task says. Visual work: run `node autobuild/verify.mjs --frames` (or the capture
   tool directly), open the PNGs with the Read tool, and say in PROGRESS.md what each frame actually
   showed — not what it should have shown. Fix what you see. Two attempts per problem, then log it
   and move on (see `DECISIONS.md`).
6. Before finishing: `node autobuild/verify.mjs` must be healthy; tick the task in `PLAN.md`;
   prepend an entry to `PROGRESS.md` (date, task id, what changed, what you saw, numbers, what
   is left); log decisions in `DECISIONS.md`; update `ASSETS.md` for any asset; commit with
   a message starting with the task id. Do not push; the loop pushes.
7. If you have budget left after step 6 and the task list continues, you may start the next task.
   Stop at about 60% of your turn budget rather than leaving work half-done.

Use `godot` through `GODOT_BIN` (see `autobuild/README.md`), never through an editor or MCP server.
Do not ask the user anything. If every remaining task is `[B]`, write that in PROGRESS.md and end.
