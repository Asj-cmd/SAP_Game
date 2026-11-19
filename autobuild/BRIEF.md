# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT4-8 — Bots catch thieves (last)

**Status 2026-11-19:** step 3 was run. Only the new code fails (pre-PT4-8 0 of 600, current 5 and 11), so PT4-8 stays [~] and waits for a planner decision (top of PROGRESS.md). PT5-1 is ticked; do not re-run its verify for PT4-8.

**Approach**
1. The code, tests and docs are done (`0f2e250`, `3225d56`, `83eb205`, `fde314f`). Do NOT rewrite them.
   The only thing left is one healthy full `node autobuild/verify.mjs`.
2. Normal route: do not run a verify for PT4-8 on its own. Do PT5-1 (below); PT5-1's one full verify
   at its end is PT4-8's too. If it is healthy, tick PT4-8 in `PLAN.md` in PT5-1's final commit
   (`[~]` → `[x]`, drop the "NOT ticked ..." words, keep the numbers), delete this section and the
   note at the top of `PROGRESS.md`.
3. If that verify fails ONLY on the 3v3 tick budget again: run
   `node autobuild/run_tool.mjs perf_probe -- --team-size=3` once on the current code and once with
   the bot files from `0f2e250` checked out into a git worktree (never in the working tree). If both
   are over 5 of 600, it is the machine: write it in `BLOCKED.md` (what was measured, that the old
   code fails the same way) and tick PT4-8 with a note pointing at that entry. If only the new code
   fails, leave `[~]` and log the two numbers in `PROGRESS.md`; no third attempt.

**Already decided**
- No retuning of the six `BotProfileDef` numbers, no new chase scenarios, no catch-time re-run.
- A tick-budget fail that the pre-PT4-8 code shares is load, not a regression (memory note: compare
  old code before fixing). The gate number (≤ 5 of 600) is not changed.

**Files likely touched**: `PLAN.md`, `PROGRESS.md`, maybe `BLOCKED.md`, this file. No code.

**Done means**: one full `verify.mjs` healthy (20 suites at pins incl. `bot_director_test` 54,
symmetry 190/190, bot match 3v3 + 1v1 deterministic with a winner, net smoke OK, 3v3 tick budget
≤ 5 of 600), or the BLOCKED.md route in step 3. No frames.

**Do NOT**: sweeps, seed sweeps, balance tuning, touching `sim/ai/` to "save" tick time, raising
`max_over_budget_ticks`, two verifies at once (they collide on the net_smoke port).
