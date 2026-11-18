# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

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
6. PT4-2's lineup labels then read occupant names from the lobby state on guests too (today a guest
   shows "Player" for another human: `GreyBoxMain._lineup_player`; bots already read "Bot" from
   `SimEntity.is_bot`).

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
