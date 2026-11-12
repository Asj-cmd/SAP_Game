# Decisions — how to decide without asking

The user is away most of the day and wants the project to move. **Decide, record, continue.**
Stopping to ask is the most expensive thing a session can do.

## Three kinds of decision

1. **Decide and log.** Anything reversible, local, or a matter of taste with a sane default:
   pick, write one line in the log below (date · task · decision · why · how to undo), continue.
2. **Decide, log, and flag `REVIEW`.** Anything the user will care about seeing: art style pick,
   character looks, how teams are told apart, tone of sounds. Pick the best option, log it with
   `REVIEW`, build so that changing it is cheap (theme resource, data file). The user reviews in the evening.
3. **Block.** Only these stop work on a task: it needs **money**, a **login/account the user must
   create**, a **secret/credential**, an **installation on the user's machine you cannot do**, or it
   would **reverse a settled decision**. Write it in `BLOCKED.md` (what, why, what the user must do,
   what you did instead), mark the task `[B]`, and **move on to the next task**. Never idle.

## Never, without the user

- Spend money or start a paid trial. Free tiers and credits already on the account are fine if the
  terms allow commercial use; record the terms in `ASSETS.md`.
- Publish anything, upload to Steam/itch/any store, post anywhere, email anyone.
- Put secrets in the repo. Force-push, rewrite history, or delete branches.
- Use assets with unclear, non-commercial, or no-derivatives licences, or ripped from other games.
- Reopen the settled decisions in `godot/DESIGN_DIRECTION.md` §4 without *new measured evidence*.

## When stuck

`godot/CLAUDE.md` caps failure loops at two fix attempts. In autonomous mode the rule becomes:
**two attempts, then log what failed / what you tried / your diagnosis in `BLOCKED.md`, mark the
task `[~]` or `[B]`, and move to the next task.** A failure that blocks everything downstream
(the build is red and you cannot fix it) is the only reason to end a session early: revert to the
last green commit (`git revert`, not reset), say so in PROGRESS.md.

## Working agreements

- **Measure before changing; build the instrument first.** (`godot/PROJECT_MEMORY.md` §3.)
- Keep `verify.mjs` green at every commit. Ratchet the baseline when you add tests or tighten a metric.
- One task, one or a few commits: `P1-4: toon shader with outline pass`. Push is done by the loop.
- Visual work is done only when you have opened a frame with the Read tool and described what you saw.
- Presentation never writes to the simulation; art never changes collision, zones or numbers
  in `content/` unless the task says so.
- Prefer one coherent look over more content. Cut scope before cutting polish; a smaller
  good-looking game beats a larger patchy one.

## Settled at autobuild start

| ID | Decision | Why / how to undo |
|---|---|---|
| D1 | Engine stays **Godot 4.7, Compatibility renderer, typed GDScript**. The Three.js client/server is legacy. | The sim, netcode and tooling are healthy and tested; the dev GPU cannot run Forward+. |
| D2 | Look: **stylised toon cartoon** with outlines, saturated palette, one shared `ArtTheme`. Assets from CC0/purchased/AI-generated sources, unified by the theme. | Mixed sources look coherent only under one shader and palette. Undo = edit the theme. |
| D3 | Characters: **four family designs, identical on both teams** (the chaos), teams told apart by **outfit accent colour + outline tint + HUD marker**. `REVIEW`. NB: the repo already has two blocky Blender characters (`character_a/b`); P2-1 decides keep / restyle / replace. | If chaos hurts readability, colour more of the outfit. One data change. |
| D4 | Steam is the distribution target; itch.io and friend-testing via Tailscale/LAN remain supported. | See the earlier planning chats. |
| D5 | The build is **host-authoritative** over the existing session/transport interface; Steam is a new transport backend, not a rewrite. | `ARCHITECTURE.md` §3. |
| D7 | Settled in the repo, not reopened: vault verb removed (jump does it); escape windows are one-way drops on faces away from the enemy house; carriers move at 0.85 of walking speed; art is 1 unit = 1 cm and optional via fallback. | `godot/PROJECT_MEMORY.md`, `godot/art/README.md`. |
| D6 | Dev machine is a GT 730M laptop: all art must fit the Compatibility renderer and the budgets in `STYLE.md`. | Do not add Forward+-only features. |

## Log

| Date | Task | Decision | Why | Undo |
|---|---|---|---|---|
| | | | | |
