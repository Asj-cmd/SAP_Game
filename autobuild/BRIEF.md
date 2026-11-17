# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P5-4 — Deadpan feedback

**Approach**
1. Build one presentation-only node, `GameFeedback` (new, `game/greybox/game_feedback.gd`), owned by
   `greybox_main` like `GameAudio` (`var audio: GameAudio` at greybox_main.gd:228). It is driven from
   the same places that already spot events: `_animate` (greybox_main.gd:1474: grab, throw via
   `_act`, `seized` / `freed` lists) and GameAudio's score/phase tracking (deposit = a team's score
   rises). Add one call next to each existing `audio.play(...)`. Never read or write the sim from it
   except the truth world it is handed.
2. **Event line**: a plain text feed, bottom-left of the seat, at most 3 lines, each shown 3 s then
   gone (no fade animation beyond a 0.2 s alpha out). Lines: "<Family> <member> was caught",
   "<Family> <member> was freed", "<Family> banked cash", "<Family> took cash" (a grab of the other
   family's bundle). Family names from `FamilyNames` (P5-0 loader), member words from the slot's
   `FamilyMember` id made plain ("dad", "mom", "elder girl", "younger boy"); your own body reads "You".
3. **Vanish puff** where a seized victim stood (its last drawn position, `_anim_last_seen`): one
   `CPUParticles3D` burst (Compatibility-safe), 8 flat grey-beige quads, 0.4 s, no gravity tricks,
   one_shot, freed after. Same puff, smaller (4 quads), where a freed ally reappears. Nothing else
   gets particles.
4. **Own-body camera nudge**: on your own landing after a jump (the >8 airborne-frame rule GameAudio
   uses) and on being seized, a straight downward nudge of the chase camera, 6 units (landing) /
   12 units (seized), 0.15 s, eased back. Position only, no rotation, no shake. Add it as an offset
   inside `ChaseCamera` that it adds after the spring arm; presentation only.
5. **Seized cut**: when YOUR body is seized, a full-screen black `ColorRect` on the seat, alpha 1 → 0
   over 0.25 s, so the jump to jail reads as a cut, not a glitch. Same, 0.2 s, when you are freed.
6. **Cash number bump**: in `MatchHud`, when a family's banked count rises, that end's label scales
   1.0 → 1.15 → 1.0 over 0.2 s. No colour flash.
7. Run the full verify once, at the end; commit.

**Already decided**
- The five effects above and nothing more: no confetti, no screen shake, no slow-motion, no hit-stop,
  no coloured flashes, no floating "+$" numbers, no sound changes (D2). Log as one REVIEW row:
  "P5-4 deadpan feedback set: event line, vanish puff, camera nudge, seized cut, HUD bump".
- Text: theme font, white at 0.85 alpha, no background box, 16 px.
- Every number (durations, sizes, quad count) is a `const` at the top of `game_feedback.gd` /
  `ChaseCamera`, so tuning is one place.
- Capture runs (`--capture*`, pilot, net smoke) keep the effects (they are cheap) but `--capture-clean`
  hides the event line like the other text layers.

**Files likely touched**
- `godot/game/greybox/game_feedback.gd` (new)
- `godot/game/greybox/greybox_main.gd`
- `godot/game/greybox/chase_camera.gd`
- `godot/game/greybox/match_hud.gd`
- `godot/game/greybox/family_names.gd` (read only, for names)
- `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`

**Done means**
- Full `node autobuild/verify.mjs` healthy, run ONCE at the end: all suites at their pinned counts in
  `autobuild/test_baseline.json` (no count changes, no new tests: this is presentation), symmetry
  exact, bot 3v3 and 1v1 deterministic as before (presentation cannot move them; if they move, the
  sim was touched by mistake), net_smoke agrees, tick budget within the gate.
- A headless `--solo` run prints no script errors.
- No frames (testing diet); say in PROGRESS.md that the effects are unseen.

**Do NOT**
- Touch `sim/`, collision, zones or `content/` numbers.
- Add tests, frame captures, contact sheets or sweeps.
- Add cartoon effects of any kind (stars, sparkles, coins flying, bright colours, squash-stretch).
- Rework GameAudio or the HUD layout beyond the label bump.
- Use GPUParticles (CPUParticles3D only, Compatibility).

## P5-5 — First-run clarity

**Approach**
1. **Controls strip**: a one-line hint at the bottom centre of the seat during a match, built from
   `PlayerSettings.key_for` (so it follows rebinding; also fixes the P5-2 note that the [E] free prompt
   is a fixed E: make `MatchHud`'s prompt use `key_for(&"seize")` too). Text: "WASD move · Mouse look
   · Space jump · Shift crouch · LMB grab/drop · RMB throw · E seize/free · Esc menu" with the real
   key names (`OS.get_keycode_string`). Shown for the first 60 s of every match and whenever the
   guide (below) is on; toggled off afterwards. Hidden by `--capture-clean`.
2. **Guide**: a small presentation-only step list, `FirstRunGuide` (new,
   `game/greybox/first_run_guide.gd`), one line under the top bar ("Step 2 of 5: ..."). Each step
   advances on a condition read from the truth world for the local actor:
   1. "Move with WASD, look with the mouse" → moved 300 units.
   2. "Cross the fence into the other family's yard" → `world.zone_at(pos).owner_team` is the
      other team.
   3. "Find their cash and grab it (LMB)" → `is_carrying()`.
   4. "Carry it back into your own house" → own team's score rises (or carrying while on own ground;
      take the score rise).
   5. "Catch intruders at home with E. If you are caught, a teammate frees you" → shown 8 s, then done.
   A step that is not met in 20 s shows a second plain sentence (where to look: "Their house is
   across the fence, behind you" etc.). No arrows in the world, no camera takeover (D9: nothing takes
   control away).
3. **First run**: `PlayerSettings` gains `[firstrun] guide_done` (bool, default false). On the first
   solo or hosted match the guide runs; finishing step 5 or pressing F9 (skip) sets it true and saves.
   The main menu gets a "How to play" button that clears the flag (the next match shows the guide)
   and shows a plain panel with the controls list and three sentences of rules (steal cash from the
   other house, bring it home; seize intruders on your side; free jailed teammates).
4. The guide works in a normal match with bots (no special mode, no new sim rules). Guests see it too,
   driven by their own confirmed world.
5. Capture/pilot/net-smoke runs ignore the saved settings already (P5-1); make the guide OFF in them.
6. Full verify once at the end; commit.

**Already decided**
- No separate tutorial level or mode; the "60-second guided first match" is the guide over a normal
  match (REVIEW, log it: "first match guide is a step line over a normal match, not a tutorial mode").
- Skip key F9 (free F-key; F1 debug HUD, F2-F4 debug, F5-F8 team tell, F10 menu, F12 capture). Log it.
- Step texts as above; plain sentences, no exclamation marks (D2 deadpan). Log REVIEW.
- Settings section `[firstrun]`, key `guide_done`. Log it.

**Files likely touched**
- `godot/game/greybox/first_run_guide.gd` (new)
- `godot/game/greybox/greybox_main.gd`
- `godot/game/greybox/match_hud.gd` (prompt key text)
- `godot/game/greybox/player_settings.gd`
- `godot/game/greybox/main_menu.gd` (How to play button + panel)
- `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`

**Done means**
- Full `node autobuild/verify.mjs` healthy, run ONCE at the end, suites at pinned counts (no test
  changes: `game/` is never tested), bot matches unchanged, net_smoke agrees.
- A headless `--solo` run prints no script errors.
- No frames; say the guide and strip are unseen.

**Do NOT**
- Build a scripted tutorial level, spawn special bots, pause the sim, or freeze the player.
- Put the guide's decisions in `sim/` or write tests for it.
- Add world arrows, glowing outlines or other markers (team tell options stay as they are, P2-4).
- Capture frames or run the pilot as a check.

## P6-1 — Loss and lag

**Approach**
1. New `LinkConditions` (new, `godot/net/link_conditions.gd`, RefCounted): `latency_ms` (one way),
   `jitter_ms` (0 default), `loss` (0..1), `seed`, and a `clock: Callable` (default
   `Time.get_ticks_msec`) so a test can drive time by hand.
2. `LoopbackTransport` gains `var conditions: LinkConditions = null`. Null = today's immediate,
   lossless behaviour, unchanged byte for byte (it is the reference; keep its doc comment true by
   saying the conditions are opt-in). With conditions, `send` puts `{due_ms, payload, from}` in the
   receiver's pending queue; `poll` moves due entries to the inbox.
   - UNRELIABLE: dropped with probability `loss` (own seeded RNG), may arrive out of order with jitter.
   - RELIABLE (everything today: nothing in the code sends UNRELIABLE): never dropped; a "lost" packet
     arrives one extra round trip later (2 × latency, ENet-like resend), and delivery stays in order
     per sender (due = max(due, previous due from that sender)).
   - Session/peer events (ready, joined, left) are not delayed.
3. `tools/net_loopback.gd`: accept `--latency-ms=` `--loss=` `--jitter-ms=` and give both ends the
   conditions (loopback backend only). Its per-packet wait is 2000 ms, which is enough. Run it at
   `--latency-ms=100 --loss=0.05` and expect IN LOCKSTEP with the same scores as without.
4. `tools/net_prediction.gd` already takes `--latency=` in ticks (30 Hz: 100 ms = 3 ticks). Add
   `--loss=` there with the same reliable model (a lost packet arrives 2 × latency ticks later, in
   order; seeded). Run at `--latency=3 --loss=0.05` and `--latency=6 --loss=0.05`; expect CONSISTENT,
   record the own-position prediction error it prints in PROGRESS.md.
5. If either diverges: that is a real defect; find the first disagreeing tick (both tools print it),
   fix it in `net/` (two attempts max, then BLOCKED.md and `[~]`).
6. Add rows to the EXISTING `tests/transport_test.gd` (table-driven, loopback only, fake clock):
   nothing before latency, delivered at latency, reliable never lost and in order under loss 1.0,
   unreliable dropped at loss 1.0 and kept at 0.0, null conditions = immediate. Ratchet
   `transport_test` in `autobuild/test_baseline.json` (now 28).
7. Add one line to the Network block of `autobuild/verify.mjs`: net_loopback with
   `--latency-ms=100 --loss=0.05`, verdict "IN LOCKSTEP" (full verify only, not `--quick`).
8. Note in `godot/ARCHITECTURE.md` (net section, two lines) that loopback can simulate lag/loss and
   that every channel is reliable today. Full verify once at the end; commit.

**Already decided**
- Latency in wall-clock ms on the transport (the lockstep harness waits on the wall clock); in ticks
  in net_prediction (it has no transport). Log it.
- Reliable-under-loss = later, never missing (ENet reliable model); unreliable = dropped. Log it.
- The gate condition is 100 ms one way + 5% loss, as PLAN.md says. Log it.
- ENet and net_smoke get no loss injection (ENet has none built in; out of scope). Log it.

**Files likely touched**
- `godot/net/link_conditions.gd` (new)
- `godot/net/loopback_transport.gd`
- `godot/tools/net_loopback.gd`, `godot/tools/net_prediction.gd`
- `godot/tests/transport_test.gd`, `autobuild/test_baseline.json`
- `autobuild/verify.mjs`
- `godot/ARCHITECTURE.md`, `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`

**Done means**
- `transport_test` passes with its new count pinned; the null-conditions rows prove the reference
  path is unchanged.
- net_loopback at 100 ms / 5 % prints IN LOCKSTEP with the same host/guest scores as the plain run.
- net_prediction at 3 and 6 ticks with 5 % loss prints CONSISTENT; its error numbers are in PROGRESS.md.
- Full `node autobuild/verify.mjs` healthy, run ONCE at the end, including the new network line.

**Do NOT**
- Change the default (no-conditions) loopback behaviour, the snapshot format or the command codec
  unless a divergence proves it necessary.
- Start the Steam transport (P6-3) or host modes (P6-2).
- Switch any channel to UNRELIABLE as an "optimisation".
- Touch `sim/`, bots, or run sweeps; no frames.
