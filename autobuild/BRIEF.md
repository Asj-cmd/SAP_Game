# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT4-2 — Family spawn

**Approach**
1. Spawns are `SPAWN_LOCAL` in `godot/tools/build_house.gd` (house-local, turned for House B by
   `_place_point`); the game loads the BAKED `godot/content/levels/house.tres`, so re-bake with
   `node autobuild/run_tool.mjs bake_blockout_headless` after the change (PT4-1's lesson).
2. Replace the four points with one row on the front lawn, in slot order: house-local
   `(300, -150)`, `(550, -150)`, `(800, -150)`, `(1050, -150)` (the front strip is 350 deep; the front
   door jamb is near x 1440, so the row stays clear of the doorway). If a point hits a blocker or a
   prop, shift the whole row along x, keeping 250 spacing.
3. Lineup length: set `pre_round_seconds` 2.0 → 3.0 in `godot/content/modes/house_1v1.tres`,
   `house_2v2.tres`, `house_3v3.tres`, `house_4v4.tres`. The sim's countdown already freezes movement,
   so it is the "hold still" rule; no new sim rule.
4. Presentation (`godot/game/greybox/greybox_main.gd`, new `godot/game/greybox/family_lineup.gd`):
   while the confirmed world is in `MatchPhase.COUNTDOWN`, the local seat's view uses a fixed
   Camera3D standing about 600 in front of its own family's row, at about 150 high, looking at the
   row; every drawn body of that family faces the camera (outward from the house). Above the row:
   the family name (`FamilyNames.name_of`); under each body: role and who plays it. Back to the chase
   camera when PLAYING starts. SimEntity has no facing field, so facing is drawn only.
5. Labels: role from `ArtTheme.member_for(team, slot, false)`: Dad, Mom, Daughter, Son (add
   "Elder"/"Younger" only when both kids are the same sex). Who plays it: "You" for the local seat;
   on the host the lobby seat's `display_name` or "Bot"; on a guest "Player" for other bodies (PT4-3
   adds the roster to the lobby message). UiTheme fonts, 2D labels placed with
   `Camera3D.unproject_position`.

**Already decided**
- Front lawn lineup, not the hall: it is outside, already where two spawns are, and the camera has
  room. Log in `DECISIONS.md` (decide and log).
- Countdown 3 s every round, all sizes (data). Log as REVIEW (it is how long every round starts).
- The lineup is shown each round start, own family only.

**Files likely touched**: `godot/tools/build_house.gd`, `godot/content/levels/house.tres`
(re-baked), `godot/content/modes/house_{1v1,2v2,3v3,4v4}.tres`, `godot/game/greybox/greybox_main.gd`,
`godot/game/greybox/family_lineup.gd` (new), `godot/tests/greybox_level_test.gd`,
`autobuild/test_baseline.json`, `DECISIONS.md`.

**Done means**
- `greybox_level_test` gains one table over team sizes 2, 3, 4: each spawn mirrors its twin about
  (3640, 1860), no two bodies closer than two body radii, no spawn inside a collision blocker, the
  same points on a second load. Ratchet its pin.
- Symmetry probe passes; bot match 3v3 still ends with a winner within its stall budget (spawn and
  countdown move the numbers; record the new ones).
- Full `node autobuild/verify.mjs`, once, at the end, before committing. No frames.

**Do NOT**
- Add a sim phase, a facing field or a snapshot change; touch the bots or retune round length to
  fix a bot-match result (two attempts, then BLOCKED.md per the rules).
- Edit `house.tscn` by hand or forget the re-bake.
- Capture frames or run sweeps.

## PT4-3 — Choose your family member

**Approach**
1. A member IS a seat slot: slot n of a family draws `ArtTheme.member_for(team, n, false)`, and
   only slots 0..team_size-1 exist, so offering "only the members that exist at this size" is
   listing that family's slots (2v2: Dad, Mom; 3v3 adds Daughter; 4v4 adds Son).
2. `Lobby` (`godot/net/lobby.gd`, pure, tested): each human seat holder has a choice (a slot, or
   RANDOM, default). `admit` takes an optional wanted slot. New `choose(identity, slot)`: allowed
   only in `Phase.GATHERING`, on the player's own family; refused with a reason ("taken by <name>")
   if another player explicitly chose it; a seat a Random player only sits on provisionally is not a
   block (that player is moved to another free slot). New `resolve_random(rng)` at Start puts the
   Random players on the free slots of their family; bots then fill what is left (existing fill).
   Rejoin already returns the same seat by identity: keep it.
3. Moving a human to another seat changes their actor: the host sends the peer a fresh
   `frame_seat` (`godot/net/match_channel.gd`), and the guest's TAG_SEAT handling in
   `godot/game/greybox/match_link.gd` adopts the new actor id.
4. Message: extend PT3-3's `LobbyState` (`godot/net/lobby_state.gd`) to version 2: the names plus,
   per seat, team, slot, occupant (human name, bot, empty) and choice. A guest's request is a
   TAG_LOBBY frame "choose slot n"; the host answers by broadcasting the state (a refused request
   also gets the reason back to that peer).
5. UI: in `godot/game/greybox/lobby_panel.gd`, next to each family's name box, an OptionButton
   (Random + the existing members); taken ones disabled with the taker's name. On the main menu
   (`godot/game/greybox/main_menu.gd`) the same picker for solo, rebuilt when the team-size picker
   changes; `MatchLink.seat_local` passes the wanted slot.
6. PT4-2's lineup labels then read occupant names from the lobby state on guests too.

**Already decided**
- Random resolves on the host at Start with the host's own RandomNumberGenerator (not the sim's
  RNG), so solo no longer always plays Dad. Log (decide and log).
- Labels use the member without kid swap; kid swap is a per-machine tell option and may draw the
  kids the other way round on that machine. Log as REVIEW.
- Players do not change family here; the existing even split stays.

**Files likely touched**: `godot/net/lobby.gd`, `godot/net/lobby_seat.gd`, `godot/net/lobby_state.gd`,
`godot/net/match_channel.gd`, `godot/game/greybox/match_link.gd`, `godot/game/greybox/lobby_panel.gd`,
`godot/game/greybox/main_menu.gd`, `godot/game/greybox/greybox_main.gd`, `godot/tests/lobby_test.gd`,
`autobuild/test_baseline.json`, `DECISIONS.md`.

**Done means**
- `lobby_test` gains one table: explicit duplicate refused with a reason, Random never takes an
  explicit pick, explicit pick displaces a Random player, every team size offers exactly its slots,
  choose refused after the match starts, rejoin keeps the member, bots take only leftovers; plus the
  version-2 encode/decode round trip. Ratchet the pin.
- Full `node autobuild/verify.mjs`, once, at the end, before committing (net_smoke must stay green).
  No frames.

**Do NOT**
- Put the choice in the sim snapshot or the input stream; change bot behaviour; let players switch
  families; add new test files; capture frames.
