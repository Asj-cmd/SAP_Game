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

## PT5-2 — Minimap that is easy to read

**Approach**
1. Read first, write one or two lines in `PROGRESS.md` on what confuses. From a quick read: the map is
   in `game/greybox/team_tell_overlay.gd` `_draw_map`, data from `minimap_outline.gd`. It is drawn
   ONLY when the D3 option (b) `tell.minimap` is on (off by default, so most players never see it);
   it turns so the own house is at the bottom (`_up` from spawns); it is a fixed 210 px dark box;
   both floors are one flat house rectangle; no labels, no vaults, no jail, no cash; houses are one
   grey, not family colour. Confirm or correct this against the code.
2. Data (`MinimapOutline.build`): keep lot, yards, fence, gates; per house add footprint per floor
   (union of that team's indoor zones on that floor), the CASH_ROOM and JAIL zone centres per floor
   (`ZoneDef.role`, 3D `bounds`), and `upper_floor_y` = the lowest `bounds.position.y` among indoor
   zones above 100. Add a static `floor_of(feet_y, upper_floor_y) -> int` (0 ground, 1 upstairs;
   upstairs when feet are at or above `upper_floor_y - 60`, so a body halfway up a flight still counts
   as ground).
3. Overlay: draw the map whenever `in_match` (no longer gated on `tell.minimap`); `tell.minimap`
   now means D3 (b) "teammates only" (hide enemy pointers when it is on). North-up, fixed: world +x
   right, world −z up, the same on both machines; remove the spawn-based turn (pointers get a fixed
   `up`).
4. Look (`UiTheme` colours/constants, no new palette): cream card with the shared soft shadow,
   lot a muted green, yards a shade lighter, fence a dark line broken at the gates, each house's
   footprint for the shown floor filled with its family colour at ~45 % over cream with a darker
   family-colour outline, the family name (`FamilyNames.name_of(team)`) in the body font, small,
   on that family's lot outside the house. Vault icon: a small dark square with a thin cream slot;
   jail icon: a small square with three vertical bars. Loose cash: small green rounded marks (bundles
   not carried, on the shown floor). Floor label "Ground" / "Upstairs" in the card's top-left corner.
5. Bodies: PT4-5 pointers unchanged in shape; a body on the other floor is drawn at 35 % alpha and
   smaller, so it is not mistaken for someone on yours.
6. Size: the card is 0.2 × viewport height tall, width from the lot's aspect, top-right under the
   status line, clear of the cash bar (check `match_hud.gd` for the bar's rect). Hold `Tab` → the same
   map centred at 0.6 × height. Add `map` to the rebindable keys in `PlayerSettings` `[keys]` (default
   Tab), and a line in `HOW_TO_PLAY.md`.
7. `greybox_main.gd` hands the overlay the loose cash points (from the confirmed world, as the bodies
   are) and the local body's floor. Presentation only.

**Already decided**
- Shown by default in every match; D3 (b) is re-read as "hide enemies on the map". REVIEW.
- North-up fixed (task says so) instead of own-house-at-bottom. REVIEW.
- Other-floor bodies faded, not hidden (you still see someone is upstairs). REVIEW.
- Floor split rule from step 2; icons as in step 4; Tab hold for the big map, rebindable.
- Log these four in `DECISIONS.md` (the first three REVIEW).

**Files likely touched**: `godot/game/greybox/minimap_outline.gd`,
`godot/game/greybox/team_tell_overlay.gd`, `godot/game/greybox/greybox_main.gd`,
`godot/game/greybox/ui_theme.gd` (constants only if missing), `godot/game/greybox/player_settings.gd`
(the `map` key), `godot/tests/match_status_test.gd` (floor choice + icon placement cases),
`autobuild/test_baseline.json`, `HOW_TO_PLAY.md`, `DECISIONS.md`.

**Done means**
- Table cases in the existing `match_status_test.gd` (no new file): `floor_of` at ground, mid-flight,
  landing, upstairs; `MinimapOutline.build` on the real level puts each house's vault(s) and jail on
  the right floor and inside that house's footprint, mirrored between the two houses; pointer shapes
  from PT4-5 still pass. Pin ratcheted.
- One full `node autobuild/verify.mjs` at the end, healthy.
- **ONE capture set at the end** (`--capture-hud` with a chase view; not `--capture-clean`, which hides
  HUD), four frames: (1) ground floor inside the own house: card top-right, "Ground", both lots,
  family-coloured footprints, names on lots, vault/jail icons on the ground floor only, own pointer
  outlined; (2) upstairs: label "Upstairs", the upstairs footprint and its vault, ground-floor icons
  gone; (3) carrying cash (`--pilot=carry`): the carried bundle not drawn as loose cash, other loose
  marks still green; (4) near the gate: fence broken at the gate, own pointer next to it. Also one shot
  with Tab held if `--capture-press` can hold it. Open each with Read and write what it actually
  shows. **At most one redo** of what looks wrong.

**Do NOT**: touch the sim, zones or collision; redraw both floors at once; invent a new palette or
font outside `UiTheme`; add an enemy-cash or enemy-position cheat beyond what the map already showed;
sweeps, probes, render-stats runs; restyle the cash bar or other HUD pieces.
