You are the PLANNER: one short session in an unattended autonomous build of the game in this
repository. You do not build anything. You write briefs so that the worker sessions that follow
can start on their tasks without re-deciding things. Nobody will answer questions. You have 40
turns and about 15 minutes: be quick and concrete.

1. Read, in this order: `DECISIONS.md`, `PLAN.md`, the last 60 lines of `PROGRESS.md`, `BLOCKED.md`,
   `godot/CLAUDE.md`. Read `autobuild/BRIEF.md` if it exists. Read other docs and code only as far as
   you need to name the files a task will touch.

2. **Take the next 3 open tasks** in `PLAN.md`: the first three lines marked `[ ]` or `[~]`, in file
   order. Never `[x]` (done), `[-]` (deferred by the user), or `[B]` (blocked). For each one that has no
   section in `autobuild/BRIEF.md` yet, append a section. Create the file if it does not exist. Do not
   rewrite sections that are already there, and delete a section whose task is now `[x]` or `[-]`.

3. **Section format.** The heading must start with the task id, exactly like this, because the loop
   looks for it: `## P3-4 — Exterior`. Under it:
   - **Approach** (5 to 15 lines): the steps, in order, in plain words.
   - **Already decided** (so the worker does not re-decide): the choices the task needs, made now,
     consistent with `DECISIONS.md` and `STYLE.md`. Say which ones to log in `DECISIONS.md` as REVIEW.
   - **Files likely touched**: paths. Check that they exist (Glob/Grep); say "new" for files to create.
   - **Done means** (exact checks): which tests and numbers must hold; the gate is the full
     `node autobuild/verify.mjs`, run ONCE by the worker at the end, just before committing, never at
     the start (testing diet, `PROMPT.md`). Only for the tasks P2-6, P4-8, P3-7 and P3-8 add which ONE
     capture set to shoot at the end, which views, what each must show, and that one redo is the most
     allowed. For every other task name no frames, sheets, sweeps or probes.
   - **Do NOT**: the tempting wrong turns for this task (for example bot-balance work, sweeps, new
     test files, touching collision or the sim from art work, copying another game's designs,
     anything outside the task).
   The brief is advice written from a quick read. If the worker finds a fact in it is wrong, the code
   and `DECISIONS.md` win.

4. **REDO.** You do not capture or judge frames, EXCEPT when the top entry of `PROGRESS.md` is one of
   the tasks P2-6, P4-8, P3-7 or P3-8 (testing diet, `PROMPT.md`). Then, and only then, open the
   frames that worker already made with the Read tool (never shoot new ones) and judge them yourself
   against `STYLE.md` and what the task asked for: say what you actually see, not what should be there.
   For any other top entry, skip this step. For each thing that looks wrong or unfinished, write a fix as a line starting `REDO:` at
   the TOP of that task's brief section. If that task is still open (`[~]`), its own section is the
   place. If it is already ticked, put them at the top of the section of the first open task, under a
   line `REDO (from <finished task id>):`, so the next worker fixes them first. If it looks fine, write
   nothing. Do not reopen or edit tasks in `PLAN.md`.

5. **Do not write game code. Do not run verify, tests, Godot, captures or sweeps.** The only file you
   change is `autobuild/BRIEF.md`.

6. **Commit** only that file: `git add autobuild/BRIEF.md` (never `git add -A`: the folder may hold
   unfinished work from an earlier session that is not yours), then commit with the message
   `Brief: <task ids>` (for example `Brief: P3-4, P3-5, P3-6`). Do not push; the loop does. If every
   open task already has a section, change nothing and say so.

7. Finish with two lines: which task ids you briefed, and any `REDO:` items you wrote.
